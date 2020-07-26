package Gtk3::ImageView::Tool::SelectorDragger;

use warnings;
use strict;
use base 'Gtk3::ImageView::Tool';
use Glib qw(TRUE FALSE);    # To get TRUE and FALSE

our $VERSION = 1;

sub new {
    my $class = shift;
    my $view  = shift;
    my $self  = Gtk3::ImageView::Tool->new($view);
    $self->{_tool} = Gtk3::ImageView::Tool::Selector->new($view);
    return bless $self, $class;
}

sub button_pressed {
    my $self  = shift;
    my $event = shift;

    # left mouse button
    if ( $event->button == 1 ) {
        $self->{_tool} = Gtk3::ImageView::Tool::Selector->new( $self->view );
    }
    elsif ( $event->button == 2 ) {    # middle mouse button
        $self->{_tool} = Gtk3::ImageView::Tool::Dragger->new( $self->view );
    }
    else {
        return FALSE;
    }
    return $self->{_tool}->button_pressed($event);
}

sub button_released {
    my $self  = shift;
    my $event = shift;
    $self->{_tool}->button_released($event);
    $self->{_tool} = Gtk3::ImageView::Tool::Selector->new( $self->view );
    return;
}

sub motion {
    my $self  = shift;
    my $event = shift;
    $self->{_tool}->motion($event);
    return;
}

sub cursor_type_at_point {
    my ( $self, $x, $y ) = @_;
    return $self->{_tool}->cursor_type_at_point( $x, $y );
}

1;
