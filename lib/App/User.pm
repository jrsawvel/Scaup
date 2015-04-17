package User;
use strict;
use warnings;

use WWW::Mailgun;

my %scaup_h           = _get_user_cookie_settings();

sub _get_user_cookie_settings {
    my $q = new CGI;
    my %h;
    my $cookie_prefix = Config::get_value_for("cookie_prefix");
    if ( defined($q->cookie($cookie_prefix. "session_id")) ) {
        $h{session_id}        = $q->cookie($cookie_prefix . "session_id");
        $h{author_name}       = $q->cookie($cookie_prefix . "author_name");
        $h{loggedin}          = 1;
    } else {
        $h{loggedin}          = 0;
        $h{session_id}        = -1;
    }
    return %h;
}

sub get_logged_in_flag {
    return $scaup_h{loggedin};
}

sub get_logged_in_author_name {
    return $scaup_h{author_name};
}

sub get_logged_in_session_id {
    return $scaup_h{session_id};
}

sub show_login_form {
    my $t = Page->new("loginform");
    $t->display_page("Login Form");
}

sub mail_login_link {

    my $q = new CGI;
    my $user_submitted_email = Utils::trim_spaces($q->param("email"));

    if ( !$user_submitted_email ) {
        Page->report_error("user", "Invalid input.", "No data was submitted.");
    }

    my $author_name = Config::get_value_for("author_name");
    my $author_email = _get_email_for($author_name);

    if ( $user_submitted_email ne $author_email ) {
        Page->report_error("user", "Invalid input.", "Data was not found.");
    } else {
        my $rev = _create_session_id(); 
        _send_login_link($author_email, $rev);
    }

    Page->success("Creating New Login Link", "A new login link has been created and sent.", "");

}

sub _send_login_link {
    my $email_rcpt      = shift;
    my $rev             = shift;

    my $date_time = Utils::create_datetime_stamp();

    my $mailgun_api_key = Config::get_value_for("mailgun_api_key");
    my $mailgun_domain  = Config::get_value_for("mailgun_domain");
    my $mailgun_from    = Config::get_value_for("mailgun_from");

    my $home_page = Config::get_value_for("home_page");
    my $link      = "$home_page/nopwdlogin/$rev";

    my $site_name = Config::get_value_for("site_name");
    my $subject = "$site_name Login Link - $date_time UTC";

    my $message = "Clink or copy link to log into the site.\n\n$link\n";
             

    my $mg = WWW::Mailgun->new({ 
        key    => "$mailgun_api_key",
        domain => "$mailgun_domain",
        from   => "$mailgun_from"
    });

    $mg->send({
          to      => "<$email_rcpt>",
          subject => "$subject",
          text    => "$message"
    });

}

sub _get_email_for {

    my $author_name = shift;

    my $rc;

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    my $db = Config::get_value_for("database_name");
    $rc = $c->req('GET', $db . '/_design/views/_view/author?key="' . $author_name . '"');

    if ( !$rc->{'json'}->{'rows'}->[0] ) {
        return " ";
    } else {
        my $author_info = $rc->{'json'}->{'rows'}->[0]->{'value'};
        return $author_info->{'email'};
    }
}

sub _get_session_id_for {
    my $author_name = shift;

    my $rc;

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    my $db = Config::get_value_for("database_name");
    $rc = $c->req('GET', $db . '/_design/views/_view/author?key="' . $author_name . '"');

    if ( !$rc->{'json'}->{'rows'}->[0] ) {
        return " ";
    } else {
        my $author_info = $rc->{'json'}->{'rows'}->[0]->{'value'};
        return $author_info->{'current_session_id'};
    }
}

sub _create_session_id {

#    my $created_at  = DateTimeFormatter::create_date_time_stamp_utc("(yearfull)/(0monthnum)/(0daynum) (24hr):(0min):(0sec)"); 
    my $created_at = Utils::create_datetime_stamp();
    my $updated_at = $created_at;

    my $cdb_hash = {
        'type'              =>  'session_id',
        'created_at'        =>  $created_at,
        'updated_at'        =>  $updated_at,
        'status'            =>  'pending'
    };

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    my $db = Config::get_value_for("database_name");
    my $rc = $c->req('POST', $db, $cdb_hash);

    if ( $rc->{'json'}->{'rev'} ) {
        return $rc->{'json'}->{'rev'};
    } else {
        return " ";
    }
}

sub no_password_login {
    my $tmp_hash = shift; 

    my $error_exists = 0;

    my $q   = new CGI;
    my $rev = $tmp_hash->{one};

    my $session_id = _get_session_id($rev);

    if ( !$session_id ) {
        Page->report_error("user", "Unable to login.", "Invalid session information submitted.");
    }

    my $savepassword    = "no";

    my $cookie_prefix = Config::get_value_for("cookie_prefix");
    my $cookie_domain = Config::get_value_for("domain_name");
    my $author_name   = Config::get_value_for("author_name");

    my ($c1, $c2);

    if ( $savepassword eq "yes" ) {
        $c1 = $q->cookie( -name => $cookie_prefix . "author_name",  -value => "$author_name", -path => "/",  -expires => "+10y",  -domain => ".$cookie_domain");
        $c2 = $q->cookie( -name => $cookie_prefix . "session_id",   -value => "$session_id",  -path => "/",  -expires => "+10y",  -domain => ".$cookie_domain");
    } else {
        $c1 = $q->cookie( -name => $cookie_prefix . "author_name",  -value => "$author_name", -path => "/",  -domain => ".$cookie_domain");
        $c2 = $q->cookie( -name => $cookie_prefix . "session_id",   -value => "$session_id",  -path => "/",  -domain => ".$cookie_domain");
    }

    my $url = Config::get_value_for("home_page");
    print $q->redirect( -url => $url, -cookie => [$c1,$c2] );

}


# update couchdb to change status for the session id from pending to active
# and return the session id.
sub _get_session_id {
    my $user_submitted_rev = shift;

    my $rc;

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    my $db = Config::get_value_for("database_name");

    $rc = $c->req('GET', $db . '/_design/views/_view/session_id?key="'. $user_submitted_rev. '"');

    if ( $rc->{'success'} ) {
        if ( !$rc->{'json'}->{'rows'}->[0] ) {
            return 0;
        } else {
            my $session_id_info = $rc->{'json'}->{'rows'}->[0]->{'value'};
            my $id     = $session_id_info->{'_id'};
            my $rev    = $session_id_info->{'_rev'};
            my $status = $session_id_info->{'status'};
            if ( $status ne "pending" ) {
                return 0;
            }
            if ( $rev ne $user_submitted_rev ) {
                return 0;
            }
            $session_id_info->{'status'}     = "active";
            $session_id_info->{'updated_at'} = Utils::create_datetime_stamp();
            my $url      =  $db . "/" . $id;
            $rc = $c->req('PUT', $url, $session_id_info);
            _update_user_current_session_id($id);
            return $id;
        }
    } else {
        return 0;
    }    
}

sub logout {

    my $config_author_name = Config::get_value_for("author_name");
    my $cookie_author_name = User::get_logged_in_author_name();
    my $cookie_session_id  = User::get_logged_in_session_id();


    if ( $config_author_name ne $cookie_author_name ) {
        Page->report_error("user", "Unable to logout.", "Invalid info submitted.");    
    }

    my $rc;

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    my $db = Config::get_value_for("database_name");

    $rc = $c->req('GET', $db . '/' . $cookie_session_id);

    if ( $rc->{'success'} ) {
        if ( !$rc->{'json'} ) {
            Page->report_error("user", "Unable to logout.", "Invalid info submitted.");    
        } else {
            my $session_id_info = $rc->{'json'};
            my $id     = $session_id_info->{'_id'};
            my $status = $session_id_info->{'status'};

            if ( $status ne "active" ) {
                Page->report_error("user", "Unable to logout.", "Invalid info submitted.");    
            }
            if ( $id ne $cookie_session_id ) {
                Page->report_error("user", "Unable to logout.", "Invalid info submitted.");    
            }
            $session_id_info->{'status'} = "deleted";
            my $url      =  $db . "/" . $id;
            $rc = $c->req('PUT', $url, $session_id_info);
        }
    } else {
        Page->report_error("user", "Unable to logout.", "Invalid info submitted.");    
    }    

    my $q = new CGI;

    my $cookie_prefix = Config::get_value_for("cookie_prefix");
    my $cookie_domain = Config::get_value_for("domain_name");

    my $c1 = $q->cookie( -name => $cookie_prefix . "author_name",            -value => "0", -path => "/", -expires => "-10y", -domain => ".$cookie_domain");
    my $c2 = $q->cookie( -name => $cookie_prefix . "session_id",             -value => "0", -path => "/", -expires => "-10y", -domain => ".$cookie_domain");

    my $url = Config::get_value_for("home_page"); 
    print $q->redirect( -url => $url, -cookie => [$c1,$c2] );

}

sub _update_user_current_session_id {
    my $session_id = shift;

    my $author_name = Config::get_value_for("author_name");
    
    my $rc;

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    my $db = Config::get_value_for("database_name");
    $rc = $c->req('GET', $db . '/_design/views/_view/author?key="' . $author_name . '"');

    if ( !$rc->{'json'}->{'rows'}->[0] ) {
        return " ";
    } else {
        my $author_info = $rc->{'json'}->{'rows'}->[0]->{'value'};
        $author_info->{'current_session_id'} = $session_id;
        my $url      =  $db . "/" . $author_info->{'_id'};
        $rc = $c->req('PUT', $url, $author_info);
    }
}

sub is_valid_login {
    my $submitted_author_name = shift;
    my $submitted_session_id  = shift;

    my $author_name = Config::get_value_for("author_name");
    return 0 if $submitted_author_name ne $author_name;

    # from the user doc
    my $current_session_id = _get_session_id_for($author_name);
    return 0 if $submitted_session_id ne $current_session_id;

    # check to ensure the current_session_id is active in the session_id doc
    my $rc;

    my $c = CouchDB::Client->new();
    $c->testConnection or Page->report_error("system", "Database error.", "The server cannot be reached.");

    my $db = Config::get_value_for("database_name");

    $rc = $c->req('GET', $db . '/' . $submitted_session_id);
    my $session_info = $rc->{'json'};

    return 0 if $session_info->{'status'} ne "active";

    # may use this info later if activie session ids are given an expiration date
      my $created_at  = $session_info->{'created_at'};
      my $updated_at  = $session_info->{'updated_at'};

    return 1;

}


1;

