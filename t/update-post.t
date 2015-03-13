#!/usr/bin/perl -wT

# update post

use strict;

use lib 'lib';
use lib 'lib/CPAN';

# use Test::More qw(no_plan);
use Test::More tests => 13;

BEGIN {
    use_ok('REST::Client');
    use_ok('JSON::PP');
    use_ok('App::Config');
    use_ok('App::Utils');
}

#my $api_url = Config::get_value_for("api_url");
my $api_url = "http://scaup.soupmode.com";

ok(defined($api_url), 'read api url from config file.');

my $json_input;



#################### get user's logged-in info

my $user_id      = "0";
my $user_name    = "xyz";
my $session_id   = "123456";

ok(defined($user_id),     'user id parsed from json input.');
ok(defined($user_name),   'user name parsed from json input.');
ok(defined($session_id),  'session id parsed from json input.');


my $post_id      = "this-is-a-test";
my $post_digest  = "123456";

ok(defined($post_id),     'post id parsed from json input.');
ok(defined($post_digest), 'post digest parsed from json input.');


#################### new post text

my $date_time = Utils::create_datetime_stamp();

my %hash;
$hash{post_text}   = "# new UPDATED post text $date_time\n\nhere is some more text.\n\ntags #grebe #blogging";
$hash{post_id}     = $post_id;
$hash{post_digest} = $post_digest;
$hash{submit_type} = "Update";
my $json = encode_json \%hash;

my $headers = {
    'Content-type' => 'application/x-www-form-urlencoded'
};

my $rest = REST::Client->new( {
    host => $api_url,
} );

my $pdata = {
    'json'       => $json,
    'user_name'  => $user_name,
    'user_id'    => $user_id,
    'session_id' => $session_id,
};
my $params = $rest->buildQuery( $pdata );

$params =~ s/\?//;

$rest->PUT( "/posts" , $params , $headers );

my $rc = $rest->responseCode();

ok($rc >= 200 && $rc < 300, 'post successfully created.');

my $fh;

open($fh, ">", "t/updated-post-info.json") or die "cannot open > updated-post-info.json: $!";

print $fh $rest->responseContent() . "\n"; 

close($fh) or warn "close failed: $!";


