package Post;

use strict;
use warnings;

use CouchDB::Client;
use HTML::Entities;
use Encode;
use LWP::UserAgent;
use Text::MultiMarkdown;
use Text::Textile;
use JSON::PP;
use REST::Client;
use Cache::Memcached::libmemcached;
# use URI::Escape;

use App::PostTitle;
use App::Stream;


sub new_create_post {
    my $logged_in_author_name  = User::get_logged_in_author_name(); 
    my $session_id             = User::get_logged_in_session_id(); 
    my $author                 = Config::get_value_for("author_name");
    my $db                     = Config::get_value_for("database_name");
    if ( $logged_in_author_name ne $author ) {
        Page->report_error("user", "Unable to peform action.", "You are not logged in.");
    }

    my $q = new CGI;
    my $submit_type     = $q->param("sb"); # Preview or Post 
    my $post_location   = $q->param("post_location"); # notes_stream or ?
    my $original_markup = $q->param("markup");

    my $markup = Encode::decode_utf8($original_markup);
    $markup = HTML::Entities::encode($markup,'^\n^\r\x20-\x25\x27-\x7e');

    my $api_url = Config::get_value_for("api_url");

    my $json_input;

    my $hash = {
        'author'      => $logged_in_author_name,
        'session_id'  => $session_id,
        'submit_type' => $submit_type,
        'markup'      => $markup,
    };

    my $json_input = encode_json $hash;

    my $headers = {
        'Content-type' => 'application/json'
    };

    my $rest = REST::Client->new( {
        host => $api_url,
    } );

    $rest->POST( "/posts" , $json_input , $headers );

    my $rc = $rest->responseCode();

    my $json = decode_json $rest->responseContent();

    if ( $rc >= 200 and $rc < 300 ) {
        if ( $submit_type eq "Post" ) {
            if ( $post_location eq "notes_stream" ) {
                my $home_page = Config::get_value_for("home_page");
                print $q->redirect( -url => $home_page);
                exit;
            } else {
                my $home_page = Config::get_value_for("home_page");
                print $q->redirect( -url => $home_page . "/" . $json->{'post_id'} );
                exit;
            }
        } elsif ( $submit_type eq "Preview" ) {
            my $t = Page->new("newpostform");
            my $html = _remove_intro_text_command($json->{html});
            $t->set_template_variable("previewingpost", 1);
            $t->set_template_variable("html", $html);
            $t->set_template_variable("markup", $original_markup);
            $t->display_page("Previewing new post");
            exit;
        }
    } elsif ( $rc >= 400 and $rc < 500 ) {
         Page->report_error("user", $json->{description}, "$json->{user_message} $json->{system_message}");
    } else  {
        Page->report_error("user", "Unable to complete request. Invalid response code returned from API.", "$json->{user_message} $json->{system_message}");
    }
}


sub create_post {
    my $logged_in_author_name  = User::get_logged_in_author_name(); 
    my $session_id             = User::get_logged_in_session_id(); 
    my $author                 = Config::get_value_for("author_name");
    my $db                     = Config::get_value_for("database_name");
    if ( $logged_in_author_name ne $author ) {
        Page->report_error("user", "Unable to peform action.", "You are not logged in.");
    }


    my $q = new CGI;
    my $submit_type     = $q->param("sb"); # Preview or Post 
    my $post_location   = $q->param("post_location"); # notes_stream or ?
    my $original_markup = $q->param("markup");

    my $markup = Utils::trim_spaces($original_markup);
    if ( !defined($markup) || length($markup) < 1 ) {
        Page->report_error("user", "Invalid post.", "You most enter text.");
    } 
    $markup = Encode::decode_utf8($markup);
    $markup    = HTML::Entities::encode($markup,'^\n^\r\x20-\x25\x27-\x7e');


    my $o = PostTitle->new();
    $o->process_title($markup);
    if ( $o->is_error() ) {
        Page->report_error("user", "Error creating post.", $o->get_error_string());
    } 
    my $title           = $o->get_post_title();
    my $post_type       = $o->get_content_type(); # article or note
    my $slug            = $o->get_slug();
    my $html            = _markup_to_html($markup, $o->get_markup_type(), $slug);


    if ( $submit_type eq "Preview" ) {
        my $t = Page->new("newpostform");
        $html = _remove_intro_text_command($html);
        $t->set_template_variable("previewingpost", 1);
        $t->set_template_variable("html", $html);
        $t->set_template_variable("markup", $original_markup);
        $t->display_page("Previewing new post");
        exit;
    }


    my $tmp_post = $html;
    $tmp_post =~ s|<more />|\[more\]|;
    $tmp_post =~ s|<h1 class="headingtext">|\[h1\]|;
    $tmp_post =~ s|</h1>|\[/h1\]|;

    $tmp_post           = Utils::remove_html($tmp_post);
    my $post_stats      = _calc_reading_time_and_word_count($tmp_post); #returns a hash ref
    my $more_text_info  = _get_more_text_info($tmp_post, $slug, $title); #returns a hash ref
    my @tags            = Utils::create_tag_array($markup);
    my $created_at      = Utils::create_datetime_stamp();


    $html = _remove_intro_text_command($html);


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


sub update_post {
    my $logged_in_author_name  = User::get_logged_in_author_name(); 
    my $session_id             = User::get_logged_in_session_id(); 
    my $author                 = Config::get_value_for("author_name");
    my $db                     = Config::get_value_for("database_name");
    if ( $logged_in_author_name ne $author ) {
        Page->report_error("user", "Unable to peform action.", "You are not logged in.");
    }


    my $q = new CGI;
    my $submit_type     = $q->param("sb"); # Preview or Post 
    my $post_id         = $q->param("post_id"); # the slug. example: this-is-a-test
    my $rev             = $q->param("rev"); # the slug. example: this-is-a-test
    my $original_markup = $q->param("markup");

    my $markup = Utils::trim_spaces($original_markup);
    if ( !defined($markup) || length($markup) < 1 ) {
        Page->report_error("user", "Invalid post.", "You most enter text.");
    } 
    $markup = Encode::decode_utf8($markup);
    $markup    = HTML::Entities::encode($markup,'^\n^\r\x20-\x25\x27-\x7e');


    my $o = PostTitle->new();
    $o->process_title($markup);
    if ( $o->is_error() ) {
        Page->report_error("user", "Error creating post.", $o->get_error_string());
    } 
    my $title           = $o->get_post_title();
    my $post_type       = $o->get_content_type(); # article or note
    my $html            = _markup_to_html($markup, $o->get_markup_type(), $post_id);


    if ( $submit_type eq "Preview" ) {
        my $t = Page->new("editpostform");
        $html = _remove_intro_text_command($html);
        $t->set_template_variable("html", $html);
        $t->set_template_variable("slug",       $post_id);
        $t->set_template_variable("title",      $title);
        $t->set_template_variable("rev",        $rev);
        $t->set_template_variable("markup", $original_markup);
        $t->display_page("Editing " . $title);
        exit;
    }


    my $tmp_post = $html;
    $tmp_post =~ s|<more />|\[more\]|;
    $tmp_post =~ s|<h1 class="headingtext">|\[h1\]|;
    $tmp_post =~ s|</h1>|\[/h1\]|;

    $tmp_post           = Utils::remove_html($tmp_post);
    my $post_stats      = _calc_reading_time_and_word_count($tmp_post); #returns a hash ref
    my $more_text_info  = _get_more_text_info($tmp_post, $post_id, $title); #returns a hash ref
    my @tags            = Utils::create_tag_array($markup);
    my $updated_at      = Utils::create_datetime_stamp();


    my $previous_post_hash = _get_entire_post($post_id); #returns a hash ref

    if ( $previous_post_hash->{'_rev'} ne $rev ) {
        Page->report_error("user", "Unable to update post.", "Invalid rev information provided."); 
    }


    $html = _remove_intro_text_command($html);


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
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");
    my $rc = $c->req('PUT', $db . "/$post_id", $previous_post_hash);
    if ( $rc->{status} >= 300 ) {
        Page->report_error("user", "Unable to update post.", $rc->{msg});
    }


    if ( Config::get_value_for("write_html_to_memcached") ) {
        _write_html_to_memcached($post_id);
    }


    my $home_page = Config::get_value_for("home_page");
    print $q->redirect( -url => $home_page . "/" . $post_id);
    exit;

}


sub show_post {
    my $tmp_hash      = shift; 
    my $creation_type = shift;
    my $api_call      = shift;

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

    return $post if $api_call;

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

sub show_splitscreen_form {
    my $author_name  = User::get_logged_in_author_name(); 
    my $session_id   = User::get_logged_in_session_id(); 

#    my $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id";
#    my $api_url      = Config::get_value_for("api_url") . '/users/' . $user_name;
#    if ( $rc >= 200 and $rc < 300 ) {
#    } elsif ( $rc >= 400 and $rc < 500 ) {
#        if ( $rc == 401 ) {
#            my $t = Page->new("notloggedin");
#            $t->display_page("Login");

    my $t = Page->new("splitscreenform");
    $t->set_template_variable("action", "addarticle");
    $t->set_template_variable("api_url", Config::get_value_for("api_url"));
    $t->set_template_variable("post_id", 0);
    $t->set_template_variable("post_rev", "undef");
    $t->display_page_min("Creating Post - Split Screen");
}


sub show_post_to_edit {
    my $tmp_hash = shift; 

    my $author_name  = User::get_logged_in_author_name(); 
    my $session_id   = User::get_logged_in_session_id(); 

    my $post_id = $tmp_hash->{one};

    my $ua = LWP::UserAgent->new;

    my $db = Config::get_value_for("database_name");
    my $url = "http://127.0.0.1:5984/" . $db . "/_design/views/_view/post_markup?key=\"$post_id\"";

    my $response = $ua->get($url);

    if ( !$response->is_success ) {
        Page->report_error("user", "Unable to display post.", "Post ID \"$post_id\" was not found.");
    }

    my $rc = decode_json $response->content;

    my $post = $rc->{'rows'}->[0]->{'value'};

    if ( !$post ) {
        Page->report_error("user", "Unable to display post.", "Post ID \"$post_id\" was not found.");
    }

    my $slug = $rc->{'rows'}->[0]->{'id'};

    my $t = Page->new("editpostform");
    $t->set_template_variable("slug",       $slug);
    $t->set_template_variable("title",      $post->{'title'});
    $t->set_template_variable("rev",        $post->{'_rev'});
#$t->set_template_variable("markup_text", decode_entities($json->{markup_text}, '<>&'));
    $t->set_template_variable("markup",     $post->{'markup'});
    $t->display_page($post->{'title'});
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


    my $tmp_hash;
    $tmp_hash->{one}=1;
    $html = Stream::show_stream($tmp_hash, "private");
    $html .= "\n<!-- memcached -->\n";
    $key =  $domain_name . "-homepage";
    $rc = $memd->set($key, $html);
}


sub _markup_to_html {
    my $markup      = shift;
    my $markup_type = shift;
    my $slug        = shift;

    if ( Utils::get_power_command_on_off_setting_for("markdown", $markup, 0) ) {
        $markup_type = "markdown";
    }

    my $html   = Utils::remove_power_commands($markup);
    $html      = Utils::url_to_link($html) if Utils::get_power_command_on_off_setting_for("url_to_link", $markup, 1);

    $html = Utils::custom_commands($html); 

    $html = Utils::hashtag_to_link($html)  if Utils::get_power_command_on_off_setting_for("hashtag_to_link", $markup, 1);

    if ( $markup_type eq "textile" ) {
        my $textile = new Text::Textile;
        $html = $textile->process($html);
    } else {
        my $md   = Text::MultiMarkdown->new;
        $html = $md->markdown($html, {heading_ids => 0} );
    }

    # why do this?
    $html =~ s/&#39;/'/sg;

    $html = _create_heading_list($html, $slug);

    return $html;
}

sub _calc_reading_time_and_word_count {
    my $post = shift; # html already removed
    my $hash_ref;
    my @tmp_arr                 = split(/\s+/s, $post);
    $hash_ref->{'word_count'}   = scalar (@tmp_arr);
    $hash_ref->{'reading_time'} = 0; #minutes
    $hash_ref->{'reading_time'} = int($hash_ref->{'word_count'} / 180) if $hash_ref->{'word_count'} >= 180;
    return $hash_ref;
}

sub _get_more_text_info {
    my $tmp_post   = shift;
    my $slug       = shift;
    my $title      = shift;

    my $text_intro;

    my $more_text_exists = 0; #false

    if ( $tmp_post =~ m|^(.*?)\[more\](.*?)$|is ) { 
        $text_intro = $1;
        my $tmp_extended = Utils::trim_spaces($2);
        if ( length($tmp_extended) > 0 ) {
            $more_text_exists = 1;
        }
        if ( length($text_intro) > 300 ) {
            $text_intro = substr $text_intro, 0, 300;
            $text_intro .= " ...";
        }
    } elsif ( $tmp_post =~ m|^intro[\s]*=[\s]*(.*?)$|mi ) {
        $text_intro = $1;
        $more_text_exists = 1;
        if ( length($text_intro) > 300 ) {
            $text_intro = substr $text_intro, 0, 300;
            $text_intro .= " ...";
        }
        $text_intro = "<span class=\"streamtitle\"><a href=\"/$slug\">$title</a></span> - " . $text_intro;
    } elsif ( length($tmp_post) > 300 ) {
        $text_intro = substr $tmp_post, 0, 300;
        $text_intro .= " ...";
        $more_text_exists = 1;
    } else {
        $text_intro = $tmp_post;
    }

    $text_intro =~ s|\[h1\]|<span class="streamtitle"><a href="/$slug">|;
    $text_intro =~ s|\[/h1\]|</a></span> - |;
    $text_intro = Utils::remove_newline($text_intro);

    if ( !$more_text_exists ) {
        $text_intro = Utils::url_to_link($text_intro);
        $text_intro = Utils::hashtag_to_link($text_intro);
    }

    return { 'more_text_exists' => $more_text_exists, 'text_intro' => $text_intro };
}


sub _get_entire_post {
    my $post_id = shift;

    my $db = Config::get_value_for("database_name");

    my $rc;

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    $rc = $c->req('GET', $db . "/$post_id");

    if ( !$rc->{'json'} ) {
        Page->report_error("user", "Unable to get post.", "Post ID \"$post_id\" was not found.");
    }

    my $perl_hash = $rc->{'json'};
    
    if ( !$perl_hash ) {
        Page->report_error("user", "Unable to get post.", "Post ID \"$post_id\" was not found.");
    }

    return $perl_hash;
}



# comments from the create_post sub. may need to address these issues later.
# since it's a single-user app, then no need to encode????
#    $markup    = HTML::Entities::encode($markup,'^\n^\r\x20-\x25\x27-\x7e');
#    my $formatted_created_at  = Utils::format_date_time($created_date);
#    my $formatted_updated_at  = $formatted_created_at;

# these comments were removed from the cdb hash in the create post sub.
#    'slug'              =>  $slug,
#    'post_id'           =>  Utils::create_random_string(),
#    'formatted_created_at'  =>  $formatted_created_at,
#    'formatted_updated_at'  =>  $formatted_updated_at,

sub _remove_intro_text_command {
    my $html = shift;

    if ( $html =~ m|^<p>intro[\s]*=[\s]*(.*?)</p>$|mi ) {
        $html =~ s|^<p>intro[\s]*=[\s]*$1</p>||mig;
    }

    return $html;
}

sub _create_heading_list {
    my $str  = shift;
    my $slug = shift;

    my @headers = ();
    my $header_list = "";

    if ( @headers = $str =~ m{\s+<h([1-6]).*?>(.*?)</h[1-6]>}igs ) {
        my $len = @headers;
        for (my $i=0; $i<$len; $i+=2) { 
            my $heading_text = Utils::remove_html($headers[$i+1]); 
            my $heading_url  = Utils::clean_title($heading_text);
            my $oldstr = "<h$headers[$i]>$headers[$i+1]</h$headers[$i]>";
#            my $newstr = "<a name=\"$heading_url\"></a>\n<h$headers[$i]>$headers[$i+1]</h$headers[$i]>";
            my $newstr = "<a name=\"$heading_url\"></a>\n<h$headers[$i] class=\"headingtext\"><a href=\"#$heading_url\">$headers[$i+1]</a></h$headers[$i]>";
            $str =~ s/\Q$oldstr/$newstr/i;
#            $header_list .= "<!-- header:$headers[$i]:$heading_text -->\n";   
        } 
    }

#    $str .= "\n$header_list";  

    if ( $str =~ m{^<h1.*?>(.*?)</h1>}igs ) {
        my $orig_heading_text = $1;
        my $heading_text = Utils::remove_html($orig_heading_text); 
        my $heading_url  = Utils::clean_title($heading_text);
        my $oldstr = "<h1>$orig_heading_text</h1>";
        my $newstr = "<a name=\"$heading_url\"></a>\n<h1 class=\"headingtext\"><a href=\"/$slug\">$orig_heading_text</a></h1>";
        $str =~ s/\Q$oldstr/$newstr/i;
    }

    return $str; 
}

sub splitscreen_edit {
    my $tmp_hash = shift;  

    my $author_name  = User::get_logged_in_author_name(); 
    my $session_id   = User::get_logged_in_session_id(); 

    my $post_id = $tmp_hash->{one};

    my $ua = LWP::UserAgent->new;

    my $db = Config::get_value_for("database_name");
    my $url = "http://127.0.0.1:5984/" . $db . "/_design/views/_view/post_markup?key=\"$post_id\"";

    my $response = $ua->get($url);

    if ( !$response->is_success ) {
        Page->report_error("user", "Unable to display post.", "Post ID \"$post_id\" was not found.");
    }

    my $rc = decode_json $response->content;

    my $post = $rc->{'rows'}->[0]->{'value'};

    if ( !$post ) {
        Page->report_error("user", "Unable to display post.", "Post ID \"$post_id\" was not found.");
    }

    my $slug = $rc->{'rows'}->[0]->{'id'};

    my $t = Page->new("splitscreenform");
    $t->set_template_variable("action",   "updateblog");
    $t->set_template_variable("api_url",  Config::get_value_for("api_url"));
#   $t->set_template_variable("markup",   decode_entities($post->{markup_text}, '<>&'));
    $t->set_template_variable("markup",   $post->{'markup'});
    $t->set_template_variable("post_id",  $slug);
    $t->set_template_variable("post_rev", $post->{_rev});

    $t->display_page_min("Editing - Split Screen " . $post->{title});
}

1;
