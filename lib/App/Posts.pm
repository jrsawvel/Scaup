package Posts;

use strict;
use warnings;

use CouchDB::Client;
use HTML::Entities;
use Encode;
use LWP::UserAgent;
use Text::Markdown;
use Text::Textile;
use JSON::PP;
use Cache::Memcached::libmemcached;
# use URI::Escape;

use App::Config;
use App::Page;
use App::Utils;
use App::PostTitle;


sub show_stream {
    my $tmp_hash = shift;

    my $page_num = 1;
    if ( Utils::is_numeric($tmp_hash->{one}) ) {
        $page_num = $tmp_hash->{one};
    }

    my $rc;

    my $db = Config::get_value_for("database_name");

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    my $max_entries = Config::get_value_for("max_entries_on_page");

    my $skip_count = ($max_entries * $page_num) - $max_entries;

    my $couchdb_uri = $db . '/_design/views/_view/stream/?descending=true&limit=' . ($max_entries + 1) . '&skip=' . $skip_count;

    $rc = $c->req('GET', $couchdb_uri);

    my $stream = $rc->{'json'}->{'rows'};

    my $next_link_bool = 0;
    my $len = @$stream;
    if ( $len > $max_entries ) {
        $next_link_bool = 1;
    }

    my @posts;

    foreach my $hash_ref ( @$stream ) {
        $hash_ref->{'value'}->{'updated_at'} = Utils::format_date_time($hash_ref->{'value'}->{'updated_at'});
        push(@posts, $hash_ref->{'value'});
    }

    my $t = Page->new("stream");
    $t->set_template_variable("loggedin", User::get_logged_in_flag());
    $t->set_template_loop_data("stream_loop", \@posts);

    if ( $page_num == 1 ) {
        $t->set_template_variable("not_page_one", 0);
    } else {
        $t->set_template_variable("not_page_one", 1);
    }

    if ( $len >= $max_entries && $next_link_bool ) {
        $t->set_template_variable("not_last_page", 1);
    } else {
        $t->set_template_variable("not_last_page", 0);
    }
    my $previous_page_num = $page_num - 1;
    my $next_page_num = $page_num + 1;
    my $next_page_url = "/stream/$next_page_num";
    my $previous_page_url = "/stream/$previous_page_num";
    $t->set_template_variable("next_page_url", $next_page_url);
    $t->set_template_variable("previous_page_url", $previous_page_url);

    $t->display_page("Stream of Posts");
}

sub show_search_form {
    my $t = Page->new("searchform");
    $t->display_page("Search form");
}

sub create_post {
    my $db = Config::get_value_for("database_name");

    my $q = new CGI;
    my $original_markup = $q->param("markup");

    my $markup = Utils::trim_spaces($original_markup);
    if ( !defined($markup) || length($markup) < 1 ) {
        Page->report_error("user", "Invalid post.", "You most enter text.");
    } 

    my $markup = Encode::decode_utf8($markup);
# since it's a single-user app, then no need to encode????
#    $markup    = HTML::Entities::encode($markup,'^\n^\r\x20-\x25\x27-\x7e');

    my $submit_type = $q->param("sb"); # Preview or Post 

    my $post_location = $q->param("post_location"); # notes_stream or ?

    my $logged_in_author_name  = User::get_logged_in_author_name(); 
    my $session_id   = User::get_logged_in_session_id(); 

    my $author = Config::get_value_for("author_name");

    if ( $logged_in_author_name ne $author ) {
        Page->report_error("user", "Unable to peform action.", "You are not logged in.");
    }

    my $type        = "post";
    my $post_status = "public";
    my $created_at  = Utils::create_datetime_stamp();
    my $updated_at  = $created_at;

#    my $formatted_created_at  = Utils::format_date_time($created_date);
#    my $formatted_updated_at  = $formatted_created_at;

    my $o = PostTitle->new();
    $o->process_title($markup);
    my $title           = $o->get_post_title();
    my $post_type       = $o->get_content_type(); # article or note
    if ( $o->is_error() ) {
        Page->report_error("user", "Error creating post.", $o->get_error_string());
    } 
    my $markup_type = $o->get_markup_type();

    my $slug     = $o->get_slug();

    my $html = Utils::hashtag_to_link($markup);

    if ( $markup_type eq "textile" ) {
        my $textile = new Text::Textile;
        $html = $textile->process($html);
    } else {
        my $md   = Text::Markdown->new;
        $html = $md->markdown($html);
    }

    # why do this?
    $html =~ s/&#39;/'/sg;


    if ( $submit_type eq "Preview" ) {
        my $t = Page->new("newpostform");
        $t->set_template_variable("previewingpost", 1);
        $t->set_template_variable("html", $html);
        $t->set_template_variable("markup", $original_markup);
        $t->display_page("Previewing new post");
        exit;
    }


    my $tmp_post = $html;
    $tmp_post =~ s|<h1>|\[h1\]|;
    $tmp_post =~ s|</h1>|\[/h1\]|;

    $tmp_post = Utils::remove_html($tmp_post);
    my @tmp_arr = split(/\s+/s, $tmp_post);
    my $word_count = @tmp_arr;
    my $reading_time = 0; #minutes
    $reading_time  = int($word_count / 180) if $word_count >= 180;

    my $more_text_exists = 0; #false
    my $text_intro = $tmp_post;
    if ( length($tmp_post) > 300 ) {
        $text_intro = substr $tmp_post, 0, 300;
        $text_intro .= " ...";
        $more_text_exists = 1;
    }

    $text_intro =~ s|\[h1\]|<span class="streamtitle"><a href="/$slug">|;
    $text_intro =~ s|\[/h1\]|</a></span> - |;
    $text_intro = Utils::remove_newline($text_intro);

    if ( !$more_text_exists ) {
        $text_intro = Utils::url_to_link($text_intro);
        $text_intro = Utils::hashtag_to_link($text_intro);
    }

    my @tags = Utils::create_tag_array($markup);

    my $cdb_hash = {
    '_id'                   =>  $slug,
#    'slug'              =>  $slug,
#    'post_id'           =>  Utils::create_random_string(),
    'type'                  =>  'post',
    'title'                 =>  $title,
    'markup'                =>  $markup,
    'html'                  =>  $html,
    'text_intro'            =>  $text_intro,
    'more_text_exists'      =>  $more_text_exists,
    'post_type'             =>  $post_type,
    'tags'                  =>  \@tags,
    'author'                =>  $author,
    'created_at'            =>  $created_at,
    'updated_at'            =>  $updated_at,
#    'formatted_created_at'  =>  $formatted_created_at,
#    'formatted_updated_at'  =>  $formatted_updated_at,
    'reading_time'          =>  $reading_time,
    'word_count'            =>  $word_count,
    'post_status'           =>  $post_status
    };

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    my $rc = $c->req('POST', $db, $cdb_hash);

    if ( $rc->{status} >= 300 ) {
        Page->report_error("user", "Unable to create post.", $rc->{msg});
    }

    if ( Config::get_value_for("write_html_to_memcached") ) {
        _write_html_to_memcached($rc->{'json'}->{'id'});
    }

    if ( $post_location eq "notes_stream" ) {
        my $home_page = Config::get_value_for("home_page");
        print $q->redirect( -url => $home_page);
        exit;
    } else {
        my $home_page = Config::get_value_for("home_page");
        print $q->redirect( -url => $home_page . "/" . $rc->{'json'}->{'id'} );
        exit;
    }
}

# old show post sub
# for some reason, the CouchDB::Client module is slow when returning a 37-minute read (6751 words).
sub _do_not_use_ {
    my $tmp_hash = shift; 

    my $post_id = $tmp_hash->{function}; 
    
    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    my $db = Config::get_value_for("database_name");

    my $rc = $c->req('GET', $db . "/_design/views/_view/post?key=\"$post_id\"");

    if ( !$rc->{'json'}->{'rows'}->[0]->{'value'} ) {
        Page->report_error("user", "Unable to display post.", "Post ID \"$post_id\" was not found.");
    }

    my $post = $rc->{'json'}->{'rows'}->[0]->{'value'};

    my $slug = $rc->{'json'}->{'rows'}->[0]->{'id'};

    my $t = Page->new("post");

    $t->set_template_variable("html",            $post->{'html'});
    $t->set_template_variable("author",          $post->{'author'});
    $t->set_template_variable("created_at",      $post->{'created_at'});
    $t->set_template_variable("updated_at",      $post->{'updated_at'});
    $t->set_template_variable("reading_time",    $post->{'reading_time'});
    $t->set_template_variable("word_count",      $post->{'word_count'});
    $t->set_template_variable("slug",            $slug);
    $t->set_template_variable("author_profile",  Config::get_value_for("author_profile"));

    if ( $post->{'created_at'} ne $post->{'updated_at'} ) {
        $t->set_template_variable("modified", 1);
    }

    $t->display_page($post->{'title'});

}

sub show_post {
    my $tmp_hash = shift; 
    my $creation_type = shift;

    my $post_id = $tmp_hash->{function}; 
   
    my $ua = LWP::UserAgent->new;

    my $db = Config::get_value_for("database_name");
    my $url = "http://127.0.0.1:5984/" . $db . "/_design/views/_view/post?key=\"$post_id\"";

    my $response = $ua->get($url);

    if ( !$response->is_success ) {
        # Page->report_error("system", "Database error.", "The server cannot be reached.");
        Page->report_error("user", "Unable to display post.", "Post ID \"$post_id\" was not found.");
    }

    my $rc = decode_json $response->content;

    my $post = $rc->{'rows'}->[0]->{'value'};

    if ( !$post ) {
        Page->report_error("user", "Unable to display post.", "Post ID \"$post_id\" was not found.");
    }

    my $slug = $rc->{'rows'}->[0]->{'id'};

    my $t = Page->new("post");

    if ( $creation_type eq "private" ) {
        $t->set_template_variable("loggedin", 0);
    } else {
        $t->set_template_variable("loggedin", User::get_logged_in_flag());
    }

    my $cache_it = 0;
    if ( !User::get_logged_in_flag() and Config::get_value_for("write_html_to_memcached") ) {
        $cache_it = 1;
    }

    $t->set_template_variable("html",            $post->{'html'});
    $t->set_template_variable("author",          $post->{'author'});
    $t->set_template_variable("created_at",      Utils::format_date_time($post->{'created_at'}));
    $t->set_template_variable("updated_at",      Utils::format_date_time($post->{'updated_at'}));
    $t->set_template_variable("reading_time",    $post->{'reading_time'});
    $t->set_template_variable("word_count",      $post->{'word_count'});
    $t->set_template_variable("post_type",       $post->{'post_type'});
    $t->set_template_variable("slug",            $slug);
    $t->set_template_variable("author_profile",  Config::get_value_for("author_profile"));

    if ( $post->{'created_at'} ne $post->{'updated_at'} ) {
        $t->set_template_variable("modified", 1);
    }

    if ( $creation_type ne "private" ) {
        $t->display_page($post->{'title'}, $cache_it, $post_id);
    } else {
        return $t->create_html($post->{'title'});
    }
}

sub search {
    my $tmp_hash = shift;  

    my $keyword = $tmp_hash->{one};

    my $page_num = 1;

    if ( Utils::is_numeric($tmp_hash->{two}) ) {
        $page_num = $tmp_hash->{two};
    }

    if ( !defined($keyword) ) {
        my $q = new CGI;
        $keyword = $q->param("keywords");

        if ( !defined($keyword) ) {
            Page->report_error("user", "Missing data.", "Enter keyword to search on.");
        }
        
        $keyword = Utils::trim_spaces($keyword);
        if ( length($keyword) < 1 ) {
            Page->report_error("user", "Missing data.", "Enter keyword to search on.");
        }
        
        # $keyword =~ s/ /\+/g;
        # $keyword = uri_escape($hash{search_string});
    }


    my $rc;

    my $db = Config::get_value_for("database_name");

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    # $rc = $c->req('GET', $db . "/_design/views/_view/single_word_search?key=\"$keyword\"&descending=true");
    $rc = $c->req('GET', $db . "/_design/views/_view/single_word_search?startkey=[\"$keyword\", {}]&endkey=[\"$keyword\"]&descending=true");

    my $stream = $rc->{'json'}->{'rows'};

    if ( !$stream ) {
        Page->success("Search results for $keyword", "No matches found.", "");
    }

    my $number_of_matches = @$stream;
    if ( $number_of_matches < 1 ) {
        Page->success("Search results for $keyword", "No matches found.", "");
    }

    my @posts;

    my %post_hash;

    # grab the hash of info for each post and collapse the search results, 
    # since a result is returned for each time the search word appears within
    # the same post. obviously, we only want to display each article once.
    # without collapsing, if the search term appeared five times within the same
    # article, then five results will be returned from the view. code below
    # collapses it down to one result.
    foreach my $hash_ref ( @$stream ) {
        my $tmp_slug = $hash_ref->{'value'}->{'slug'};
        $hash_ref->{'value'}->{'updated_at'} = Utils::format_date_time($hash_ref->{'value'}->{'updated_at'});
        push(@posts, $hash_ref->{'value'}) if !exists $post_hash{$tmp_slug}; 
        $post_hash{$tmp_slug} = 1;    
    }

    my $t = Page->new("stream");
    $t->set_template_loop_data("stream_loop", \@posts);
    $t->set_template_variable("search", 1);
    $t->set_template_variable("keyword", $keyword);
    $t->set_template_variable("search_type_text", "Search");
    $t->set_template_variable("search_type", "search");
    $t->display_page("Search results for $keyword");
}


sub delete {
    my $tmp_hash = shift; # ref to hash
    my $post_id = $tmp_hash->{one};

    my $author_name  = User::get_logged_in_author_name(); 
    my $session_id   = User::get_logged_in_session_id(); 


    my $db = Config::get_value_for("database_name");

    my $rc;

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    $rc = $c->req('GET', $db . "/$post_id");

    if ( !$rc->{'json'} ) {
        Page->report_error("user", "Unable to delete post.", "Post ID \"$post_id\" was not found.");
    }

    my $perl_hash = $rc->{'json'};
    
    if ( !$perl_hash ) {
        Page->report_error("user", "Unable to delete post.", "Post ID \"$post_id\" was not found.");
    }

    $perl_hash->{'post_status'} = "deleted";

    $rc = $c->req('PUT', $db . "/$post_id", $perl_hash);

    my $url = Config::get_value_for("home_page");
    my $q = new CGI;
    print $q->redirect( -url => $url);

}

sub show_deleted_posts {

    my $rc;

    my $db = Config::get_value_for("database_name");

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    $rc = $c->req('GET', $db . '/_design/views/_view/deleted_posts/?descending=true');

    my $deleted = $rc->{'json'}->{'rows'};

    my @posts;

    foreach my $hash_ref ( @$deleted ) {
        push(@posts, $hash_ref->{'value'});
    }

    my $t = Page->new("deleted");
    $t->set_template_loop_data("deleted_loop", \@posts);
    $t->display_page("Deleted Posts");

}

sub undelete {
    my $tmp_hash = shift; # ref to hash
    my $post_id = $tmp_hash->{one};

    my $author_name  = User::get_logged_in_author_name(); 
    my $session_id   = User::get_logged_in_session_id(); 


    my $db = Config::get_value_for("database_name");

    my $rc;

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    $rc = $c->req('GET', $db . "/$post_id");

    if ( !$rc->{'json'} ) {
        Page->report_error("user", "Unable to delete post.", "Post ID \"$post_id\" was not found.");
    }

    my $perl_hash = $rc->{'json'};
    
    if ( !$perl_hash ) {
        Page->report_error("user", "Unable to delete post.", "Post ID \"$post_id\" was not found.");
    }

    $perl_hash->{'post_status'} = "public";

    $rc = $c->req('PUT', $db . "/$post_id", $perl_hash);

    my $url = Config::get_value_for("home_page") . "/deleted";
    my $q = new CGI;
    print $q->redirect( -url => $url);

}

sub tag_search {
    my $tmp_hash = shift;  

    my $keyword = $tmp_hash->{one};

    my $page_num = 1;

    if ( Utils::is_numeric($tmp_hash->{two}) ) {
        $page_num = $tmp_hash->{two};
    }

    my $rc;

    my $db = Config::get_value_for("database_name");

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

#    $rc = $c->req('GET', $db . "/_design/views/_view/tag_search?reduce=false&startkey=\"$keyword\"&endkey=\"$keyword\"");
    $rc = $c->req('GET', $db . "/_design/views/_view/tag_search?reduce=false&startkey=[\"$keyword\", {}]&endkey=[\"$keyword\"]&descending=true");

    my $stream = $rc->{'json'}->{'rows'};

    if ( !$stream ) {
        Page->success("Search results for $keyword", "No matches found.", "");
    }

    my $number_of_matches = @$stream;
    if ( $number_of_matches < 1 ) {
        Page->success("Search results for $keyword", "No matches found.", "");
    }

    my @posts;

    foreach my $hash_ref ( @$stream ) {
        $hash_ref->{'value'}->{'updated_at'} = Utils::format_date_time($hash_ref->{'value'}->{'updated_at'});
        push(@posts, $hash_ref->{'value'});
    }

    my $t = Page->new("stream");
    $t->set_template_loop_data("stream_loop", \@posts);
    $t->set_template_variable("search", 1);
    $t->set_template_variable("keyword", $keyword);
    $t->set_template_variable("search_type_text", "Tag search");
    $t->set_template_variable("search_type", "tag");
    $t->display_page("Tag search results for $keyword");
}

sub show_new_post_form {
    my $author_name  = User::get_logged_in_author_name(); 
    my $session_id   = User::get_logged_in_session_id(); 

#    my $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id";
#    my $api_url      = Config::get_value_for("api_url") . '/users/' . $user_name;
#    if ( $rc >= 200 and $rc < 300 ) {
#    } elsif ( $rc >= 400 and $rc < 500 ) {
#        if ( $rc == 401 ) {
#            my $t = Page->new("notloggedin");

        my $t = Page->new("newpostform");
        $t->display_page("Compose new post");
}

sub _write_html_to_memcached {
    my $id = shift;

    my $tmp_hash;
    $tmp_hash->{function} = $id;

    my $html = show_post($tmp_hash, "private");

    $html .= "\n<!-- memcached -->\n";

    my $port         =  Config::get_value_for("memcached_port");
    my $domain_name  =  Config::get_value_for("domain_name");
    my $key          =  $domain_name . "-" . $id;

    my $memd = Cache::Memcached::libmemcached->new( { 'servers' => [ "127.0.0.1:$port" ] } );
    my $rc = $memd->set($key, $html);
}

1;
