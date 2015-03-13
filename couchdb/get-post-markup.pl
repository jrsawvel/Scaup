#!/usr/bin/perl -wT

use lib '/home/scaup/Scaup/lib';

use CouchDB::Client;
use Data::Dumper;

my $rc;
my $c = CouchDB::Client->new();
$c->testConnection or die "The server cannot be reached";

$rc = $c->req('GET', 'scaupdvlp1/_design/views/_view/post_markup?key="thu-feb-19-2015-weather"');
print Dumper $rc;
print "\n";

# my $stream = $rc->{'json'}->{'rows'};


