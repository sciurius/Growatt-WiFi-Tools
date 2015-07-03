#!/usr/bin/perl -w

# Author          : Johan Vromans
# Created On      : Thu Jul  2 14:37:37 2015
# Last Modified By: Johan Vromans
# Last Modified On: Fri Jul  3 21:43:09 2015
# Update Count    : 102
# Status          : Unknown, Use with caution!

################ Common stuff ################

use strict;

# Package name.
my $my_package = 'Growatt WiFi Tools';
# Program name and version.
my ($my_name, $my_version) = qw( growatt_data 0.01 );

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
my $gwversion = 3;		# Growatt WiFi module version
my $print = 1;			# default: print report
my $plot = 0;			# generate gnuplot data
my $verbose = 0;		# verbose processing

# Development options (not shown with -help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test = 0;			# test mode.

# Process command line options.
app_options();

# Post-processing.
$trace |= ($debug || $test);

################ Presets ################

my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';

################ The Process ################

@ARGV = qw( - ) unless @ARGV;
process_file($_) foreach @ARGV;

################ Subroutines ################

use Fcntl;

sub process_file {
    my ( $file ) = @_;

    unless ( -s $file > 200 ) {
	warn("$file: too small -- ignored\n");
	return;
    }

    # Extract timestamp from filename, if possible.
    my $sample_time = "---";
    my $sample_date = "---";
    if ( $file && $file =~ m;(?:^|/)(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)\.; ) {
	$sample_date = "$3-$2-$1";
	$sample_time = "$4:$5:$6";
    }

    my $data;

    # Read data from file...
    if ( $file && $file ne '-' ) {
	sysopen( my $fd, $file, O_RDONLY )
	  or do { warn( "$file: $!\n" ); return };
	sysread( $fd, $data, 10240 );
	close($fd);
    }
    # ... or standard input.
    else {
	$data = do { local $/; <STDIN> };
    }

    # If the data is a hex representation, make binary.
    unless ( $data =~ /^\x00\x01/ ) {
	$data =~ s/^  [0-9a-f]{4}: //mg;
	$data =~ s/  .*$//mg;
	$data =~ s/\s//g;
	$data = pack("H*", $data);
    }

    unless ( length($data) > 200 ) {
	warn("$file: too small -- ignored\n");
	return;
    }

    # Disassemble.
    my $a = disassemble( $data );
    unless ( $a ) {
	warn("$file\n");
	return;
    }
    $a->{SampleDate} = $sample_date;
    $a->{SampleTime} = $sample_time;

    # Print (for now).
    print_data($a) if $print;
    plot_data($a)  if $plot;
}

use Data::Hexify;

sub disassemble {
    my ( $data ) = @_;
    my $off = 0;

    # Mote common case for unpacking data.
    my $up = sub {
	my ( $len, $scale ) = @_;
	my $val = up( $data, $off, $len, $scale );
	$off += $len;
	return $val;
    };

    # All data messages start with 00 01 00 02 ll ll 01 04.
    unless ( $up->(2) == 0x0001
	     and
	     $up->(2) == 0x0002
	     and
	     $up->(2) == length($data) - 6
	     and
	     $up->(2) == 0x0104 ) {
	warn("Invalid data package\n");
	warn(Hexify(\$data),"\n");
	return;
    }

    my %a;

    $a{DataLoggerId} = substr($data, $off, 10); $off += 10;
    $a{InverterId}   = substr($data, $off, 10); $off += 10;

    $off += 5;
    $off += 6 if $gwversion >= 2;	# for V2.0.0.0 and up
    my $off0 = $off - 15;		# for assertion

    $a{InvStat} = $up->(2);
    $a{InvStattxt} = (qw( waiting normal fault ))[$a{InvStat}];
    $a{Ppv} = $up->(4, 1);
    $a{Vpv1} = $up->(2, 1);
    $a{Ipv1} = $up->(2, 1);
    $a{Ppv1} = $up->(4, 1);
    $a{Vpv2} = $up->(2, 1);
    $a{Ipv2} = $up->(2, 1);
    $a{Ppv2} = $up->(4, 1);
    $a{Pac} = $up->(4, 1);
    $a{Fac} = sprintf("%.2f", up($data, $off, 2)/100 ); $off += 2;
    $a{Vac1} = $up->(2, 1);
    $a{Iac1} = $up->(2, 1);
    $a{Pac1} = $up->(4, 1);
    $a{Vac2} = $up->(2, 1);
    $a{Iac2} = $up->(2, 1);
    $a{Pac2} = $up->(4, 1);
    $a{Vac3} = $up->(2, 1);
    $a{Iac3} = $up->(2, 1);
    $a{Pac3} = $up->(4, 1);
    $a{E_Today} = $up->(4) * 100;
    $a{E_Todayk} = sprintf("%.2f", $a{E_Today} / 1000);
    $a{E_Total} = $up->(4, 1);
    $a{Tall} = $up->(4);
    $a{TallH} = sprintf("%.2f", $a{Tall}/(60*60*2));
    $a{Tmp} = $up->(2, 1);
    $a{ISOF} = $up->(2, 1);
    $a{GFCIF} = sprintf("%.2f", up($data, $off, 2)/10 ); $off += 2;
    $a{DCIF} = sprintf("%.2f", up($data, $off, 2)/10 ); $off += 2;
    $a{Vpvfault} = $up->(2, 1);
    $a{Vacfault} = $up->(2, 1);
    $a{Facfault} = sprintf("%.2f", up($data, $off, 2)/100 ); $off += 2;
    $a{Tmpfault} = $up->(2, 1);
    $a{Faultcode} = sprintf("0x%02X", $up->(2));
    $a{IPMtemp} = $up->(2, 1);
    $a{Pbusvolt} = $up->(2, 1);
    $a{Nbusvolt} = $up->(2, 1);

    # Assertion.
    warn("offset = ", $off-$off0, ", should be 103\n")
      unless $off-$off0 == 103;
    $off += 12;

    $a{Epv1today} = sprintf("%.2f", up($data, $off, 4)/10 ); $off += 4;
    $a{Epv1total} = sprintf("%.2f", up($data, $off, 4)/10 ); $off += 4;
    $a{Epv2today} = sprintf("%.2f", up($data, $off, 4)/10 ); $off += 4;
    $a{Epv2total} = sprintf("%.2f", up($data, $off, 4)/10 ); $off += 4;
    $a{Epvtotal} = sprintf("%.2f", up($data, $off, 4)/10 ); $off += 4;
    $a{Rac} = sprintf("%.2f", up($data, $off, 4)*100 ); $off += 4;
    $a{ERactoday} = sprintf("%.2f", up($data, $off, 4)*100 ); $off += 4;
    $a{ERactotal} = sprintf("%.2f", up($data, $off, 4)*100 ); $off += 4;

    return \%a;
}

sub plot_data {
    my ( $a ) = @_;
    my %a = %$a;
    printf( "\"%s %s\" %.1f %.1f %.1f %.1f\n",
	    $a{SampleDate}, $a{SampleTime},
	    $a{Ppv}, $a{Ipv1}, $a{Ipv2}, $a{Tmp} );
}

sub print_data {
    my ( $a ) = @_;
    my %a = %$a;

    printf( "Growatt Inverter serial   : %-20s", $a{InverterId} );
    printf( "      Capture sample date : %s\n", $a{SampleDate} );
    printf( "Growatt Wifi Module serial: %-20s", $a{DataLoggerId} );
    printf( "      Capture sample time : %s\n", $a{SampleTime} );
    printf( "Growatt Inverter status   : %-20s", "$a{InvStat} ($a{InvStattxt})" );
    printf( "      Growatt temperature : %6.1f C\n", $a{Tmp} );
    print( "-" x 87, "\n" );

    printf( "%-11s %8.1f %-10s",   "E_Today",     $a{E_Todayk},  "kWh" );
    printf( "%-11s %8.1f %-10s",   "E_Total",     $a{E_Total},   "kWh" );
    printf( "%-11s %8.1f %-10s\n", "Total time",  $a{TallH},     "hrs" );
    print( "-" x 87, "\n" );

    printf( "%-11s %8.1f %-10s",   "Ppv",         $a{Ppv},       " W" );
    printf( "%-11s %8.1f %-10s",   "Pac",         $a{Pac},       " W" );
    printf( "%-11s %8.2f %-10s\n", "Fac",         $a{Fac},       "Hz" );
    print( "-" x 87, "\n" );

    printf( "%-11s %8.1f %-10s",   "Vpv1",        $a{Vpv1},      " V" );
    printf( "%-11s %8.1f %-10s\n", "Vpv2",        $a{Vpv2},      " V" );
    printf( "%-11s %8.1f %-10s",   "Ipv1",        $a{Ipv1},      " A" );
    printf( "%-11s %8.1f %-10s\n", "Ipv2",        $a{Ipv2},      " A" );
    printf( "%-11s %8.1f %-10s",   "Ppv1",        $a{Ppv1},      " W" );
    printf( "%-11s %8.1f %-10s\n", "Ppv2",        $a{Ppv2},      " W" );
    print( "-" x 87, "\n" );

    printf( "%-11s %8.1f %-10s",   "Vac1",        $a{Vac1},      " V" );
    printf( "%-11s %8.1f %-10s",   "Vac2",        $a{Vac2},      " V" );
    printf( "%-11s %8.1f %-10s\n", "Vac3",        $a{Vac3},      " V" );
    printf( "%-11s %8.1f %-10s",   "Iac1",        $a{Iac1},      " A" );
    printf( "%-11s %8.1f %-10s",   "Iac2",        $a{Iac2},      " A" );
    printf( "%-11s %8.1f %-10s\n", "Iac2",        $a{Iac3},      " A" );
    printf( "%-11s %8.1f %-10s",   "Pac1",        $a{Pac1},      " W" );
    printf( "%-11s %8.1f %-10s",   "Pac2",        $a{Pac2},      " W" );
    printf( "%-11s %8.1f %-10s\n", "Pac2",        $a{Pac3},      " W" );
    print( "-" x 87, "\n" );

    printf( "%-11s %8.1f %-10s\n", "Epvtotal",    $a{Epvtotal},  "kW" );
    printf( "%-11s %8.1f %-10s",   "Epv1today",   $a{Epv1today}, "kW" );
    printf( "%-11s %8.1f %-10s\n", "Epv2today",   $a{Epv2today}, "kW" );
    printf( "%-11s %8.1f %-10s",   "Epv1total",   $a{Epv1total}, "kW" );
    printf( "%-11s %8.1f %-10s\n", "Epv2total",   $a{Epv2total}, "kW" );
    print( "-" x 87, "\n" );

    printf( "%-11s %8.1f %-10s",   "ISO Fault",   $a{ISOF},      " V" );
    printf( "%-11s %8.1f %-10s",   "Vpvfault",    $a{Vpvfault},  " V" );
    printf( "%-11s %8.1f %-10s\n", "Tempfault",   $a{Tmpfault},  " C" );
    printf( "%-11s %8.1f %-10s",   "GFCI Fault",  $a{GFCIF},     "mA" );
    printf( "%-11s %8.1f %-10s",   "Vacfault",    $a{Vacfault},  " V" );
    printf( "%-11s %8s\n",         "Faultcode",   $a{Faultcode}      );
    printf( "%-11s %8.1f %-10s",   "DCI Fault",   $a{DCIF},      " A" );
    printf( "%-11s %9.2f %-10s\n", "Facfault",    $a{Facfault},  "Hz" );
    print( "-" x 87, "\n" );

    printf( "%-11s %8.1f %-10s",   "IPMtemp",     $a{IPMtemp},   " C" );
    printf( "%-11s %8.1f %-10s\n", "Rac",         $a{Rac},       "Var" );
    printf( "%-11s %8.1f %-10s",   "Pbusvolt",    $a{Pbusvolt},  " V" );
    printf( "%-11s %8.1f %-10s\n", "E_Rac_today", $a{ERactoday}, "Var" );
    printf( "%-11s %8.1f %-10s",   "Nbusvolt",    $a{Nbusvolt},  " V" );
    printf( "%-11s %8.1f %-10s\n", "E_Rac_total", $a{ERactotal}, "Var" );
    print( "-" x 87, "\n" );

}

# Unpack 2 or 4 bytes unsigned data, optionally scaling it.
sub up {
    my ( $data, $offset, $len, $scale ) = ( @_, 0 );
    my $v = unpack( $len == 2 ? "n" : "N",
		    substr( $data, $offset, $len ) );
    if ( $scale ) {
	return sprintf("%.${scale}f", $v/(10**$scale));
    }
    return $v;
}

exit 0;

################ Subroutines ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally

    # Process options, if any.
    # Make sure defaults are set before returning!
    return unless @ARGV > 0;

    if ( !GetOptions(
		     'version=i' => \$gwversion,
		     'print!'	=> sub { $print = $_[1]; $plot = 0 },
		     'plot!'	=> sub { $plot = $_[1]; $print = 0 },
		     'ident'	=> \$ident,
		     'verbose'	=> \$verbose,
		     'trace'	=> \$trace,
		     'help|?'	=> \$help,
		     'debug'	=> \$debug,
		    ) or $help )
    {
	app_usage(2);
    }
    app_ident() if $ident;
}

sub app_ident {
    print STDERR ("This is $my_package [$my_name $my_version]\n");
}

sub app_usage {
    my ($exit) = @_;
    app_ident();
    print STDERR <<EndOfUsage;
Usage: $0 [options] [file ...]
    --version=NN		Growatt Wifi module version, default 3.
    --[no]print			generate printed report (default)
    --[no]plot			generate gnuplot data (experimental)
    --help			this message
    --ident			show identification
    --verbose			verbose information
EndOfUsage
    exit $exit if defined $exit && $exit != 0;
}
