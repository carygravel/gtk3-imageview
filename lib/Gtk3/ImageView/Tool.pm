package Gtk3::ImageView::Tool;

use warnings;
use strict;
use Glib qw(TRUE FALSE);    # To get TRUE and FALSE

sub new {
    my $class = shift;
    my $view  = shift;
    return bless { _view => $view, }, $class;
}

sub view {
    my $self = shift;
    $self->{_view};
}

sub button_pressed {
    my $self  = shift;
    my $event = shift;
    FALSE;
}

sub button_released {
    my $self  = shift;
    my $event = shift;
    FALSE;
}

sub motion {
    my $self  = shift;
    my $event = shift;
    FALSE;
}

sub cursor_at_point {
    my ( $self, $x, $y ) = @_;
    my $display     = Gtk3::Gdk::Display::get_default;
    my $cursor_type = $self->cursor_type_at_point( $x, $y );
    return unless defined $cursor_type;
    Gtk3::Gdk::Cursor->new_from_name( $display, $cursor_type );
}

sub cursor_type_at_point {
    my ( $self, $x, $y ) = @_;
    undef;
}

# compatibility layer

sub signal_connect {
    my $self = shift;
    $self->view->signal_connect(@_);
}

sub signal_handler_disconnect {
    my $self = shift;
    $self->view->signal_handler_disconnect(@_);
}

1;
