use warnings;
use strict;
use Try::Tiny;
use File::Temp;
use Test::More tests => 2;
use Test::MockObject;
use Test::Deep;
use Carp::Always;

BEGIN {
    use Glib qw/TRUE FALSE/;
    use Gtk3 -init;
    use_ok('Gtk3::ImageView');
}

#########################

my $window = Gtk3::Window->new('toplevel');
$window->set_size_request( 300, 200 );
my $view = Gtk3::ImageView->new;
$window->add($view);
$view->set_tool('selector');
$view->set_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file('t/transp-green.svg'),
    TRUE );
$window->show_all;
$window->hide;

$view->set_zoom(8);
my $event = Test::MockObject->new;
$event->set_always( 'button', 0 );
$event->set_always( 'x',      7 );
$event->set_always( 'y',      5 );
$view->get_tool->button_pressed($event);
$event->set_always( 'x', 93 );
$event->set_always( 'y', 67 );
$view->get_tool->button_released($event);
my $factor = $view->get('scale-factor');

# I don't know why this formula, but it seems to work for scales 1, 2, 3
cmp_deeply(
    $view->get_selection,
    {
        x      => num( 50 - 18 * $factor, 3 ),
        y      => num( 50 - 12 * $factor, 3 ),
        width  => 11 * $factor,
        height => 8 * $factor
    },
    'get_selection'
);
