var MINI = require('minified'); 
var $ = MINI.$, $$ = MINI.$$, EE = MINI.EE;

var keyCounter=0;
var autoSaveInterval=300000   // in milliseconds. default = 5 minutes.
var intervalID=0;
var prevLength=0;
var currLength=0;
var isFocus=0;

function countKeyStrokes () {
    keyCounter++;    
}
    
$(function() {

    onkeydown = function(e){
        if(e.ctrlKey && e.keyCode == 'P'.charCodeAt(0)){
        //  if(e.ctrlKey && e.shiftKey && e.keyCode == 'P'.charCodeAt(0)){
            e.preventDefault();
            previewPost();
        }

        if(e.ctrlKey && e.keyCode == 'S'.charCodeAt(0)){
            e.preventDefault();
            keyCounter++; // force a save even if no editing occurred since user clicked the save link.
            savePost();
        }

        if(e.ctrlKey && e.keyCode == 'U'.charCodeAt(0)){
            e.preventDefault();
            singleScreenMode();
        }

        // bare minimum view. large textarea box only. no border. no nav bar. no other links. no buttons.
        if(e.ctrlKey && e.keyCode == 'J'.charCodeAt(0)){
            e.preventDefault();
            $('body').set({$background: '#fff'} );
            $('#navmenu').set({$display: 'none'} );
            $('#tx_input').set({$background: '#fff'} );
            $('#tx_input').set({$border: 'none'} );
            $('#tx_input').set({$color: '#222'} );
            $('#col_left').set({$padding: '1em 0 0 0'} );
            singleScreenMode();
        }

        // display a 5-line text area box
        if(e.ctrlKey && e.keyCode == 'H'.charCodeAt(0)){
            e.preventDefault();
            $('body').set({$background: '#fff'} );
            $('#navmenu').set({$display: 'none'} );
            $('#tx_input').set({$background: '#fff'} );
            $('#tx_input').set({$border: 'none'} );
            $('#tx_input').set({$color: '#222'} );
            $('#tx_input').set({$height: '150px'} );
            $('#tx_input').set({$margin: '30% 0 0 0'} );
            $('#col_left').set({$padding: '1em 0 0 0'} );
            isFocus=1;
            singleScreenMode();
        }

        if(e.ctrlKey && e.keyCode == 'B'.charCodeAt(0)){
            e.preventDefault();
            $('body').set({$background: '#ddd'} );
            $('#navmenu').set({$display: 'inline'} );
            $('#tx_input').set({$background: '#f8f8ff'} );
            $('#tx_input').set({$border: '1px solid #bbb'} );
            $('#tx_input').set({$color: '#222'} );
            $('#col_left').set({$padding: '0'} );
            if ( isFocus ) {            
                $('#tx_input').set({$margin: '0 0 0 0'} );
                $('#tx_input').set({$height: '100%'} );
                ifFocus=0;
            }
            splitScreenMode();
        }

        if(e.ctrlKey && e.keyCode == 'D'.charCodeAt(0)){
            e.preventDefault();
            $('body').set({$background: '#181818'} );
            $('#tx_input').set({$background: '#181818'} );
            $('#tx_input').set({$color: '#c0c0c0'} );
        }
    }

    // autosave every five minutes
    //    setInterval(function(){savePost()},300000); 
    intervalID = setInterval(function(){savePost()},autoSaveInterval); 


// ******************** 
// SINGLE-SCREEN MODE
// ******************** 

    $('#moveButton').on('click', singleScreenMode);

    function singleScreenMode () {
        $('#text_preview').animate({$$fade: 0}, 500); // fade out
        $('#tx_input').animate({$$fade: 1}, 500); // fade in
        $('#col_right').set('$', '+col -prevsinglecol');
        $('#col_left').set('$', '+singlecol -col');
        $('#col_right').set({$float: 'right'} );
        $('#col_right').set({$position: 'relative'} );
        document.getElementById('tx_input').focus();
    }


// ******************** 
// SPLIT-SCREEN MODE
// ******************** 

    $('#resetButton').on('click', splitScreenMode);

    function splitScreenMode () {
        $('#tx_input').animate({$$fade: 1}, 500); // fade in 
        $('#text_preview').animate({$$fade: 1}, 500); // fade in 
        $('#col_left').set('$', '+col -singlecol');
        $('#col_right').set('$', '+col -prevsinglecol');
        $('#col_right').set({$float: 'right'} );
        $('#col_right').set({$position: 'relative'} );
        document.getElementById('tx_input').focus();
    }


// **********
// PREVIEW
// ********** 

    $('#previewButton').on('click', previewPost);

    function previewPost () {
        var col_type = $('#col_left').get('@class');

        var action        = $('#splitscreenaction').get('@value');
        var cgiapp        = $('#splitscreencgiapp').get('@value');
        var apiurl        = $('#splitscreenapiurl').get('@value');
        var postrev       = $('#splitscreenpostrev').get('@value');

        var postid = 0;
        postid        = $('#splitscreenpostid').get('@value');

        var rest_action = "POST";
        if ( postid > 0 ) {
            rest_action = "PUT";
        }
 
        if ( col_type === "singlecol" ) { 
            $('#col_left').set('$', '+col -singlecol');
            $('#tx_input').animate({$$fade: 0}, 500); // fade out
            $('#col_right').set('$', '+prevsinglecol -col');
            $('#col_right').set({$float: 'normal'} );
            $('#col_right').set({$position: 'absolute'} );
            $('#text_preview').animate({$$fade: 1}, 500); // fade in 
        } 

        var markup = $$('#tx_input').value;

        var regex = /^autosave=(\d+)$/m;
        var myArray;
        if ( myArray = regex.exec(markup) ) {
            if ( myArray[1] > 0  &&  (myArray[1] * 1000) != autoSaveInterval ) {
                autoSaveInterval = myArray[1] * 1000; 
                clearInterval(intervalID);
                intervalID = setInterval(function(){savePost()},autoSaveInterval); 
            }
        }

        markup=escape(markup);

        var paramstr;

// alert(apiurl);

        var author_name  = getCookie('scaupauthor_name');
        var session_id   = getCookie('scaupsession_id');

        var myRequest = {         // create a request object that can be serialized via JSON
            author:      author_name,
            session_id:  session_id,
            submit_type: 'Preview',
            form_type:   'ajax',
            markup:      markup,
            post_id:     postid,
            rev:         postrev
        };

        var json_str = $.toJSON(myRequest);

        jQuery.ajax({
                url: apiurl + '/posts',
                type: rest_action,
                data: json_str,
                contentType:"application/json; charset=utf-8",
                dataType:"json",
                success: function (data, textStatus, xhr) {
                    var obj = $.parseJSON(xhr.responseText);
                 if ( obj['post_type'] == "article" ) {
                     $('#text_preview').set('innerHTML', '<h1>' + obj['title'] + '</h1>' + obj['html']);
                 } else {
                     $('#text_preview').set('innerHTML', obj['html']);
                 }
                    
                },
                error: function (xhr, textStatus, errorThrown) {
                    var obj = $.parseJSON(xhr.responseText);
                    $('#text_preview').set('innerHTML', '<h1>Error</h1>' + obj['user_message'] + ' ' + obj['system_message']);
                }
        });


    } // end preview post function


// **********
// SAVE
// ********** 

    $('#saveButton').on('click', forceSave);

    function forceSave () {
        keyCounter++;
        savePost();
    }

    function savePost () {
        var markup = $$('#tx_input').value;

        currLength = markup.length;

        if ( keyCounter == 0 && currLength == prevLength ) {
            return;
        }
    
        prevLength = currLength; 
        keyCounter=0;
 
        var col_type = $('#col_left').get('@class');

        var action        = $('#splitscreenaction').get('@value');
        var cgiapp        = $('#splitscreencgiapp').get('@value');
        var apiurl        = $('#splitscreenapiurl').get('@value');
        var postid        = $('#splitscreenpostid').get('@value');
        var postrev       = $('#splitscreenpostrev').get('@value');


        markup=escape(markup);

        var sbtype = "Post";
        var rest_action = "POST";

        if ( action === "updateblog" ) {
            sbtype = "Update";
            rest_action = "PUT";
        }

        var author_name  = getCookie('scaupauthor_name');
        var session_id   = getCookie('scaupsession_id');

        var myRequest = {         // create a request object that can be serialized via JSON
            author:      author_name,
            session_id:  session_id,
            submit_type: sbtype,
            form_type:   'ajax',
            markup:      markup,
            post_id:     postid,
            rev:         postrev
        };

        var json_str = $.toJSON(myRequest);

        jQuery.ajax({
                url: apiurl + '/posts',
                type: rest_action,
                data: json_str,
                contentType:"application/json; charset=utf-8",
                dataType:"json",
                success: function (data, textStatus, xhr) {
                    var obj = $.parseJSON(xhr.responseText);
                 if ( obj['post_type'] == "article" ) {
                     $('#text_preview').set('innerHTML', '<h1>' + obj['title'] + '</h1>' + obj['html']);
                 } else {
                     $('#text_preview').set('innerHTML', obj['html']);
                 }
                  $('#saveposttext').set({$color: '#000'});
                  setTimeout(function() {$('#saveposttext').set({$color: '#f8f8f8'})}, 2000);
                  $('#splitscreenaction').set('@value', 'updateblog');
                  $('#splitscreenpostid').set('@value', obj['post_id']);
                  $('#splitscreenpostrev').set('@value', obj['rev']);
                },
                error: function (xhr, textStatus, errorThrown) {
                    var obj = $.parseJSON(xhr.responseText);
                    $('#text_preview').set('innerHTML', '<h1>Error</h1>' + obj['user_message'] + ' ' + obj['system_message']);
                }
        });


    } // send save function

    function getCookie(c_name) {
        var c_value = document.cookie;
        var c_start = c_value.indexOf(" " + c_name + "=");
        if (c_start == -1) {
            c_start = c_value.indexOf(c_name + "=");
        }
        if (c_start == -1) {
            c_value = null;
        }
        else {
            c_start = c_value.indexOf("=", c_start) + 1;
            var c_end = c_value.indexOf(";", c_start);
            if (c_end == -1) {
                c_end = c_value.length;
            }
            c_value = unescape(c_value.substring(c_start,c_end));
        }
        return c_value;
    }

});

