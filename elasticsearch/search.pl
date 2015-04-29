#!/usr/bin/perl -wT

use strict;
use LWP::UserAgent;
use JSON::PP;
use Data::Dumper;
use URI::Escape;


my $ua = LWP::UserAgent->new;

my $search_string = "SCARF FOR MOM";

$search_string = "beer";

$search_string = "black cloister";



$search_string = uri_escape($search_string);

my $db = "scaupdvlp1";

my $url = 'http://127.0.0.1:9200/' . $db . '/' . $db . '/_search?size=10&q=%2Btype%3Apost+%2Bpost_status%3Apublic+%2Bmarkup%3A' . $search_string;

# print $url . "\n";

my $response = $ua->get($url);

if ( !$response->is_success ) {
    die "Unable to complete request.";
}

my $rc = decode_json $response->content;

print "total hits = $rc->{'hits'}->{'total'}\n";
print "===================================\n";

print Dumper $rc;
#print "===================================\n";


my $posts_array_ref = $rc->{'hits'}->{'hits'};

# print Dumper $posts_array_ref;
# print "===================================\n";


# print "\n\n\n single post info \n\n";

# my $post = $rc->{'hits'}->{'hits'}->[0]->{'_source'};

# print Dumper $post;
# print $post->{'text_intro'} . "\n";
#print $post->{'more_text_exists'} . "\n";
#print $post->{'updated_at'} . "\n";
#print $post->{'reading_time'} . " min\n";
#my $tags_hash_ref = $post->{'tags'};
#foreach my $tag ( @$tags_hash_ref ) {
#    print $tag . "\n";
#}


print "===================================\n";

my $stream = $rc->{'hits'}->{'hits'};

# print Dumper $stream;

print "===================================\n";

my $number_of_matches = @$stream;

print "number of search results = $number_of_matches\n";

my @posts;

my %post_hash;

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
        push(@posts, $hash_ref->{'_source'});
    }

# print Dumper \@posts;
