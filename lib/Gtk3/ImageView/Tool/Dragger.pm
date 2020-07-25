package Gtk3::ImageView::Tool::Dragger;

use warnings;
use strict;
use base 'Gtk3::ImageView::Tool';
use Glib qw(TRUE FALSE);    # To get TRUE and FALSE

sub button_pressed {
    my $self  = shift;
    my $event = shift;

    # Convert the widget size to image scale to make the comparisons easier
    my $allocation = $self->view->get_allocation;
    ( $allocation->{width}, $allocation->{height} ) =
      $self->view->_to_image_distance( $allocation->{width},
        $allocation->{height} );
    my $pixbuf_size = $self->view->get_pixbuf_size;
    if (   $allocation->{width} > $pixbuf_size->{width}
        && $allocation->{height} > $pixbuf_size->{height} )
    {
        # Nothing to drag around, let drag-n-drop work
        return FALSE;
    }

    $self->{drag_start} = { x => $event->x, y => $event->y };
    $self->{dragging}   = TRUE;
    $self->view->update_cursor( $event->x, $event->y );
    return TRUE;
}

sub button_released {
    my $self  = shift;
    my $event = shift;
    $self->{dragging} = FALSE;
    $self->view->update_cursor( $event->x, $event->y );
}

sub motion {
    my $self  = shift;
    my $event = shift;
    if ( not $self->{dragging} ) { return FALSE }
    my $offset = $self->view->get_offset;
    my $zoom   = $self->view->get_zoom;
    my $ratio  = $self->view->get_resolution_ratio;
    my $offset_x =
      $offset->{x} + ( $event->x - $self->{drag_start}{x} ) / $zoom * $ratio;
    my $offset_y =
      $offset->{y} + ( $event->y - $self->{drag_start}{y} ) / $zoom;
    ( $self->{drag_start}{x}, $self->{drag_start}{y} ) =
      ( $event->x, $event->y );
    $self->view->set_offset( $offset_x, $offset_y );
}

sub cursor_type_at_point {
    my ( $self, $x, $y ) = @_;
    ( $x, $y ) = $self->view->_to_image_coords( $x, $y );
    my $pixbuf_size = $self->view->get_pixbuf_size;
    if (    $x > 0
        and $x < $pixbuf_size->{width}
        and $y > 0
        and $y < $pixbuf_size->{height} )
    {
        if ( $self->{dragging} ) {
            return 'grabbing';
        }
        else {
            return 'grab';
        }
    }
}

1;
