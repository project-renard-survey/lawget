#!/usr/bin/perl
use strict;
use warnings;

# Our includes.
use WWW::Mechanize;
use File::Path;
use File::Copy;
use Config::JSON;
use YAML qw'LoadFile DumpFile';
use Getopt::Long;
use Term::ReadLine;
use Text::Wrap;
use Term::ReadKey;
use Module::Load;
use Data::Diver qw'DiveRef';
use List::MoreUtils qw(uniq);
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
if (@ARGV > 0) { print "got arguments\n"; exit; }

############################## Command-line Mode ###############################

############################### Interactive Mode ###############################

# Let's give the user some sort of hello message.
system("clear");
print "\nWelcome to lawget.\n\n";
my $banner = "You can download statutory code, administrative code, law reporters, treaties, etc from a number of " .
             "sources. Type 'quit' (without quotes) at any time to exit.";
print wrap('', '', $banner);

# Sending them into the endless polling loop!
while (my ($module, $government_id, $material_type) = menu('United States')) {
    # Load up the module. Should only load once, even if called many times.
    load $module;
    # Configure is running every time, not sure if that's bad or not.
    $module->configure($app_config);

    # A package menu() should return an array of the materials id, the format, and optionally an id and a "type". Some 
    # modules handle many different governments (legal publishers modules, for municipal codes), and even downloading 
    # different sets of materials (codes of ordinances, zoning codes, special programs, charters).
    my ($format, @materials) = $module->menu($government_id, $material_type);
    
    # And where would they like those files downloaded to?
    my $destination = ask_destination($module, $government_id, $material_type);
    # How would they like the files renamed?
    my $rename = ask_rename($module, $government_id, $material_type);
    # What languages do they want this in? If empty, there's only one anyway.
    my @languages = ask_language($module);

    # Let's write out the configs with new defaults.
    DumpFile("config.yaml", $app_config);

    # Some materials only download junk files, that are virtually useless until compiled. Others are usable as is.
    my (@downloaded) = $module->download($destination, $rename, @materials);

    # Depending on the format desired, may need to do some work.
    my @compiled;
    my @ready_files;
    if    ($format ne 'original') {
        # Will need to be compiled to html, regardless of format.
        (@compiled) = $module->download($destination, $rename, @materials);
        if    ($format eq 'html') {
            # The ready files is an identical list to @compiled.
            @ready_files = @compiled;
        }
        elsif ($format eq 'pdf') {
            # Need to convert the html files to pdf. Enter wkhtmltopdf.

        }
    }
    # If original files, no need to recompile. May or may not be on offer.
    else {
        @ready_files = @downloaded;
    }

}

exit;

################################################################################
################################# Subroutines ##################################
################################################################################

sub menu {
    my ($menu_name, $start_letter) = @_;

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

    # Sometimes we don't know what materials exist until we look them up.
    if (exists $menu->{'dynamic_materials'}) {
        my $module = $menu->{'dynamic_materials'};
        # Load up the module that can check what materials are available
        load $module;
        $module->configure($app_config);
        # Grab them
        $module->materials($menu_name, \$menu_config);
    }

    # We need to print the m-heading if it exists (might not early in the tree).
    print $menu->{'m-heading'} . "\n" if exists $menu->{'m-heading'};

    # The hard-coded materials menus...
    my $i = 1;
    foreach my $material (@{$menu->{'materials'}}) {
        if (ref($material) eq "HASH") {
            $options{$i}{'type'} = 'module';
            $options{$i}{'name'} = $material->{'module'};
            $options{$i}{'government'} = $material->{'government'};
            $options{$i}{'government'} = $material->{'government'};
            print "  [$i] " . $material->{'label'} . "\n"; 
        }
        $i++;
    }
    # We need to print the s-heading if it exists.
    print $menu->{'s-heading'} . "\n" if exists $menu->{'s-heading'};

    # Sometimes the list of subdivisions available can be determined dynamically.
    my $module_argument = "";
    $module_argument = $menu->{'argument'} if exists $menu->{'argument'};
    foreach my $module (@{$menu->{'dynamic'}}) {
        load $module;
        $module->configure($app_config);
        $module->subdivisions($module_argument, \$menu_config);
    }

    # If there are more than n subdivisions, we'll want to make this a little easier to browse.
    if (exists $menu->{'subdivisions'} && scalar @{$menu->{'subdivisions'}} > 55 && !$start_letter) {
        #print "the length is ", scalar @{$menu->{'subdivisions'}}, "\n";
        my @alphabet;
        foreach my $label (@{$menu->{'subdivisions'}}) {
            if (ref($label) eq "HASH") { 
                push(@alphabet, substr($label->{'label'}, 0, 1));
            }
            else {
                push(@alphabet, substr($label, 0, 1));
            }
        }
        @alphabet = uniq(@alphabet);
        $i = 10;
        foreach my $letter (@alphabet) {
            $options{$i}{'type'} = 'letter';
            $options{$i}{'id'} = $letter;
            print "  [$i] $letter\n";
            $i++;
        }
    }
    elsif (exists $menu->{'subdivisions'} && scalar @{$menu->{'subdivisions'}} > 55 && $start_letter) {
        # The subdivision menus...
        $i = 10;
        my @slice = grep { substr($_->{'label'}, 0, 1) eq $start_letter } @{$menu->{'subdivisions'}};
        my @sorted_slice = sort {$a->{'label'} cmp $b->{'label'}} @slice;

        foreach my $subdivision (@sorted_slice) {
            # Sometimes we have to have this value be a hash instead of scalar...
            if (ref($subdivision) eq "HASH") { 
                $options{$i}{'type'} = 'menu';
                $options{$i}{'id'} = $subdivision->{'id'};
                print "  [$i] " . $subdivision->{'label'} . "\n";
            }
            else {
                $options{$i}{'type'} = 'menu';
                $options{$i}{'id'} = $subdivision;
                print "  [$i] $subdivision\n";
            }
            $i++;
        }
    }
    elsif (exists $menu->{'subdivisions'}) {
        # The subdivision menus...
        $i = $menu->{'s-start'} if exists $menu->{'s-start'};
        foreach my $subdivision (@{$menu->{'subdivisions'}}) {
            # Sometimes we have to have this value be a hash instead of scalar...
            if (ref($subdivision) eq "HASH") { 
                $options{$i}{'type'} = 'menu';
                $options{$i}{'id'} = $subdivision->{'id'};
                print "  [$i] " . $subdivision->{'label'} . "\n";
            }
            else {
                $options{$i}{'type'} = 'menu';
                $options{$i}{'id'} = $subdivision;
                print "  [$i] $subdivision\n";
            }
            $i++;
        }
    }

    # We'll follow up with a question.
    my $default = $menu->{'default'} || "";
    print "\n" . $menu->{'question'} . " [$default] " if exists $menu->{'question'};

    # Wait for their answer...
    my $selection = <>;
    chomp($selection);

    if    ($selection =~ m/^\s*(quit|q|exit)\s*$/)   { exit; }
    elsif ($selection =~ m/^\s*(top|start)\s*$/)     { menu("World"); }
    elsif ($options{$selection}{'type'} eq 'letter') { menu($menu_name, $options{$selection}->{'id'}); }
    elsif (exists $options{$selection}->{'id'})      { menu($options{$selection}->{'id'}); }
    elsif (exists $options{$selection}->{'name'})    { 
        return ($options{$selection}->{'name'}, $options{$selection}->{'government'}); 
    }
    else { ; }

}

sub ask_destination {
    my ($module, $government_id, $material_type) = @_;

    # If this is for a local government, we can't get the "you_are_here" from module alone.
    my @you_are_here = $module->you_are_here;
    if ($government_id) {
         push(@you_are_here, split(/_/, $government_id), $material_type);
    }

    # Using the module's "you are here", we'll look up the default, if there is one.
    my $default_destination = DiveRef($app_config, (@you_are_here, 'default_destination')) || "";

    print "\nWhere should the materials be saved? [$$default_destination] ";

    # Prompt the user for an answer.
    my ($destination, $mkdir_err);
    do { 
        chomp($destination = <>);
        $destination ||= $$default_destination;
        File::Path::make_path($destination, {error => \$mkdir_err} );
        if (@$mkdir_err) { print "ERROR:   That destination directory can't be created, please try again: "; }
    } until(!@$mkdir_err);

    # Set this as the new default.
    $$default_destination = $destination;

    return($destination);
}

sub ask_rename {
    my ($module, $government_id, $material_type) = @_;

    # If this is for a local government, we can't get the "you_are_here" from module alone.
    my @you_are_here = $module->you_are_here;
    if ($government_id) {
         push(@you_are_here, split(/_/, $government_id), $material_type);
    }

    # Using the module's "you are here", we'll look up the default, if there is one.
    my $default_rename = DiveRef($app_config, (@you_are_here, 'default_rename')) || "";

    print "\nDo you want to rename the materials? [$$default_rename] ";

    my ($rename);
    chomp($rename = <>);
    $rename ||= $$default_rename;
    my $fn = eval "sprintf($rename)";
    # Is there any way to check that their sprintf expression is good? If we wait, we can't warn,
    # will just have to fail out.

    # Make this the new default.
    $$default_rename = $rename;

    return($rename);
}

sub ask_language {
    my ($module) = @_;

    my @languages = $module->languages;

    my @final_languages;

    # If there's only one language, no need to ask.
    if (scalar @languages > 1) {
        print "\nThis material is available in multiple languages: ", join(" ", @languages), "\n";
        
        # We'll keep asking until we get a sensible answer.
        LANGUAGES_LOOP: while(1) {
            print "Which do you want to download? [all]";
            my $chosen_languages;
            chomp($chosen_languages = <>);
            $chosen_languages ||= 'all';

            my @answer = split(/(,| )/, $chosen_languages);
            foreach my $answerpart (@answer) {
                if ($answerpart ~~ @languages) {
                    push(@final_languages, $answerpart);
                }
                elsif ($answerpart eq 'all') {
                    @final_languages = @languages;
                    last;
                }
                elsif ($answerpart =~ m/^(q|quit|exit)$/) {
                    exit;
                }
                else {
                    print "ERROR:   That option ($answerpart) is unavailable.\n";
                    undef(@final_languages);
                    next LANGUAGES_LOOP;
                }
            }
            # If we got through the forloop, then all the answers are good, we can kill this.
            last;
        }
        return(@final_languages);
    }
}

################################################################################
################################################################################
################################################################################
