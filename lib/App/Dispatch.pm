package App::Dispatch;
use strict;
use warnings;
use App::Modules;

my %cgi_params = Utils::get_cgi_params_from_path_info("function", "one", "two", "three", "four");

my $dispatch_for = {
    showerror          =>   sub { return \&do_sub(       "Utils",          "do_invalid_function"      ) },
    login              =>   sub { return \&do_sub(       "User",           "show_login_form"          ) },
    logout             =>   sub { return \&do_sub(       "User",           "logout"                   ) },
    dologin            =>   sub { return \&do_sub(       "User",           "mail_login_link"          ) },
    nopwdlogin         =>   sub { return \&do_sub(       "User",           "no_password_login"        ) },
    stream             =>   sub { return \&do_sub(       "Stream",         "show_stream"              ) },
    searchform         =>   sub { return \&do_sub(       "Stream",         "show_search_form"         ) },
    createpost         =>   sub { return \&do_sub(       "Post",           "create_post"              ) },
    post               =>   sub { return \&do_sub(       "Post",           "show_post"                ) },
    search             =>   sub { return \&do_sub(       "Stream",         "search"                   ) },
    delete             =>   sub { return \&do_sub(       "Post",           "delete"                   ) },
    deleted            =>   sub { return \&do_sub(       "Stream",         "show_deleted_posts"       ) },
    undelete           =>   sub { return \&do_sub(       "Post",           "undelete"                 ) },
    tag                =>   sub { return \&do_sub(       "Stream",         "tag_search"               ) },
    compose            =>   sub { return \&do_sub(       "Post",           "show_new_post_form"       ) },
    edit               =>   sub { return \&do_sub(       "Post",           "show_post_to_edit"        ) },
    updatepost         =>   sub { return \&do_sub(       "Post",           "update_post"              ) },
    splitscreen        =>   sub { return \&do_sub(       "Post",           "show_splitscreen_form"    ) },
    splitscreenedit    =>   sub { return \&do_sub(       "Post",           "splitscreen_edit"         ) }, 
};

sub execute {
    my $function = $cgi_params{function};

    $dispatch_for->{stream}->() if !defined($function) or !$function;

#    $dispatch_for->{showerror}->($function) unless exists $dispatch_for->{$function} ;
    $dispatch_for->{post}->($function) unless exists $dispatch_for->{$function} ;

    defined $dispatch_for->{$function}->();
}

sub do_sub {
    my $module = shift;
    my $subroutine = shift;
    eval "require App::$module" or Page->report_error("user", "Runtime Error (1):", $@);
    my %hash = %cgi_params;
    my $coderef = "$module\:\:$subroutine(\\%hash)"  or Page->report_error("user", "Runtime Error (2):", $@);
    eval "{ &$coderef };" or Page->report_error("user", "Runtime Error (2):", $@) ;
}

1;
