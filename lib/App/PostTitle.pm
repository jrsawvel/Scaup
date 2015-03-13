package PostTitle;

use strict;
use warnings;
use HTML::Entities;
use NEXT;

{
    my $MAX_TITLE_LEN = 150;

    sub new {
        my ($class) = @_;

        my $ self = {
            after_title_markup => undef,
            err                => 0,
            err_str            => undef,
            title              => undef,
            posttitle          => undef,
            slug               => undef,
            postid             => 0,
            markup_type        => "textile",
            content_type       => undef
        };

        bless($self, $class);
        return $self;
    }

    sub process_title {
        my ($self, $markup) = @_;
        $self->{title} = $markup;

        if ( $self->{title} =~ m/(.+)/ ) {
            my $tmp_title = $1;
            if ( length($tmp_title) < $MAX_TITLE_LEN+1  ) {
                my $tmp_title_len = length($tmp_title);
                $self->{title} = $tmp_title;
                my $tmp_total_len = length($markup);
                $self->{after_title_markup} = substr $markup, $tmp_title_len, $tmp_total_len - $tmp_title_len;
            } else {
                $self->{title} = substr $markup, 0, $MAX_TITLE_LEN;
                my $tmp_total_len = length($markup);
                $self->{after_title_markup} = substr $markup, $MAX_TITLE_LEN, $tmp_total_len - $MAX_TITLE_LEN;
            }   
        }
        if ( !defined($self->{title}) || length($self->{title}) < 1 ) {
            $self->{err_str} .= "You must give a title for your post.";
            $self->{err} = 1;
        } else {
            if ( $self->{title} =~ m/^h1\.(.+)/i ) {
                $self->{title} = $1;
                $self->{content_type} = "article";
                $self->{markup_type} = "textile";
            } elsif ( $self->{title} =~ m/^#[\s+](.+)/ ) {
                $self->{title} = $1;
                $self->{content_type} = "article";
                $self->{markup_type} = "markdown";
            } else {
                $self->{content_type} = "note";
                if ( length($self->{title}) > 75 ) {
                    $self->{after_title_markup} = $markup;
                    $self->{title} = substr $self->{title}, 0, 75;
                }
            }
        }
        $self->{posttitle}  = _trim_spaces($self->{title});
        # $self->{posttitle}  = ucfirst($self->{posttitle});
        $self->{posttitle}  = HTML::Entities::encode_entities($self->{posttitle}, '<>');
        $self->{slug}       = _clean_title($self->{posttitle});
    } # end process_title

    sub set_post_id {
        my ($self, $postid) = @_;
        $self->{postid} = $postid;
    }

    sub get_title {
        my ($self) = @_;
        return $self->{title};
    }
         
    sub get_post_title {
        my ($self) = @_;
        return $self->{posttitle};
    }

    sub get_slug {
        my ($self) = @_;
        return $self->{slug};
    }

    sub get_after_title_markup {
        my ($self) = @_;
        return $self->{after_title_markup};
    }

    sub get_content_type {
        my ($self) = @_;
        return $self->{content_type};
    }

    sub get_markup_type {
        my ($self) = @_;
        return $self->{markup_type};
    }

    sub is_error {
        my ($self) = @_;
        return $self->{err};
    }

    sub get_error_string {
        my ($self) = @_;
        return $self->{err_str};
    }

    sub _trim_spaces {
        my $str = shift;
        if ( !defined($str) ) {
            return "";
        }
        # remove leading spaces.   
        $str  =~ s/^\s+//;
        # remove trailing spaces.
        $str  =~ s/\s+$//;
        return $str;
    }

    sub _clean_title {
        my $str = shift;
        $str =~ s|[-]||g;
        $str =~ s|[ ]|-|g;
        $str =~ s|[:]|-|g;
        $str =~ s|--|-|g;
        # only use alphanumeric, underscore, and dash in friendly link url
        $str =~ s|[^\w-]+||g;
        return lc($str);
    }
}

# todo add destroy object code

1;



