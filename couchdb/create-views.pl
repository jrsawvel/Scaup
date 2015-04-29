#!/usr/bin/perl -wT

use JSON::PP;
use CouchDB::Client;
use Data::Dumper;


my $db = "scaupdvlp1";


my $views = <<VIEWS;
{
  "_id":"_design/views"
}
VIEWS

# convert json string into a perl hash
my $perl_hash = decode_json $views;


# homepage stream of posts listed by updated date
my $view_js =  <<VIEWJS1;
function(doc) {
    if( doc.type === 'post' && doc.post_status === 'public' ) {
        emit(doc.updated_at, {slug: doc._id, text_intro: doc.text_intro, more_text_exists: doc.more_text_exists, tags: doc.tags, post_type: doc.post_type, author: doc.author, updated_at: doc.updated_at, reading_time: doc.reading_time});
    }
}
VIEWJS1
$perl_hash->{'views'}->{'stream'}->{'map'} = $view_js;



# get a single post HTML display
$view_js =  <<VIEWJS2;
function(doc) {
    if( doc.type === 'post' && doc.post_status === 'public' ) {
        emit(doc._id, {slug: doc._id, html: doc.html, title: doc.title, author: doc.author, post_type: doc.post_type, created_at: doc.created_at, updated_at: doc.updated_at, reading_time: doc.reading_time, word_count: doc.word_count});
    }
}
VIEWJS2
$perl_hash->{'views'}->{'post'}->{'map'} = $view_js;



# get a single post - markup for edit
$view_js =  <<VIEWJS22;
function(doc) {
    if( doc.type === 'post' && doc.post_status === 'public' ) {
        emit(doc._id, {_rev: doc._rev, slug: doc._id, markup: doc.markup, title: doc.title, post_type: doc.post_type});
    }
}
VIEWJS22
$perl_hash->{'views'}->{'post_markup'}->{'map'} = $view_js;



# get all info for a single post
$view_js =  <<VIEWJS23;
function(doc) {
    if( doc.type === 'post' && doc.post_status === 'public' ) {
        emit(doc._id, {slug: doc._id, markup: doc.markup, html: doc.html, title: doc.title, author: doc.author, post_type: doc.post_type, created_at: doc.created_at, updated_at: doc.updated_at, reading_time: doc.reading_time, word_count: doc.word_count}); 
    }
}
VIEWJS23
$perl_hash->{'views'}->{'post_full'}->{'map'} = $view_js;



# 24apr2015 - implemented elasticsearch, therefore i no longer need this view, but i'll keep around, just in case ...
# get stream of results for a single word search that is surrounded by word boundaries and not a word that's a substring.
# $view_js =  <<VIEWJS3;
#function(doc) {
#    if( doc.type === 'post' && doc.post_status === 'public' ) {
#        var txt = doc.markup;
#        var words = txt.replace(/[!.,;]+/g,"").toLowerCase().split(" ");
#        for (var word in words) {
#            emit([ words[word], doc.updated_at ], {slug: doc._id, text_intro: doc.text_intro, more_text_exists: doc.more_text_exists, tags: doc.tags, post_type: doc.post_type, author: doc.author, updated_at: doc.updated_at, reading_time: doc.reading_time});
#        }
#    }
#}
#VIEWJS3
#$perl_hash->{'views'}->{'single_word_search'}->{'map'} = $view_js;




# get a stream of deleted posts executed by the logged-in author

$view_js =  <<VIEWJS5;
function(doc) {
    if( doc.type === 'post' && doc.post_status === 'deleted' ) {
        emit(doc.updated_at, {slug: doc._id, title: doc.title, post_type: doc.post_type});
    }
}
VIEWJS5

$perl_hash->{'views'}->{'deleted_posts'}->{'map'} = $view_js;



# get ALL posts

#my $view_js =  <<VIEWJS6;
#function(doc) {
#    if( doc.type === 'post' ) {
#        emit(doc.created_at, doc);
#    }
#}
#VIEWJS6
#
#$perl_hash->{'views'}->{'all_posts'}->{'map'} = $view_js;



# get author info

$view_js =  <<VIEWJS7;
function(doc) {
    if( doc.type === 'author' ) {
        emit(doc._id, doc);
    }
}
VIEWJS7

$perl_hash->{'views'}->{'author'}->{'map'} = $view_js;



# get session id info

$view_js =  <<VIEWJS8;
function(doc) {
    if( doc.type === 'session_id' ) {
        emit(doc._rev, doc);
    }
}
VIEWJS8

$perl_hash->{'views'}->{'session_id'}->{'map'} = $view_js;



# tag search on the tag array
$view_js = <<VIEWJS9;
function(doc) {
  if( doc.type === 'post' && doc.post_status === 'public' && doc.tags.length > 0) {
    doc.tags.forEach(function(i) {
      emit( [i, doc.updated_at ], {slug: doc._id, text_intro: doc.text_intro, more_text_exists: doc.more_text_exists, tags: doc.tags, post_type: doc.post_type, author: doc.author, updated_at: doc.updated_at, reading_time: doc.reading_time});
    });
  }
}
_count 
VIEWJS9
$perl_hash->{'views'}->{'tag_search'}->{'map'} = $view_js;





my $c = CouchDB::Client->new();
$c->testConnection or die "The server cannot be reached";

# create the view doc entry
my $rc = $c->req('POST', $db, $perl_hash);
print Dumper $rc;

print "\n\n\n";

$rc = $c->req('GET', $db . '/_design/views');
print Dumper $rc;
print "\n";

