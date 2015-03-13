package PostsApi;

use strict;
use warnings;

use JSON::PP;
use CGI qw(:standard);
use LWP::UserAgent;
use HTML::Entities;
use Encode;
use URI::Escape::JavaScript qw(escape unescape);

use App::Error;
use App::PostTitle;
use App::Post;


# GET page 3 of a stream of posts 
#   http://scaup.soupmode.com/api/v1/posts/?page=3
# GET a single post - default is text=html
#   http://scaup.soupmode.com/api/v1/posts/spencer-trappist-ale-clone-august-2014
# GET the markup for the same post
#   http://scaup.soupmode.com/api/v1/posts/spencer-trappist-ale-clone-august-2014/?text=markup



sub posts {
    my $tmp_hash = shift;

    my $page_num = 0;
    my $q = new CGI;
    $page_num = $q->param("page") if $q->param("page");

    my $request_method = $q->request_method();

    if ( $request_method eq "GET" and $tmp_hash->{one} and !$page_num ) {
        my $return_type = "html"; # markup = return only the markup text. html = return only html. full = return all database data for the post.
        $return_type    = $q->param("text") if $q->param("text");
        _get_post($tmp_hash->{one}, $return_type);

    } elsif ( $request_method eq "GET" ) {
        _get_post_stream($page_num);

    } elsif ( $request_method eq "POST" ) {
        _create_post();

    } elsif ( $request_method eq "PUT" ) {
        _update_post();

    }
}


sub _get_post {
    my $post_id     = shift; 
    my $return_type = shift;


    my $view_name;

    if ( $return_type eq "markup" ) {
        $view_name = "post_markup";
    } elsif ( $return_type eq "full" ) {
        $view_name = "post_full";
    } else {
        $view_name = "post";
    }
    
    my $post_hash = _get_post_data($post_id, $view_name);

    if ( !$post_hash ) {
        Error::report_error("404", "Post unavailable.", "Post ID not found: $post_id");
    }

    my $json_hash;
   
    $json_hash->{status}      = 200;
    $json_hash->{description} = "OK";
    $json_hash->{post}        = $post_hash;

    my $json_str = encode_json $json_hash;
    print header('application/json', '200 Accepted');
    print $json_str;
    exit;

}

sub _get_post_data {
    my $post_id   = shift;
    my $view_name = shift;

    my $ua = LWP::UserAgent->new;

    my $db = Config::get_value_for("database_name");

    my $url = "http://127.0.0.1:5984/" . $db . "/_design/views/_view/" . $view_name . "?key=\"$post_id\"";

    my $response = $ua->get($url);

    if ( !$response->is_success ) {
        Error::report_error("404", "Unable to display post.", "Post ID \"$post_id\" was not found.");
    }

    my $rc = decode_json $response->content;

    my $post = $rc->{'rows'}->[0]->{'value'};

    return $post;
}

sub _get_post_stream {
    my $page_num    = shift;

    $page_num++ if $page_num == 0;

    my $rc;

    my $db = Config::get_value_for("database_name");

    my $c = CouchDB::Client->new();
    $c->testConnection or Error::report_error("500", "Database error.", "The server cannot be reached.");

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

    my $ctr=0;
    foreach my $hash_ref ( @$stream ) {
        $hash_ref->{'value'}->{'formatted_updated_at'} = Utils::format_date_time($hash_ref->{'value'}->{'updated_at'});
        push(@posts, $hash_ref->{'value'});
        last if ++$ctr == $max_entries;
    }

    my $hash_ref;
    $hash_ref->{status}      = 200;
    $hash_ref->{description} = "OK";
    $hash_ref->{posts}       = \@posts;
    my $json_str = encode_json $hash_ref;

    print header('application/json', '200 Accepted');
    print $json_str;
    exit;
}

sub _create_post {

    my $q = new CGI;

    my $json_text = $q->param('POSTDATA');

    my $hash_ref = decode_json $json_text;


    my $logged_in_author_name  = $hash_ref->{'author'};
    my $session_id             = $hash_ref->{'session_id'};

    my $author                 = Config::get_value_for("author_name");
    my $db                     = Config::get_value_for("database_name");
    if ( $logged_in_author_name ne $author ) {
        Error::report_error("400", "Unable to peform action.", "You are not logged in.");
    }

    my $submit_type     = $hash_ref->{'submit_type'}; # Preview or Post 
    if ( $submit_type ne "Preview" and $submit_type ne "Post" ) {
        Error::report_error("400", "Unable to process post.", "Invalid submit type given.");
    } 

    my $original_markup = $hash_ref->{'markup'};

    my $markup = Utils::trim_spaces($original_markup);
    if ( !defined($markup) || length($markup) < 1 ) {
        Error::report_error("400", "Invalid post.", "You most enter text.");
    } 
    my $formtype = $hash_ref->{'form_type'};
    if ( $formtype eq "ajax" ) {
        $markup = URI::Escape::JavaScript::unescape($markup);
    $markup = HTML::Entities::encode($markup, '^\n\x20-\x25\x27-\x7e');
    } else {
#        $markup = Encode::decode_utf8($markup);
    }
#    $markup = HTML::Entities::encode($markup, '^\n\x20-\x25\x27-\x7e');

    my $o = PostTitle->new();
    $o->process_title($markup);
    if ( $o->is_error() ) {
        Error::report_error("400", "Error creating post.", $o->get_error_string());
    } 
    my $title           = $o->get_post_title();
    my $post_type       = $o->get_content_type(); # article or note
    my $slug            = $o->get_slug();
    my $html            = Post::_markup_to_html($markup, $o->get_markup_type(), $slug);


    my $hash_ref;

    if ( $submit_type eq "Preview" ) {
        $html = Post::_remove_intro_text_command($html);
        $hash_ref->{html} = $html;
        $hash_ref->{status}      = 200;
        $hash_ref->{description} = "OK";
        my $json_str = encode_json $hash_ref;
        print header('application/json', '200 Accepted');
        print $json_str;
        exit;
    }

    my $tmp_post = $html;
    $tmp_post =~ s|<more />|\[more\]|;
    $tmp_post =~ s|<h1 class="headingtext">|\[h1\]|;
    $tmp_post =~ s|</h1>|\[/h1\]|;

    $tmp_post           = Utils::remove_html($tmp_post);
    my $post_stats      = Post::_calc_reading_time_and_word_count($tmp_post); #returns a hash ref
    my $more_text_info  = Post::_get_more_text_info($tmp_post, $slug, $title); #returns a hash ref
    my @tags            = Utils::create_tag_array($markup);
    my $created_at      = Utils::create_datetime_stamp();


    $html = Post::_remove_intro_text_command($html);


    my $cdb_hash = {
    '_id'                   =>  $slug,
    'type'                  =>  'post',
    'title'                 =>  $title,
    'markup'                =>  $markup,
    'html'                  =>  $html,
    'text_intro'            =>  $more_text_info->{'text_intro'},
    'more_text_exists'      =>  $more_text_info->{'more_text_exists'},
    'post_type'             =>  $post_type,
    'tags'                  =>  \@tags,
    'author'                =>  $author,
    'created_at'            =>  $created_at,
    'updated_at'            =>  $created_at,
    'reading_time'          =>  $post_stats->{'reading_time'},
    'word_count'            =>  $post_stats->{'word_count'},
    'post_status'           =>  'public'
    };


    my $c = CouchDB::Client->new();
    $c->testConnection or Error::report_error("400", "Database error.", "The server cannot be reached.");
    my $rc = $c->req('POST', $db, $cdb_hash);
    if ( $rc->{status} >= 300 ) {
        Error::report_error("400", "Unable to create post.", $rc->{msg});
    }


    if ( Config::get_value_for("write_html_to_memcached") ) {
        Post::_write_html_to_memcached($rc->{'json'}->{'id'});
    }


    $hash_ref->{post_id}     = $slug;
    $hash_ref->{rev}         = $rc->{json}->{rev};
    $hash_ref->{html}        = $html;
    $hash_ref->{status}      = 200;
    $hash_ref->{description} = "OK";
    my $json_str = encode_json $hash_ref;
    print header('application/json', '200 Accepted');
    print $json_str;
    exit;

}

sub _update_post {

    my $q = new CGI;

    my $json_text = $q->param('PUTDATA');

    my $hash_ref = decode_json $json_text;


    my $logged_in_author_name  = $hash_ref->{'author'};
    my $session_id             = $hash_ref->{'session_id'};

    my $author                 = Config::get_value_for("author_name");
    my $db                     = Config::get_value_for("database_name");
    if ( $logged_in_author_name ne $author ) {
        Error::report_error("400", "Unable to peform action.", "You are not logged in.");
    }

    my $submit_type     = $hash_ref->{'submit_type'}; # Update or Post 
    if ( $submit_type ne "Update" and $submit_type ne "Post" ) {
        Error::report_error("400", "Unable to process post.", "Invalid submit type given.");
    } 

    my $original_markup = $hash_ref->{'markup'};
    my $rev             = $hash_ref->{'rev'};
    my $post_id         = $hash_ref->{'post_id'};

    my $markup = Utils::trim_spaces($original_markup);
    if ( !defined($markup) || length($markup) < 1 ) {
        Error::report_error("400", "Invalid post.", "You most enter text.");
    } 
    my $formtype = $hash_ref->{'form_type'};
    if ( $formtype eq "ajax" ) {
        $markup = URI::Escape::JavaScript::unescape($markup);
    } else {
        $markup = Encode::decode_utf8($markup);
    }
    $markup = HTML::Entities::encode($markup, '^\n\x20-\x25\x27-\x7e');

    my $o = PostTitle->new();
    $o->process_title($markup);
    if ( $o->is_error() ) {
        Error::report_error("400", "Error creating post.", $o->get_error_string());
    } 
    my $title           = $o->get_post_title();
    my $post_type       = $o->get_content_type(); # article or note
    my $slug            = $o->get_slug();
    my $html            = Post::_markup_to_html($markup, $o->get_markup_type(), $slug);


    my $hash_ref;

    if ( $submit_type eq "Preview" ) {
        $html = Post::_remove_intro_text_command($html);
        $hash_ref->{html} = $html;
        $hash_ref->{status}      = 200;
        $hash_ref->{description} = "OK";
        my $json_str = encode_json $hash_ref;
        print header('application/json', '200 Accepted');
        print $json_str;
        exit;
    }

    my $tmp_post = $html;
    $tmp_post =~ s|<more />|\[more\]|;
    $tmp_post =~ s|<h1 class="headingtext">|\[h1\]|;
    $tmp_post =~ s|</h1>|\[/h1\]|;

    $tmp_post           = Utils::remove_html($tmp_post);
    my $post_stats      = Post::_calc_reading_time_and_word_count($tmp_post); #returns a hash ref
    my $more_text_info  = Post::_get_more_text_info($tmp_post, $slug, $title); #returns a hash ref
    my @tags            = Utils::create_tag_array($markup);
    my $updated_at      = Utils::create_datetime_stamp();


    my $previous_post_hash = _get_entire_post($post_id); #returns a hash ref

    if ( $previous_post_hash->{'_rev'} ne $rev ) {
        Error::report_error("400", "Unable to update post.", "Invalid rev information provided."); 
    }


    $html = Post::_remove_intro_text_command($html);


    $previous_post_hash->{'title'}             = $title;
    $previous_post_hash->{'markup'}            = $markup;
    $previous_post_hash->{'html'}              = $html;
    $previous_post_hash->{'text_intro'}        = $more_text_info->{'text_intro'};
    $previous_post_hash->{'more_text_exists'}  = $more_text_info->{'more_text_exists'};
    $previous_post_hash->{'post_type'}         = $post_type;
    $previous_post_hash->{'tags'}              = \@tags;
    $previous_post_hash->{'updated_at'}        = $updated_at;
    $previous_post_hash->{'reading_time'}      = $post_stats->{'reading_time'};
    $previous_post_hash->{'word_count'}        = $post_stats->{'word_count'};


    my $c = CouchDB::Client->new();
    $c->testConnection or Error::report_error("500", "Database error.", "The server cannot be reached.");
    my $rc = $c->req('PUT', $db . "/$post_id", $previous_post_hash);
    if ( $rc->{status} >= 300 ) {
        Error::report_error("400", "Unable to update post.", $rc->{msg});
    }


    if ( Config::get_value_for("write_html_to_memcached") ) {
        Post::_write_html_to_memcached($post_id);
    }


    $hash_ref->{rev}         = $rc->{json}->{rev};
    $hash_ref->{html}        = $html;
    $hash_ref->{status}      = 200;
    $hash_ref->{description} = "OK";
    my $json_str = encode_json $hash_ref;
    print header('application/json', '200 Accepted');
    print $json_str;
    exit;

}

sub _get_entire_post {
    my $post_id = shift;

    my $db = Config::get_value_for("database_name");

    my $rc;

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    $rc = $c->req('GET', $db . "/$post_id");

    if ( !$rc->{'json'} ) {
        Error::report_error("400", "Unable to get post.", "Post ID \"$post_id\" was not found.");
    }

    my $perl_hash = $rc->{'json'};
    
    if ( !$perl_hash ) {
        Error::report_error("400", "Unable to get post.", "Post ID \"$post_id\" was not found.");
    }

    return $perl_hash;
}


1;
