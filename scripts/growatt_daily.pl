#!/usr/bin/perl -w

# Author          : Johan Vromans
# Created On      : Sun Jul 19 16:27:22 2015
# Last Modified By: Johan Vromans
# Last Modified On: Thu Feb 11 17:49:08 2016
# Update Count    : 42
# Status          : Unknown, Use with caution!

################ Common stuff ################

use strict;
use warnings;
use utf8;

# Package name.
my $my_package = 'Growatt WiFi Tools';
# Program name and version.
my ($my_name, $my_version) = qw( growatt_daily 0.02 );

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
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

my @csvfields = ( "Alias / Serial number",
		  qw( Time Status Vpv1(V) Ipv1(A) Ppv1(W) Vpv2(V) Ipv2(A) Ppv2(W) Ppv(W)
		      Vac(R)(V) VacS(V) VacT(V) Iac(R)(A) IacS(A) IacT(A) Fac(Hz)
		      Pac(W) PacR(W) PacS(W) PacT(W) Temperature(℃)
		      Eac_today(kWh) Eac_total(kWh) T_total(H)),
		  "IPM Temperature(℃)", "P BUS Voltage(V)", "N BUS Voltage(V)", "Power Factor",
		  qw( Epv1_today(kWh) Epv1_total(kWh) Epv2_today(kWh) Epv2_total(kWh) Epv_total(kWh)
		      Rac(Var) E_Rac_today(KVarh) E_Rac_total(KVarh) WarnCode ) );

my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';

################ The Process ################

@ARGV = qw( - ) unless @ARGV;
process_file($_) foreach @ARGV;
export_csv();

################ Subroutines ################

use Text::CSV;
use IO::Wrap;
use Fcntl;

my $csv;
my %a;

sub process_file {
    my ( $file ) = @_;

    $csv = Text::CSV->new( { binary => 1,
			     quote_space => 0,
			     always_quote => 0 } );

    open( my $fd, '<:utf8', $file );
    unless ( $fd ) {
	warn("$file: $!\n");
	return;
    }

    my $status;
    scalar(<$fd>);
    while ( <$fd> ) {
	$status = $csv->parse($_);
	warn($file, "[$.]: parse error $status\n"), next unless $status;
	my @columns = $csv->fields;
	warn($file, "[$.]: ", scalar(@columns), " columns (should be 38)\n"), return
	  unless @columns == 38;
	unless ( $columns[1] =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)$/ ) {
	    warn("$file"."[$.]: Invalid time format \"$columns[1]\"\n");
	    next;
	}
	my $date = "$1-$2-$3";
	my $r = $a{$date} || [ $date, ( 999999999, 0 ) x 3 ];
	my $c = $columns[33];
	$r->[1] = $c if $r->[1] > $c;
	$r->[2] = $c if $r->[2] < $c;
	$c = $columns[30];
	$r->[3] = $c if $r->[3] > $c;
	$r->[4] = $c if $r->[4] < $c;
	$c = $columns[32];
	$r->[5] = $c if $r->[5] > $c;
	$r->[6] = $c if $r->[6] < $c;
	$a{$date} = $r;
    }

}


sub export_csv {

    my $status;
    my $csv = Text::CSV->new( { binary => 1,
				quote_space => 0,
				always_quote => 0 } );
    $status = $csv->combine(qw( Time Eac Epv1 Epv2 ) );
    binmode( STDOUT, ':utf8' );
    print $csv->string, "\n";

    my $r;
    foreach ( sort keys %a ) {
	$r = $a{$_};
	$status = $csv->combine( $r->[0] . " 23:59:59",
				 sprintf( "%.2f", $r->[2] - $r->[1] ),
				 sprintf( "%.2f", $r->[4] - $r->[3] ),
				 sprintf( "%.2f", $r->[6] - $r->[5] ) );
	print $csv->string, "\n";
    }

    my ( $y, $m, $d ) = $r->[0] =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/;
    my $days = 30;
    if ( $m == 2 ) {
	$days = ( $y % 4 == 0 ) ? 29 : 28;
    }
    elsif ( $m == 1 || $m == 3 || $m == 5 || $m == 7 ||
	    $m == 8 || $m == 10 || $m == 12 ) {
	$days++;
    }

    while ( ++$d <= $days ) {
	$status = $csv->combine( sprintf("%04d-%02d-%02d 23:59:59",
					 $y, $m, $d),
				 0, 0, 0 );
	print $csv->string, "\n";
    }

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
    --help			this message
    --ident			show identification
    --verbose			verbose information
EndOfUsage
    exit $exit if defined $exit && $exit != 0;
}

