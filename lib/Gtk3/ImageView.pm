package Gtk3::ImageView;

use warnings;
use strict;
no if $] >= 5.018, warnings => 'experimental::smartmatch';
use feature 'switch';
use Cairo;
use Glib qw(TRUE FALSE);    # To get TRUE and FALSE
use Gtk3;
use Gtk3::ImageView::Tool;
use Gtk3::ImageView::Tool::Dragger;
use Gtk3::ImageView::Tool::Selector;
use List::Util qw(min);
use Scalar::Util qw(blessed);
use Carp;
use Readonly;
Readonly my $HALF     => 0.5;
Readonly my $MAX_ZOOM => 100;

our $VERSION = 1;

use Glib::Object::Subclass Gtk3::DrawingArea::, signals => {
    'zoom-changed' => {
        param_types => ['Glib::Float'],    # new zoom
    },
    'offset-changed' => {
        param_types => [ 'Glib::Int', 'Glib::Int' ],    # new offset
    },
    'selection-changed' => {
        param_types => ['Glib::Scalar'],    # Gdk::Rectangle of selection area
    },
    'tool-changed' => {
        param_types => ['Glib::Scalar'],    # new Gtk3::ImageView::Tool
    },
    'dnd-start' => {
        param_types => [
            'Glib::Float',                  # x
            'Glib::Float',                  # y
            'Glib::UInt',                   # button
        ],
        return_type => 'Glib::Boolean',
        flags       => ['run-last'],
    }
  },
  properties => [
    Glib::ParamSpec->object(
        'pixbuf',                           # name
        'pixbuf',                           # nickname
        'Gtk3::Gdk::Pixbuf to be shown',    # blurb
        'Gtk3::Gdk::Pixbuf',
        [qw/readable writable/]             # flags
    ),
    Glib::ParamSpec->scalar(
        'offset',                           # name
        'Image offset',                     # nick
        'Gdk::Rectangle hash of x, y',      # blurb
        [qw/readable writable/]             # flags
    ),
    Glib::ParamSpec->float(
        'zoom',                             # name
        'zoom',                             # nick
        'zoom level',                       # blurb
        0.001,                              # minimum
        100.0,                              # maximum
        1.0,                                # default_value
        [qw/readable writable/]             # flags
    ),
    Glib::ParamSpec->float(
        'resolution-ratio',                      # name
        'resolution-ratio',                      # nick
        'Ratio of x-resolution/y-resolution',    # blurb
        0.0001,                                  # minimum
        1000.0,                                  # maximum
        1.0,                                     # default_value
        [qw/readable writable/]                  # flags
    ),
    Glib::ParamSpec->scalar(
        'tool',                                  # name
        'tool',                                  # nickname
        'Active Gtk3::ImageView::Tool',          # blurb
        [qw/readable writable/]                  # flags
    ),
    Glib::ParamSpec->scalar(
        'selection',                                 # name
        'Selection',                                 # nick
        'Gdk::Rectangle hash of selected region',    # blurb
        [qw/readable writable/]                      # flags
    ),
    Glib::ParamSpec->boolean(
        'zoom-to-fit',                               # name
        'Zoom to fit',                               # nickname
        'Whether the zoom factor is automatically calculated to fit the window'
        ,                                            # blurb
        TRUE,                                        # default
        [qw/readable writable/]                      # flags
    ),
  ];

sub INIT_INSTANCE {
    my $self = shift;
    $self->signal_connect( draw                   => \&_draw );
    $self->signal_connect( 'button-press-event'   => \&_button_pressed );
    $self->signal_connect( 'button-release-event' => \&_button_released );
    $self->signal_connect( 'motion-notify-event'  => \&_motion );
    $self->signal_connect( 'scroll-event'         => \&_scroll );
    $self->signal_connect( configure_event        => \&_configure_event );
    $self->set_app_paintable(TRUE);

    if (
        $Glib::Object::Introspection::VERSION <
        0.043    ## no critic (ProhibitMagicNumbers)
      )
    {
        $self->add_events(
            ${ Gtk3::Gdk::EventMask->new(qw/exposure-mask/) } |
              ${ Gtk3::Gdk::EventMask->new(qw/button-press-mask/) } |
              ${ Gtk3::Gdk::EventMask->new(qw/button-release-mask/) } |
              ${ Gtk3::Gdk::EventMask->new(qw/pointer-motion-mask/) } |
              ${ Gtk3::Gdk::EventMask->new(qw/scroll-mask/) } );
    }
    else {
        $self->add_events(
            Glib::Object::Introspection->convert_sv_to_flags(
                'Gtk3::Gdk::EventMask', 'exposure-mask' ) |
              Glib::Object::Introspection->convert_sv_to_flags(
                'Gtk3::Gdk::EventMask', 'button-press-mask' ) |
              Glib::Object::Introspection->convert_sv_to_flags(
                'Gtk3::Gdk::EventMask', 'button-release-mask' ) |
              Glib::Object::Introspection->convert_sv_to_flags(
                'Gtk3::Gdk::EventMask', 'pointer-motion-mask' ) |
              Glib::Object::Introspection->convert_sv_to_flags(
                'Gtk3::Gdk::EventMask', 'scroll-mask'
              )
        );
    }
    $self->set_tool( Gtk3::ImageView::Tool::Dragger->new($self) );
    $self->set_redraw_on_allocate(FALSE);
    return $self;
}

sub SET_PROPERTY {
    my ( $self, $pspec, $newval ) = @_;
    my $name       = $pspec->get_name;
    my $oldval     = $self->get($name);
    my $invalidate = FALSE;
    if (   ( defined $newval and defined $oldval and $newval ne $oldval )
        or ( defined $newval xor defined $oldval ) )
    {
        given ($name) {
            when ('pixbuf') {
                $self->{$name} = $newval;
                $invalidate = TRUE;
            }
            when ('zoom') {
                $self->{$name} = $newval;
                $self->signal_emit( 'zoom-changed', $newval );
                $invalidate = TRUE;
            }
            when ('offset') {
                if (   ( defined $newval xor defined $oldval )
                    or $oldval->{x} != $newval->{x}
                    or $oldval->{y} != $newval->{y} )
                {
                    $self->{$name} = $newval;
                    $self->signal_emit( 'offset-changed', $newval->{x},
                        $newval->{y} );
                    $invalidate = TRUE;
                }
            }
            when ('resolution-ratio') {
                $self->{$name} = $newval;
                $invalidate = TRUE;
            }
            when ('selection') {
                if (   ( defined $newval xor defined $oldval )
                    or $oldval->{x} != $newval->{x}
                    or $oldval->{y} != $newval->{y}
                    or $oldval->{width} != $newval->{width}
                    or $oldval->{height} != $newval->{height} )
                {
                    $self->{$name} = $newval;
                    $invalidate = TRUE;
                    $self->signal_emit( 'selection-changed', $newval );
                }
            }
            when ('tool') {
                $self->{$name} = $newval;
                if ( defined $self->get_selection ) {
                    $invalidate = TRUE;
                }
                $self->signal_emit( 'tool-changed', $newval );
            }
            default {
                $self->{$name} = $newval;

                #                $self->SUPER::SET_PROPERTY( $pspec, $newval );
            }
        }
        if ($invalidate) {
            $self->queue_draw();
        }
    }
    return;
}

sub set_pixbuf {
    my ( $self, $pixbuf, $zoom_to_fit ) = @_;
    $self->set( 'pixbuf', $pixbuf );
    $self->set_zoom_to_fit($zoom_to_fit);
    if ( not $zoom_to_fit ) {
        $self->set_offset( 0, 0 );
    }
    return;
}

sub get_pixbuf {
    my ($self) = @_;
    return $self->get('pixbuf');
}

sub get_pixbuf_size {
    my ($self) = @_;
    my $pixbuf = $self->get_pixbuf;
    if ( defined $pixbuf ) {
        return { width => $pixbuf->get_width, height => $pixbuf->get_height };
    }
    return;
}

sub _button_pressed {
    my ( $self, $event ) = @_;
    return $self->get_tool->button_pressed($event);
}

sub _button_released {
    my ( $self, $event ) = @_;
    $self->get_tool->button_released($event);
    return;
}

sub _motion {
    my ( $self, $event ) = @_;
    $self->update_cursor( $event->x, $event->y );
    $self->get_tool->motion($event);
    return;
}

sub _scroll {
    my ( $self, $event ) = @_;
    my ( $center_x, $center_y ) =
      $self->to_image_coords( $event->x, $event->y );
    my $zoom;
    $self->set_zoom_to_fit(FALSE);
    if ( $event->direction eq 'up' ) {
        $zoom = $self->get_zoom * 2;
    }
    else {
        $zoom = $self->get_zoom / 2;
    }
    $self->_set_zoom_with_center( $zoom, $center_x, $center_y );
    return;
}

sub _draw {
    my ( $self, $context ) = @_;
    my $allocation = $self->get_allocation;
    my $style      = $self->get_style_context;
    my $pixbuf     = $self->get_pixbuf;
    my $ratio      = $self->get_resolution_ratio;
    my $viewport   = $self->get_viewport;
    $style->add_class('imageview');

    $style->save;
    $style->add_class(Gtk3::STYLE_CLASS_BACKGROUND);
    Gtk3::render_background( $style, $context, $allocation->{x},
        $allocation->{y}, $allocation->{width}, $allocation->{height} );
    $style->restore;

    if ( defined $pixbuf ) {
        if ( $pixbuf->get_has_alpha ) {
            $style->save;
            $style->add_class('transparent');
            my ( $x1, $y1 ) = $self->to_widget_coords( 0, 0 );
            my ( $x2, $y2 ) =
              $self->to_widget_coords( $pixbuf->get_width,
                $pixbuf->get_height );
            Gtk3::render_background( $style, $context, $x1, $y1, $x2 - $x1,
                $y2 - $y1 );
            $style->restore;
        }

        my $zoom = $self->get_zoom;
        $context->scale( $zoom / $ratio, $zoom );
        my $offset = $self->get_offset;
        $context->translate( $offset->{x}, $offset->{y} );
        Gtk3::Gdk::cairo_set_source_pixbuf( $context, $pixbuf, 0, 0 );
    }
    else {
        my $bgcol = $style->get( 'normal', 'background-color' );
        Gtk3::Gdk::cairo_set_source_rgba( $context, $bgcol );
    }
    $context->paint;

    my $selection = $self->get_selection;
    if ( defined $pixbuf and defined $selection ) {
        my ( $x, $y, $w, $h, ) = (
            $selection->{x},     $selection->{y},
            $selection->{width}, $selection->{height},
        );
        if ( $w <= 0 or $h <= 0 ) { return TRUE }

        $style->save;
        $style->add_class(Gtk3::STYLE_CLASS_RUBBERBAND);
        Gtk3::render_background( $style, $context, $x, $y, $w, $h );
        Gtk3::render_frame( $style, $context, $x, $y, $w, $h );
        $style->restore;
    }
    return TRUE;
}

sub _configure_event {
    my ( $self, $event ) = @_;
    if ( $self->get_zoom_to_fit ) {
        $self->zoom_to_box( $self->get_pixbuf_size );
    }
    return;
}

# setting the zoom via the public API disables zoom-to-fit

sub set_zoom {
    my ( $self, $zoom ) = @_;
    $self->set_zoom_to_fit(FALSE);
    $self->_set_zoom_no_center($zoom);
    return;
}

sub _set_zoom {
    my ( $self, $zoom ) = @_;
    if ( $zoom > $MAX_ZOOM ) { $zoom = $MAX_ZOOM }
    $self->set( 'zoom', $zoom );
    return;
}

sub get_zoom {
    my ($self) = @_;
    return $self->get('zoom');
}

# convert x, y in image coords to widget coords
sub to_widget_coords {
    my ( $self, $x, $y ) = @_;
    my $zoom   = $self->get_zoom;
    my $ratio  = $self->get_resolution_ratio;
    my $offset = $self->get_offset;
    return ( $x + $offset->{x} ) * $zoom / $ratio,
      ( $y + $offset->{y} ) * $zoom;
}

# convert x, y in widget coords to image coords
sub to_image_coords {
    my ( $self, $x, $y ) = @_;
    my $zoom   = $self->get_zoom;
    my $ratio  = $self->get_resolution_ratio;
    my $offset = $self->get_offset;
    return $x / $zoom * $ratio - $offset->{x}, $y / $zoom - $offset->{y};
}

# convert x, y in widget distance to image distance
sub to_image_distance {
    my ( $self, $x, $y ) = @_;
    my $zoom  = $self->get_zoom;
    my $ratio = $self->get_resolution_ratio;
    return $x / $zoom * $ratio, $y / $zoom;
}

# set zoom with centre in image coordinates
sub _set_zoom_with_center {
    my ( $self, $zoom, $center_x, $center_y ) = @_;
    my $allocation = $self->get_allocation;
    my $ratio      = $self->get_resolution_ratio;
    my $offset_x   = $allocation->{width} / 2 / $zoom * $ratio - $center_x;
    my $offset_y   = $allocation->{height} / 2 / $zoom - $center_y;
    $self->_set_zoom($zoom);
    $self->set_offset( $offset_x, $offset_y );
    return;
}

# sets zoom, centred on the viewport
sub _set_zoom_no_center {
    my ( $self, $zoom ) = @_;
    my $allocation = $self->get_allocation;
    my ( $center_x, $center_y ) =
      $self->to_image_coords( $allocation->{width} / 2,
        $allocation->{height} / 2 );
    $self->_set_zoom_with_center( $zoom, $center_x, $center_y );
    return;
}

sub set_zoom_to_fit {
    my ( $self, $zoom_to_fit ) = @_;
    $self->set( 'zoom-to-fit', $zoom_to_fit );
    if ( not $zoom_to_fit ) { return }
    $self->zoom_to_box( $self->get_pixbuf_size );
    return;
}

sub zoom_to_box {
    my ( $self, $box, $additional_factor ) = @_;
    if ( not defined $box ) { return }
    if ( not defined $box->{x} )          { $box->{x}          = 0 }
    if ( not defined $box->{y} )          { $box->{y}          = 0 }
    if ( not defined $additional_factor ) { $additional_factor = 1 }
    my $allocation  = $self->get_allocation;
    my $ratio       = $self->get_resolution_ratio;
    my $sc_factor_w = $allocation->{width} / $box->{width} * $ratio;
    my $sc_factor_h = $allocation->{height} / $box->{height};
    $self->_set_zoom_with_center(
        min( $sc_factor_w, $sc_factor_h ) * $additional_factor,
        ( $box->{x} + $box->{width} / 2 ) / $ratio,
        $box->{y} + $box->{height} / 2
    );
    return;
}

sub zoom_to_selection {
    my ( $self, $context_factor ) = @_;
    $self->zoom_to_box( $self->get_selection, $context_factor );
    return;
}

sub get_zoom_to_fit {
    my ($self) = @_;
    return $self->get('zoom-to-fit');
}

sub zoom_in {
    my ($self) = @_;
    $self->set_zoom_to_fit(FALSE);
    $self->_set_zoom_no_center( $self->get_zoom * 2 );
    return;
}

sub zoom_out {
    my ($self) = @_;
    $self->set_zoom_to_fit(FALSE);
    $self->_set_zoom_no_center( $self->get_zoom / 2 );
    return;
}

sub zoom_to_fit {
    my ($self) = @_;
    $self->set_zoom_to_fit(TRUE);
    return;
}

sub _clamp_direction {
    my ( $offset, $allocation, $pixbuf_size ) = @_;

    # Centre the image if it is smaller than the widget
    if ( $allocation > $pixbuf_size ) {
        $offset = ( $allocation - $pixbuf_size ) / 2;
    }

    # Otherwise don't allow the LH/top edge of the image to be visible
    elsif ( $offset > 0 ) {
        $offset = 0;
    }

    # Otherwise don't allow the RH/bottom edge of the image to be visible
    elsif ( $offset < $allocation - $pixbuf_size ) {
        $offset = $allocation - $pixbuf_size;
    }
    return $offset;
}

sub set_offset {
    my ( $self, $offset_x, $offset_y ) = @_;
    if ( not defined $self->get_pixbuf ) { return }

    # Convert the widget size to image scale to make the comparisons easier
    my $allocation = $self->get_allocation;
    ( $allocation->{width}, $allocation->{height} ) =
      $self->to_image_distance( $allocation->{width}, $allocation->{height} );
    my $pixbuf_size = $self->get_pixbuf_size;

    $offset_x = _clamp_direction( $offset_x, $allocation->{width},
        $pixbuf_size->{width} );
    $offset_y = _clamp_direction( $offset_y, $allocation->{height},
        $pixbuf_size->{height} );

    $self->set( 'offset', { x => $offset_x, y => $offset_y } );
    return;
}

sub get_offset {
    my ($self) = @_;
    return $self->get('offset');
}

sub get_viewport {
    my ($self)     = @_;
    my $allocation = $self->get_allocation;
    my $pixbuf     = $self->get_pixbuf;
    my ( $x, $y, $w, $h );
    if ( defined $pixbuf ) {
        ( $x, $y, $w, $h ) = (
            $self->to_image_coords( 0, 0 ),
            $self->to_image_distance(
                $allocation->{width}, $allocation->{height}
            )
        );
    }
    else {
        ( $x, $y, $w, $h ) =
          ( 0, 0, $allocation->{width}, $allocation->{height} );
    }
    return { x => $x, y => $y, width => $w, height => $h };
}

sub set_tool {
    my ( $self, $tool ) = @_;
    if ( not( blessed $tool and $tool->isa('Gtk3::ImageView::Tool') ) ) {

        # TODO remove this fallback, only accept Tool directly
        given ($tool) {
            when ('dragger') {
                $tool = Gtk3::ImageView::Tool::Dragger->new($self);
            }
            when ('selector') {
                $tool = Gtk3::ImageView::Tool::Selector->new($self);
            }
            default {
                croak 'invalid set_tool call';
            }
        }
    }
    $self->set( 'tool', $tool );
    return;
}

sub get_tool {
    my ($self) = @_;
    return $self->get('tool');
}

sub set_selection {
    my ( $self, $selection ) = @_;
    my $pixbuf_size = $self->get_pixbuf_size;
    if ( not defined $pixbuf_size ) { return }
    if ( $selection->{x} < 0 ) {
        $selection->{width} += $selection->{x};
        $selection->{x} = 0;
    }
    if ( $selection->{y} < 0 ) {
        $selection->{height} += $selection->{y};
        $selection->{y} = 0;
    }
    if ( $selection->{x} + $selection->{width} > $pixbuf_size->{width} ) {
        $selection->{width} = $pixbuf_size->{width} - $selection->{x};
    }
    if ( $selection->{y} + $selection->{height} > $pixbuf_size->{height} ) {
        $selection->{height} = $pixbuf_size->{height} - $selection->{y};
    }
    $self->set( 'selection', $selection );
    return;
}

sub get_selection {
    my ($self) = @_;
    return $self->get('selection');
}

sub set_resolution_ratio {
    my ( $self, $ratio ) = @_;
    $self->set( 'resolution-ratio', $ratio );
    if ( $self->get_zoom_to_fit ) {
        $self->zoom_to_box( $self->get_pixbuf_size );
    }
    return;
}

sub get_resolution_ratio {
    my ($self) = @_;
    return $self->get('resolution-ratio');
}

sub update_cursor {
    my ( $self, $x, $y ) = @_;
    my $pixbuf_size = $self->get_pixbuf_size;
    if ( not defined $pixbuf_size ) { return }
    my $win    = $self->get_window;
    my $cursor = $self->get_tool->cursor_at_point( $x, $y );
    if ( defined $cursor ) {
        $win->set_cursor($cursor);
    }

    return;
}

1;

__END__

=encoding utf8

=head1 NAME

Gtk3::ImageView - Gtk3 port of the Gtk2::ImageView image viewer widget

=head1 VERSION

1

=head1 SYNOPSIS

 use Gtk3::ImageView;
 Gtk3->init;

 $window = Gtk3::Window->new();

 $view = Gtk3::ImageView->new;
 $view->set_pixbuf($pixbuf, TRUE);
 $window->add($view);

 $window->show_all;

=head1 DESCRIPTION

Gtk3 port of the L<Gtk2::ImageView|Gtk2::ImageView> image viewer widget

To discuss Gtk3::ImageView or gtk3-perl, ask questions and flame/praise the
authors, join gtk-perl-list@gnome.org at lists.gnome.org.

=for readme stop

=head1 SUBROUTINES/METHODS

=head2 $view->set_pixbuf( $pixbuf, $zoom_to_fit )

Defines the image to view. The optional zoom_to_fit parameter specifies whether
to zoom to fit the image or not.

=head2 $view->get_pixbuf

Returns the image currently being viewed.

=head2 $view->get_pixbuf_size

Returns a hash of containing the size of the current image in width and height
keys.

=head2 $view->set_zoom($zoom)

Specifies the zoom level.

=head2 $view->get_zoom

Returns the current zoom level.

=head2 $view->set_zoom_to_fit($zoom_to_fit)

Specifies whether to zoom to fit or not.

=head2 $view->zoom_to_box( $box, $additional_factor )

Specifies a box to zoom to, including an additional zoom factor

=head2 $view->zoom_to_selection($context_factor)

Zooms to the current selection, plus an addition zoom factor. Shortcut for

 $view->zoom_to_box( $view->get_selection, $context_factor );

=head2 $view->get_zoom_to_fit

Returns whether the view is currently zoom to fit or not.

=head2 $view->zoom_in

Doubles the current zoom.

=head2 $view->zoom_out

Halves the current zoom.

=head2 $view->zoom_to_fit

Shortcut for

 $view->set_zoom_to_fit(TRUE);

=head2 $view->set_offset( $x, $y )

Set the current view offset (i.e. pan position).

=head2 $view->set_offset

Returns the current view offset (i.e. pan position).

=head2 $view->get_viewport

Returns a hash containing the position and size of the current viewport.

=head2 $view->set_tool

Set the current tool (i.e. mode) - an object of a subclass of
C<Gtk3::ImageView::Tool>.

Here are some known subclasses of it:

=over 1

=item * C<Gtk3::ImageView::Tool::Dragger> lets drag the image around when zoomed.

=item * C<Gtk3::ImageView::Tool::Selector> lets select a rectangular area with mouse.

=item * C<Gtk3::ImageView::Tool::SelectorDragger> selects or drags with different mouse buttons.

=back

Don't rely too much on how Tool currently interacts with ImageView.

=head2 $view->get_tool

Returns the current tool (i.e. mode).

=head2 $view->set_selection($selection)

Set the current selection as a hash of position and size.

=head2 $view->get_selection

Returns the current selection as a hash of position and size.

=head2 $view->set_resolution_ratio($ratio)

Set the ratio of the resolutions in the x and y directions, allowing images
with non-square pixels to be correctly displayed.

=head2 $view->get_resolution_ratio

Returns the current resolution ratio.

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=head1 INCOMPATIBILITIES

=head2 Porting from L<Gtk2::ImageView|Gtk2::ImageView>

=over 1

=item * C<set_from_pixbuf()> was renamed to C<set_pixbuf()>

=item * C<set_fitting(TRUE)> was renamed to C<zoom_to_fit()>

=item * Drag and drop now can be triggered by subscribing to C<dnd-start> signal, and calling C<$view-E<gt>drag_begin_with_coordinates()> from the handler. C<drag_source_set()> won't work.

=item * C<Gtk2::ImageView::ScrollWin> replacement is not yet implemented

=item * C<set_transp()> is now available through L<CSS|https://developer.gnome.org/gtk3/stable/chap-css-overview.html> instead, e.g. via

 .imageview.transparent {
     background-image: url('checkers.svg');
 }

=back

=head1 BUGS AND LIMITATIONS

This should be rewritten on C, and Perl bindings should be provided via Glib Object Introspection.

=head1 AUTHOR

Jeffrey Ratcliffe, E<lt>jffry@posteo.netE<gt>

Alexey Sokolov E<lt>sokolov@google.comE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2018--2020 by Jeffrey Ratcliffe

Copyright (C) 2020 by Google LLC

Modelled after the GtkImageView C widget by Björn Lindqvist <bjourne@gmail.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.5 or,
at your option, any later version of Perl 5 you may have available.

=cut
