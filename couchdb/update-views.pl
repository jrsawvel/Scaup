#!/usr/bin/perl -wT

use CouchDB::Client;
use Data::Dumper;


my $db = "scaupdvlp1";

my $view_js;

my $c = CouchDB::Client->new();
$c->testConnection or die "The server cannot be reached";

$rc = $c->req('GET', $db . '/_design/views');

my $perl_hash = $rc->{'json'};


# homepage stream of posts listed by updated date
$view_js =  <<VIEWJS1;
function(doc) {
    if( doc.type === 'post' && doc.post_status === 'public' ) {
        emit(doc.created_at, {slug: doc._id, text_intro: doc.text_intro, more_text_exists: doc.more_text_exists, tags: doc.tags, post_type: doc.post_type, author: doc.author, updated_at: doc.updated_at, reading_time: doc.reading_time});
    }
}
VIEWJS1
$perl_hash->{'views'}->{'created_at_stream'}->{'map'} = $view_js;



##############################################


# update the view doc entry
$rc = $c->req('PUT', $db . '/_design/views', $perl_hash);
print Dumper $rc;

