#!/usr/bin/perl -wT

use lib '/home/scaup/Scaup/lib';

use CouchDB::Client;
use Data::Dumper;

my $rc;
my $c = CouchDB::Client->new();
$c->testConnection or die "The server cannot be reached";

# $rc = $c->req('GET', 'scaupdvlp1/_design/views/_view/stream/?descending=true&limit=16');
$rc = $c->req('GET', 'scaupdvlp1/_design/views/_view/stream2/?startkey=[{}, "test-post-that-that-autolinks-hashtags"]&descending=true&limit=16');
# $rc = $c->req('GET', 'scaupdvlp1/_design/views/_view/stream/?descending=true&limit=16&skip=15');
print Dumper $rc;
print "\n";

my $stream = $rc->{'json'}->{'rows'};
my $row_count = @$stream;

print "number of articles returned = $row_count\n";
print "row 16 id = $stream->[15]->{'id'}\n";


#my @posts;
#foreach my $hash_ref ( @$stream ) {
#    push(@posts, $hash_ref->{'value'});
#}
#print Dumper @posts;

