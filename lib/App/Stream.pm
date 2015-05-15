package Stream;

use strict;
use warnings;

use CouchDB::Client;
use LWP::UserAgent;
use JSON::PP;
use URI::Escape;

sub show_stream {
    my $tmp_hash    = shift;
    my $creation_type = shift; # if equals "private", then called from Post.pm and done so to cache home page.

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

    my $ctr=0;
    foreach my $hash_ref ( @$stream ) {
        my $tags = $hash_ref->{'value'}->{'tags'};
        if ( $tags->[0] ) {
            my $tag_list = "";
            foreach my $tag_ref ( @$tags ) {
                $tag_list .= "<a href=\"/tag/$tag_ref\">#" . $tag_ref . "</a> ";
            }
            $hash_ref->{'value'}->{'tag_list'} = $tag_list;
        }
        delete($hash_ref->{'value'}->{'tags'});
        $hash_ref->{'value'}->{'updated_at'} = Utils::format_date_time($hash_ref->{'value'}->{'updated_at'});
        push(@posts, $hash_ref->{'value'});
        last if ++$ctr == $max_entries;
    }

    my $t = Page->new("stream");

    if ( $creation_type eq "private" ) {
        $t->set_template_variable("loggedin", 0);
    } else {
        $t->set_template_variable("loggedin", User::get_logged_in_flag());
    }

    my $cache_it = 0;
    if ( !User::get_logged_in_flag() and Config::get_value_for("write_html_to_memcached") ) {
        $cache_it = 1;
    }

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

    if ( $creation_type ne "private" ) {
        $t->display_page("Stream of Posts");
    } else {
        return $t->create_html("Stream of Posts");
    }
}


sub show_search_form {
    my $t = Page->new("searchform");
    $t->display_page("Search form");
}


sub old_search {
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
        my $tags = $hash_ref->{'value'}->{'tags'};
        if ( $tags->[0] ) {
            my $tag_list = "";
            foreach my $tag_ref ( @$tags ) {
                $tag_list .= "<a href=\"/tag/$tag_ref\">#" . $tag_ref . "</a> ";
            }
            $hash_ref->{'value'}->{'tag_list'} = $tag_list;
        }
        delete($hash_ref->{'value'}->{'tags'});
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

# jrs - 24apr2015 - uses elasticsearch
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
            Page->report_error("user", "Missing data.", "Enter keyword(s) to search on.");
        }
        
        $keyword = Utils::trim_spaces($keyword);
        if ( length($keyword) < 1 ) {
            Page->report_error("user", "Missing data.", "Enter keyword(s) to search on.");
        }
        
        # $keyword =~ s/ /\+/g;
        # $keyword = uri_escape($hash{search_string});
    }

    my $db = Config::get_value_for("database_name");

    my $max_entries = Config::get_value_for("max_entries_on_page");

    my $skip_count = ($max_entries * $page_num) - $max_entries;

    my $url = 'http://127.0.0.1:9200/' . $db . '/' . $db . '/_search?size=' . $max_entries . '&q=%2Btype%3Apost+%2Bpost_status%3Apublic+%2Bmarkup%3A' . uri_escape($keyword) . '&from=' . $skip_count;

    my $ua = LWP::UserAgent->new;

    my $response = $ua->get($url);
    if ( !$response->is_success ) {
        Page->report_error("user", "Unable to complete request.", "$url");
    }

    my $rc = decode_json $response->content;

    my $total_hits = $rc->{'hits'}->{'total'};

    my $stream = $rc->{'hits'}->{'hits'};

    if ( !$stream ) {
        Page->success("Search results for $keyword", "No matches found.", "");
    }

    my $len = @$stream;
    if ( $len < 1 ) {
        Page->success("Search results for $keyword", "No matches found.", "");
    }

    my $next_link_bool = 0;
    if ( ($len == $max_entries) && ($total_hits > $max_entries) ) {
        $next_link_bool = 1;
    }

    my @posts;

    foreach my $hash_ref ( @$stream ) {
        my $tags = $hash_ref->{'_source'}->{'tags'};
        if ( $tags->[0] ) {
            my $tag_list = "";
            foreach my $tag_ref ( @$tags ) {
                $tag_list .= "<a href=\"/tag/$tag_ref\">#" . $tag_ref . "</a> ";
            }
            $hash_ref->{'_source'}->{'tag_list'} = $tag_list;
        }
        delete($hash_ref->{'_source'}->{'tags'});
        $hash_ref->{'_source'}->{'updated_at'} = Utils::format_date_time($hash_ref->{'_source'}->{'updated_at'});
        $hash_ref->{'_source'}->{'slug'} = $hash_ref->{'_source'}->{'_id'};
        delete($hash_ref->{'_source'}->{'_id'});
        delete($hash_ref->{'_source'}->{'created_at'});
        delete($hash_ref->{'_source'}->{'html'});
        delete($hash_ref->{'_source'}->{'markup'});
        delete($hash_ref->{'_source'}->{'_rev'});
        delete($hash_ref->{'_source'}->{'post_status'});
        delete($hash_ref->{'_source'}->{'type'});
        delete($hash_ref->{'_source'}->{'post_type'});
        delete($hash_ref->{'_source'}->{'title'});
        delete($hash_ref->{'_source'}->{'word_count'});
        push(@posts, $hash_ref->{'_source'});
    }

    my $t = Page->new("stream");
    $t->set_template_loop_data("stream_loop", \@posts);
    $t->set_template_variable("search", 1);
    $t->set_template_variable("keyword", $keyword);
    $t->set_template_variable("search_type_text", "Search");
    $t->set_template_variable("search_type", "search");

    if ( $page_num == 1 ) {
        $t->set_template_variable("not_page_one", 0);
    } else {
        $t->set_template_variable("not_page_one", 1);
    }

    if ( $total_hits > $max_entries && $next_link_bool ) {
        $t->set_template_variable("not_last_page", 1);
    } else {
        $t->set_template_variable("not_last_page", 0);
    }
    my $previous_page_num = $page_num - 1;
    my $next_page_num = $page_num + 1;
    my $next_page_url = "/search/$keyword/$next_page_num";
    my $previous_page_url = "/search/$keyword/$previous_page_num";
    $t->set_template_variable("next_page_url", $next_page_url);
    $t->set_template_variable("previous_page_url", $previous_page_url);

    $t->display_page("Search results for $keyword");
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

    my $max_entries = Config::get_value_for("max_entries_on_page");

    my $skip_count = ($max_entries * $page_num) - $max_entries;

#    $rc = $c->req('GET', $db . "/_design/views/_view/tag_search?reduce=false&startkey=\"$keyword\"&endkey=\"$keyword\"");

#    $rc = $c->req('GET', $db . "/_design/views/_view/tag_search?reduce=false&startkey=[\"$keyword\", {}]&endkey=[\"$keyword\"]&descending=true&skip=" . $skip_count . "&limit=" . ($max_entries + 1) );

    my $couchdb_uri = $db . "/_design/views/_view/tag_search?descending=true&limit=" . ($max_entries + 1) . "&skip=" . $skip_count;
    $couchdb_uri = $couchdb_uri . "&startkey=[\"$keyword\", {}]&endkey=[\"$keyword\"]";

    $rc = $c->req('GET', $couchdb_uri);

    my $stream = $rc->{'json'}->{'rows'};

    my $next_link_bool = 0;
    my $len = @$stream;
    if ( $len > $max_entries ) {
        $next_link_bool = 1;
    }

    if ( !$stream ) {
        Page->success("Search results for $keyword", "No matches found.", "");
    }

    my $number_of_matches = @$stream;
    if ( $number_of_matches < 1 ) {
        Page->success("Search results for $keyword", "No matches found.", "");
    }

    my @posts;

    my $ctr=0;
    foreach my $hash_ref ( @$stream ) {
        my $tags = $hash_ref->{'value'}->{'tags'};
        if ( $tags->[0] ) {
            my $tag_list = "";
            foreach my $tag_ref ( @$tags ) {
                $tag_list .= "<a href=\"/tag/$tag_ref\">#" . $tag_ref . "</a> ";
            }
            $hash_ref->{'value'}->{'tag_list'} = $tag_list;
        }
        delete($hash_ref->{'value'}->{'tags'});
        $hash_ref->{'value'}->{'updated_at'} = Utils::format_date_time($hash_ref->{'value'}->{'updated_at'});
        push(@posts, $hash_ref->{'value'});
        last if ++$ctr == $max_entries;
    }

    my $t = Page->new("stream");
    $t->set_template_loop_data("stream_loop", \@posts);
    $t->set_template_variable("search", 1);
    $t->set_template_variable("keyword", $keyword);
    $t->set_template_variable("search_type_text", "Tag search");
    $t->set_template_variable("search_type", "tag");
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
    my $next_page_url = "/tag/$keyword/$next_page_num";
    my $previous_page_url = "/tag/$keyword/$previous_page_num";
    $t->set_template_variable("next_page_url", $next_page_url);
    $t->set_template_variable("previous_page_url", $previous_page_url);
    $t->display_page("Tag search results for $keyword");
}


1;
