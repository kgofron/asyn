#!/usr/bin/perl
#
# Tool to create a new Asyn support area below the current directory
#
# Author: Andrew Johnson <anj@aps.anl.gov>
# Date: 17 May 2004
#
# $Id: makeSupport.pl,v 1.1 2004-05-20 20:28:26 anj Exp $
#

use strict;
use Getopt::Std;
use Cwd qw(cwd abs_path);


our ($opt_A, $opt_B, $opt_d, $opt_h, $opt_l, $opt_t, $opt_T);
Usage() unless getopts('A:B:dhlt:T:');

# Handle the -h command
Usage() if $opt_h;

my $top = cwd();
print "\$top = $top\n" if $opt_d;

my $arch = $ENV{EPICS_HOST_ARCH};
print "\$arch = $arch\n" if $opt_d;

my $user = $ENV{USER} ||
	   $ENV{USERNAME} ||
	   Win32::LoginName()
    or die "Can't determine your username!\n";
print "\$user = $user\n" if $opt_d;

my $date = localtime;
print "\$date = $date\n" if $opt_d;

# Find asyn directory
my $asyn;
if ($opt_A) {
    $asyn = abs_path($opt_A);
} else {
    # Work it out from this script's pathname
    my @asyn = split /[\/]/, $0;
    warn "expected 'makeSupport.pl', got '$_'\n"
        unless 'makeSupport.pl' eq ($_ = pop @asyn);
    warn "expected 'expected $arch', got '$_'\n"
        unless $arch eq ($_ = pop @asyn);
    warn "expected 'bin', got '$_'\n"
        unless 'bin' eq ($_ = pop @asyn);
    $asyn = abs_path(join "/", @asyn);
}
print "\$asyn = $asyn\n" if $opt_d;
die "ASYN directory '$asyn' not found!\n"
    unless -d $asyn;
die "ASYN ($asyn) is missing a configure/RELEASE file!\n"
    unless -f "$asyn/configure/RELEASE";

# Find templates directory
my $templates = abs_path($opt_T ||
			 $ENV{EPICS_ASYN_TEMPLATE_DIR} ||
			 "$asyn/templates");
print "\$templates = $templates\n" if $opt_d;
die "Templates directory '$templates' does not exist\n"
    unless -d $templates;

# Check the template type
my $type = $opt_t ||
	   $ENV{EPICS_ASYN_TEMPLATE_DEFAULT} ||
	   'default';
print "\$type = $type\n" if $opt_d;
print "The template '$type' does not exist.\n"
    unless $opt_l or -d "$templates/$type";

# Handle the -l command or bad template type
if ($opt_l or ! -d "$templates/$type") {
    opendir TEMPLATES, $templates or die "opendir failed: $!";
    my @templates = readdir TEMPLATES;
    closedir TEMPLATES;
    print "Templates available are:\n";
    foreach (@templates) {
	next if m/^\./;
	next if m/^CVS$/;   # Shouldn't be necessary, but...
	print "\t$_\n";
    }
    exit ! $opt_l;
}

# Check app name
my $name = shift or die "You didn't name your application!\n";
print "\$name = $name\n" if $opt_d;

# Find EPICS_BASE
my $base;
if ($opt_B) {
    $base = abs_path($opt_B);
} else {
    my %release = (TOP => $top);
    my @apps = ('TOP');
    readRelease("$asyn/configure/RELEASE", \%release, \@apps);
    expandRelease(\%release);
    $base = abs_path($release{EPICS_BASE});
}
print "\$base = $base\n" if $opt_d;
die "EPICS_BASE directory '$base' does not exist\n"
    unless -d $base;

# Substitutions work like this:
# key => val  in the hash causes  _key_ in the templateto become by val

# Substitutions in filenames
my %namesubs = (
    NAME => $name
);

# Substitutions in file text
my %textsubs = (
    NAME => $name,
    ASYN => $asyn,
    EPICSBASE => $base,
    TOP  => $top,
    TYPE => $type,
    USER => $user,
    DATE => $date
);

# Do it!
copyTree("$templates/$type", $top, \%namesubs, \%textsubs);

##### File contains subroutines only below here

sub Usage {
    print <<EOF;
Usage:
    makeSupport.pl -h
	Display help on command options
    makeSupport.pl -l [l-opts]
	List available template types
    makeSupport.pl -t type [t-opts] support
	Create tree for device 'support' from template 'type'
EOF
    print <<EOF if ($opt_h);

    where
	[l-opts] may be one of:
	    -T /path/to/templates
	    -A /path/to/asyn
	[t-opts] are any of:
	    -A /path/to/asyn
	    -B /path/to/base
	    -T /path/to/templates

Example:
    mkdir Keithley196
    cd Keithley196
    <asyn>/bin/<arch>/makeSupport.pl -t devGpib K196
EOF
    exit $opt_h ? 0 : 1;
}

#
# Parse a configure/RELEASE file.
#
# NB: This subroutine is taken from base/configure/tools/convertRelease.pl
#
sub readRelease {
    my ($file, $Rmacros, $Rapps) = @_;
    # $Rmacros is a reference to a hash, $Rapps a ref to an array
    
    local *IN;
    open(IN, $file) or die "Can't open $file: $!\n";
    while (<IN>) {
	chomp;
	s/\r$//;		# Shouldn't need this, but sometimes...
	s/\s*#.*$//;		# Remove trailing comments
	next if m/^\s*$/;	# Skip blank lines
	
	# Expand all already-defined macros in the line:
	while (my ($pre,$var,$post) = m/(.*)\$\((\w+)\)(.*)/) {
	    last unless exists $Rmacros->{$var};
	    $_ = $pre . $Rmacros->{$var} . $post;
	}
	
	# Handle "<macro> = <path>"
	my ($macro, $path) = m/^\s*(\w+)\s*=\s*(.*)/;
	if ($macro ne "") {
	    $Rmacros->{$macro} = $path;
	    push @$Rapps, $macro;
	    next;
	}
	# Handle "include <path>" syntax
	($path) = m/^\s*include\s+(.*)/;
	&readRelease($path, $Rmacros, $Rapps) if (-r $path);
    }
    close IN;
}

sub expandRelease {
    my ($Rmacros) = @_;
    # $Rmacros is a reference to a hash
    
    # Expand any (possibly nested) macros that were defined after use
    while (my ($macro, $path) = each %$Rmacros) {
	while (my ($pre,$var,$post) = $path =~ m/(.*)\$\((\w+?)\)(.*)/) {
	    $path = $pre . $Rmacros->{$var} . $post;
	    $Rmacros->{$macro} = $path;
	}
    }
}

sub copyTree {
    my ($src, $dst, $Rnamesubs, $Rtextsubs) = @_;
    # $Rnamesubs contains substitutions for file names,
    # $Rtextsubs contains substitutions for file content.
    
    opendir FILES, $src or die "opendir failed while copying $src: $!\n";
    my @entries = readdir FILES;
    closedir FILES;
    
    foreach (@entries) {
	next if m/^\.\.?$/;  # ignore . and ..
	next if m/^CVS$/;   # Shouldn't exist, but...
	
	my $srcName = "$src/$_";
	
	# Substitute any _VARS_ in the name
	s/_(\w+?)_/$Rnamesubs->{$1} || "_$1_"/eg;
	my $dstName = "$dst/$_";
	
	if (-d $srcName) {
	    copyDir($srcName, $dstName, $Rnamesubs, $Rtextsubs);
	} elsif (-f $srcName) {
	    copyFile($srcName, $dstName, $Rtextsubs);
	} elsif (-l $srcName) {
	    print "Soft link in template, ignored:\n\t$srcName\n";
	} else {
	    print "Unknown file type in template, ignored:\n\t$srcName\n";
	}
    }
}

sub copyFile {
    my ($src, $dst, $Rtextsubs) = @_;
    if (-e $dst) {
	print "Target file exists, skipping:\n\t$dst\n";
	return;
    }
    print "Creating file '$dst'\n" if $opt_d;
    open(SRC, "<$src") and open(DST, ">$dst") or die "$! copying $src to $dst\n";
    while (<SRC>) {
	# Substitute any _VARS_ in the text
	s/_(\w+?)_/$Rtextsubs->{$1} || "_$1_"/eg;
	print DST;
    }
    close DST;
    close SRC;
}

sub copyDir {
    my ($src, $dst, $Rnamesubs, $Rtextsubs) = @_;
    if (-e $dst && ! -d $dst) {
	print "Target exists but is not a directory, skipping:\n\t$dst\n";
	return;
    }
    print "Creating directory '$dst'\n" if $opt_d;
    mkdir $dst, 0777 or die "Can't create $dst: $!\n"
	unless -d $dst;
    copyTree($src, $dst, $Rnamesubs, $Rtextsubs);
}
