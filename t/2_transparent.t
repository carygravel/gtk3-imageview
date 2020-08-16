use warnings;
use strict;
use File::Temp;
use Image::Magick;
use Test::More tests => 3;

BEGIN {
    use Glib qw/TRUE FALSE/;
    use Gtk3 -init;
    use_ok('Gtk3::ImageView');
}

my $window             = Gtk3::Window->new('toplevel');
my $css_provider_alpha = Gtk3::CssProvider->new;
Gtk3::StyleContext::add_provider_for_screen( $window->get_screen,
    $css_provider_alpha, 0 );
$css_provider_alpha->load_from_data( "
    .imageview.transparent {
        background-color: #ff0000;
    }
" );
my $view = Gtk3::ImageView->new;
$view->set_pixbuf( Gtk3::Gdk::Pixbuf->new_from_file('t/transp-green.svg'),
    TRUE );
$window->add($view);
$window->show_all;
my $tmp = File::Temp->new( SUFFIX => '.png' );
Glib::Timeout->add(
    1000,
    sub {
        system("import -window 2_transparent.t $tmp");
        Gtk3::main_quit;
        return FALSE;
    }
);
Gtk3::main;

my $image = Image::Magick->new;
$image->Read("$tmp");
my $x      = $image->Get('width') / 2;
my $y      = $image->Get('height') / 2;
my @middle = $image->GetPixel( x => $x, y => $y );
is_deeply( \@middle, [ 0, 1, 0 ], 'middle pixel should be green' );

my $found = 0;
while ( $x > 0 ) {
    my @pixel = $image->GetPixel( x => $x, y => $y );
    if ( join( ',', @pixel ) eq '1,0,0' ) {
        $found = 1;
    }
    $x--;
}
is( $found, 1, 'there is red background' );
