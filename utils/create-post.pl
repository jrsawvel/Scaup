#!/usr/bin/perl -wT

use strict;

use lib '../lib';
use lib '../lib/CPAN';

use REST::Client;
use JSON::PP;
use HTML::Entities;
use Encode;

use App::Config;
use App::Utils;

my $api_url = Config::get_value_for("api_url");

my $json_input;

my $date_time = Utils::create_datetime_stamp();

my %hash;
$hash{author}      = Config::get_value_for("author_name");
$hash{session_id}  = "123456778";
$hash{submit_type} = "Post";
$hash{markup}      = "This is a test post from a Perl script. $date_time";

$hash{markup} = Encode::decode_utf8($hash{markup});
$hash{markup} = HTML::Entities::encode($hash{markup},'^\n^\r\x20-\x25\x27-\x7e');

my $json = encode_json \%hash;

my $headers = {
    'Content-type' => 'application/json'
};

my $rest = REST::Client->new( {
    host => $api_url,
} );

$rest->POST( "/posts" , $json , $headers );

my $rc = $rest->responseCode();

print "rc = $rc\n";

print "response content =\n" . $rest->responseContent(); 


