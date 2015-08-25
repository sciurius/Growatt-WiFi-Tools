#!/usr/bin/perl
#
# Author          : Johan Vromans
# Created On      : Tue Aug 25 11:29:56 2015
# Last Modified By: Johan Vromans
# Last Modified On: Tue Aug 25 14:00:52 2015
# Update Count    : 247
# Status          : Unknown, Use with caution!
#
################################################################
#
# Simple standalone server for Growatt WiFi.
#
# The Growatt WiFi module communicates with the Growatt server
# (server.growatt.com, port 5279). This server can be used
# as a standalone replacement to intercept all traffic.
#
# Data packages that contain energy data from the data logger are
# written to disk in separate files for later processing.
#
# Usage:
#
# The server should be run using systemd (per connection server) or xinetd.
#
# For systemd, install the supplied growattserver.socket and
# growattserver@.service files into /etc/systemd/system .
# Adjust growattserver@.service to reflect the actual location of the
# server script, and the location where the data should be collected.
#
# Start the service (as super user):
#
#  systemctl start growattserver.socket
#
# Using telnet, connect to port 5279. You can type commands "ping",
# "ahoy", "data" and "quit". Most commands will return garbage, but
# the string "AH12345678" should be recognizable. "quit" will
# terminate the server.
#
# In the directory configured in growattserver@.service you will find
# a log file with name YYYYMMDD.log, containing a report of all
# traffic. In this directory you will also find data files with name
# YYYYMMDDHHMMSS.dat, for every "data" command that you typed in.
#
# Using the Growatt WiFi module administrative interface, go to the
# "STA Interface Setting" and change "Server Address" (default:
# server.growatt.com) to the name or ip of the system running the
# server.
# Reboot the WiFi module and re-visit the "STA Interface Setting" page
# to verify that the "Server Connection State" is "Connected".
#
# If all went well, you'll see messages flowing between the WiFi
# module and the server, and energy data files will start appearing in
# the server directory:
#
# 20150703135901.dat
# 20150703140004.dat
# ... and so on ...
#
# If you're satisfied, you can remove the "--debug" option in
# growattserver@.service to reduce the log messages. And do not forget
# to enable growattserver.socket using systemctl so it will be
# activated automatically upon reboot.
#
################################################################

use warnings;
use strict;

################ Common stuff ################

use strict;

# Package name.
my $my_package = 'Growatt WiFi Tools';
# Program name and version.
my ($my_name, $my_version) = qw( growatt_simple 0.03 );

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

################ The Process ################

use IO::Socket::INET;
use IO::Select;
use IO::Handle;
use Fcntl;
use Data::Hexify;

my $local_port  = 5279;		# local port. DO NOT CHANGE
my $timeout = 300;		# 5 minutes

$debug = 1;			# for the time being
$| = 1;				# flush standard output

my @tm = localtime(time);

open( STDERR, '>>',
      sprintf( "%04d%02d%02d.log", 1900+$tm[5], 1+$tm[4], $tm[3] ) );
print STDERR ( ts(), " Starting Growatt server version $my_version\n\n" );

my $ioset = IO::Select->new;
STDIN->blocking(0);
$ioset->add(\*STDIN);

my $s_timeout;

while ( 1 ) {
    my @sockets = $ioset->can_read($timeout);
    $s_timeout ||= !@sockets;
    if ( $s_timeout ) {
	print STDERR ( "==== ", ts(), " TIMEOUT ====\n\n" );
	last;
    }

    my $buffer = "";
    my $len = sysread( $sockets[0], $buffer, 4096);
    if ( $len ) {
	$buffer = preprocess_msg($buffer);
	while ( my $msg = split_msg( \$buffer ) ) {
	    process_msg($msg);
	}
    }
    else {
	last;
    }
}

print STDERR ( ts(), " Server terminating\n" );
exit 0;

################ Subroutines ################

sub ts {
    my @tm = localtime(time);
    sprintf( "%04d-%02d-%02d %02d:%02d:%02d",
	     1900 + $tm[5], 1+$tm[4], @tm[3,2,1,0] );
}

sub trace {
    return unless $trace;
    print STDERR ( @_ );
}

my $data_logger;

sub split_msg {
    my ( $bufref ) = @_;

    # Theoretically, a single read may yield more than one message.

    if ( $$bufref =~ /^\x00\x01\x00\x02(..)/ ) {
	my $length = unpack( "n", $1 );
	return substr( $$bufref, 0, $length+6, '' );
    }
    return;
}

sub process_msg {
    my ( $msg ) = @_;

    # Processes a message.

    my $ts = ts();

    # 0x0116 -> PING.
    if ( $msg =~ /^\x00\x01\x00\x02..\x01\x16(.{10})/ ) {

	# Just echo it.

	$data_logger = $1;
	trace( "==== $ts client PING ====\n\n" );
	trace( "==== $ts server PING ====\n\n" );
	syswrite( STDOUT, $msg );
	return;
    }

    # 0x0103 -> AHOY.
    if ( $msg =~ /^\x00\x01\x00\x02..\x01\x03..../ ) {

	# Just ACK it.

	trace( "==== $ts client AHOY ====\n", Hexify(\$msg), "\n" );
	trace( "==== $ts server ACK 0103 ====\n\n" );
	syswrite( STDOUT, m_ack(0x0103) );
	return;
    }

    # 0x0104 -> DATA.
    if ( $msg =~ /^\x00\x01\x00\x02..\x01\x04..../ ) {

	# Dump energy reports to individual files.

	trace( "==== $ts client DATA ====\n", Hexify(\$msg), "\n" );
	my $tag = "server";

	my $fn = $ts;
	$fn =~ s/[- :]//g;
	$fn .= ".dat";
	$tag .= " DATA";

	my $fd;

	if ( sysopen( $fd, $fn, O_WRONLY|O_CREAT )
	     and syswrite( $fd, $msg ) == length($msg)
	     and close($fd) ) {
	    # OK
	}
	else {
	    print STDERR ( "==== $ts server ERROR $fn: $! ====\n\n" );
	}

	trace( "==== $ts server ACK 0104 ====\n\n" );
	syswrite ( STDOUT, m_ack(0x0104) );
	return;
    }

    # Unhandled.
    trace( "==== $ts client ====\n", Hexify(\$msg), "\n" );
    return;
}

sub m_ack {
    pack( "nnnnC", 1, 2, 3, $_[0], 0 );
}

sub m_ping {
    pack( "nnnn", 1, 2, 2+length($data_logger), 0x0116 ) . $data_logger;
}

sub preprocess_msg {
    my ( $msg ) = @_;

    # Convenient telnet commands for testing.

    if ( $msg =~ /^ping(?:\s+(\S+))?/ ) {
	$data_logger //= "AH12345678";
	$msg = m_ping();
    }
    elsif ( $msg =~ /^ahoy(?:\s+(\S+))?/ ) {
	$msg = pack( "n[4]A[10]A[10].",
			1, 2, 0xd9, 0x0103,
			$1 // "AH12345678", "OP24510017", 6 + 0xd9 );
    }
    elsif ( $msg =~ /^data/ ) {
	$msg = pack( "n[4]A[10]A[10].",
			1, 2, 0xd9, 0x0104,
			$1 // "AH12345678", "OP24510017", 6 + 0xd9 );
    }
    elsif ($msg =~ /^q(?:uit)?/ ) {
	$s_timeout++;
    }

    return $msg;
}

################ Command line options ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally

    # Process options, if any.
    my $remote;

    if ( !GetOptions(
		     'ident'	=> \$ident,
		     'verbose'	=> \$verbose,
		     'trace'	=> \$trace,
		     'test'	=> \$test,
		     'help|?'	=> \$help,
		     'debug'	=> \$debug,
		    ) or $help )
    {
	app_usage(2);
    }
    app_ident() if $ident;

    $local_port ||= 5279;
}

sub app_ident {
    print STDERR ("This is $my_package [$my_name $my_version]\n");
}

sub app_usage {
    my ($exit) = @_;
    app_ident();
    print STDERR <<EndOfUsage;
Usage: $0 [options]
    --help		This message
    --ident		Shows identification
    --verbose		More verbose information

EndOfUsage
    exit $exit if defined $exit && $exit != 0;
}
