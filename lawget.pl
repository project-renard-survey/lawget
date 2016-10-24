#!/usr/bin/perl
use strict;
use warnings;

# Our includes.
use WWW::Mechanize;
use File::Path;
use Config::JSON;
use YAML qw'LoadFile';
use Getopt::Long;
use Text::Wrap;
use Term::ReadKey;
use Module::Load;
use Data::Dumper;

# We have some custom modules for this project that don't really belong on CPAN or in the standard locations.
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lawget/lib';

# Turn off the smartmatch warning.
no warnings 'experimental::smartmatch';

# Set the text wrap up...
my ($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();
$Text::Wrap::columns = $wchar;

# Load up the config file.
my $app_config = LoadFile("config.yaml");
# Load up the menu file (don't want to do it in menu(), just bad.)
my $menu_config = LoadFile("menu.yaml");

# Check for options. If none, assume interactive mode.

# Let's give the user some sort of hello message.
print "\nWelcome to lawget.\n\n";
my $banner = "You can download statutory code, administrative code, law reporters, treaties, etc from a number of " .
             "sources. Type 'quit' (without quotes) at any time to exit.";
print wrap('', '', $banner);


# Sending them into the endless polling loop!
while (my $module = menu('United States')) {
    # Load up the module. Should only load once, even if called many times.
    load $module;
    # Configure is running every time, not sure if that's bad or not.
    $module->configure($app_config);

    # We need to call the module's menu() method, and generate a menu from it.
    my ($materials) = $module->menu();
}
exit;




#US::Texas::TAC::download('http://texreg.sos.state.tx.us/public/readtac$ext.viewtac', (1));
US::Texas::TAC::download((1));
US::Texas::TAC::compile((1));


################################################################################
################################# Subroutines ##################################
################################################################################

sub menu {
    my ($menu_name) = @_;

    # Let's make sure this is always passed a menu name.
    if (!exists $menu_config->{$menu_name}) {
        print "\nWARNING: The menu.yaml file may be broken, returning to the top.\n";
        menu("World");
    }

    # This file was passed a label of the menu object to retrieve.
    my $menu = $menu_config->{$menu_name};

    # Let's just keep track of which index is which here.
    my %options;

    # Let's do a newline. Just because.
    print "\n";

    # We need to print the m-heading if it exists (might not early in the tree).
    print $menu->{'m-heading'} . "\n" if exists $menu->{'m-heading'};
    # The materials menus...
    my $a = 1;
    foreach my $material (@{$menu->{'materials'}}) {
        if (ref($material) eq "HASH") {
            $options{$a}{'type'} = 'module';
            $options{$a}{'name'} = $material->{'module'};
            print "  [$a] " . $material->{'label'} . "\n"; 
        }
        $a++;
    }
    # We need to print the s-heading if it exists.
    print $menu->{'s-heading'} . "\n" if exists $menu->{'s-heading'};
    # The materials menus...
    $a = $menu->{'s-start'} if exists $menu->{'s-start'};
    foreach my $subdivision (@{$menu->{'subdivisions'}}) {
        # Sometimes we have to have this value be a hash instead of scalar...
        if (ref($subdivision) eq "HASH") { 
            $options{$a}{'type'} = 'menu';
            $options{$a}{'id'} = $subdivision->{'id'};
            print "  [$a] " . $subdivision->{'label'} . "\n";
        }
        else {
            $options{$a}{'type'} = 'menu';
            $options{$a}{'id'} = $subdivision;
            print "  [$a] $subdivision\n";
        }
        $a++;
    }

    # We'll follow up with a question.
    my $default = $menu->{'default'} || "";
    print "\n" . $menu->{'question'} . " [$default] " if exists $menu->{'question'};

    # Wait for their answer...
    my $selection = <>;
    chomp($selection);

    if    ($selection ~~ ["quit", "q", "exit"])   { exit; }
    elsif ($selection ~~ ["top", "start"])        { menu("World"); }
    elsif (exists $options{$selection}->{'id'})   { menu($options{$selection}->{'id'}); }
    elsif (exists $options{$selection}->{'name'}) { return $options{$selection}->{'name'}; }
    else { ; }

}

################################################################################
################################################################################
################################################################################
