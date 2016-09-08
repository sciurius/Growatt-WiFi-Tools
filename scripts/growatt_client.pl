#!/usr/bin/perl
#
# Author          : Johan Vromans
# Created On      : Tue Aug 25 20:38:22 2015
# Last Modified By: Johan Vromans
# Last Modified On: Thu Sep  8 22:09:04 2016
# Update Count    : 76
# Status          : Unknown, Use with caution!
#
################################################################
#
# Growatt WiFi emulating client.
#
# This client connects to the Growatt server and pretends it is the
# WiFi stick talking.
#
# It depends on the following data files residing in a data directory:
#
#   ahoy.dat        - client announce message
#   configXX.dat    - client configuration messages
#   data.dat        - the last data package.
#
# These data files are written by the growatt_server.
#
# When the communication is established, every 5 minutes the client
# looks for a new data file and, if found, it is sent to the server.
#
# This is highlly experimental for now.
#
################################################################

use warnings;
use strict;

################ Common stuff ################

use strict;

# Package name.
my $my_package = 'Growatt WiFi Tools';
# Program name and version.
my ($my_name, $my_version) = qw( growatt_client 0.01 );

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
my $remote_host = "server.growatt.com";		# remote server. DO NOT CHANGE
my $remote_port = 5279;		# remote port. DO NOT CHANGE
my $datalogger;			# datalogger
my $timeout;			# 30 minutes
my $datadir = ".";		# where the data is
my $verbose = 0;		# verbose processing

# Development options (not shown with -help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test = 0;			# test mode.

# Process command line options.
app_options();

# Setup protocol dependent stuff.
set_proto();

# Post-processing.
$timeout //= 300;
$trace |= ($debug || $test);
$verbose |= $trace;

################ Presets ################

my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';

################ The Process ################

use IO::Socket::INET;
use IO::Select;
use IO::Handle;
use Fcntl;
use Data::Hexify;

my $ioset = IO::Select->new;
my $server = new_conn( $remote_host, $remote_port );
$ioset->add($server);

$debug = 1;			# for the time being

warn( ts(), " Starting Growatt datalogger emulator version $my_version",
      " for $datalogger\n\n" );
warn( ts(), " Connected to $remote_host:$remote_port (", client_ip($server), ")\n\n" );

my $last_ping = 0;
my $last_ahoy = 0;
my $last_data = 0;

# States.
# 0   need to send AHOY
# 1   waiting for ACK 0103
# 2   may send data
# 3   waiting for ACK 0104
my $state = 0;
my $now = time;

while ( 1 ) {
    my @sockets = $ioset->can_read(1);
    $now = time;
    unless ( @sockets ) {

	if ( $now - $last_ping > 180 ) {
	    my $msg = m_ping();
	    warn( "==== ", ts(), " client PING $datalogger ==$state==\n\n" );
	    $server->syswrite($msg);
	    $last_ping = $now;
	}

	if ( $state == 0 ) {
	    my $msg = m_ahoy();
	    warn( "==== ", ts(), " client AHOY ==$state==\n\n" );
	    $server->syswrite($msg);
	    $state = 1;
	    $last_ahoy = $now;
	}
	elsif ( $state == 1 && ( $now - $last_ahoy > 30 ) ) {
	    $state = 0;
	}
	elsif ( $state == 2 ) {
	    next unless $now - $last_data > 300;
	    if ( my $msg = new_data() ) {
		warn( "==== ", ts(), " client DATA ==$state==\n\n" );
		$server->syswrite($msg);
		# Force retry in 20 seconds.
		# ACK will update the timestamp appropriately.
		$last_data = $now + 280;
		$state = 3;
	    }
	}
	elsif ( $state == 3 ) {
	    $state = 2 if $now - $last_data > 300;
	}
	next;
    }

    my $buffer;
    my $len = $sockets[0]->sysread($buffer, 4096);
    if ( $len ) {
	while ( my $msg = split_msg( \$buffer ) ) {
	    process_msg( $sockets[0], $msg );
	}
    }
    else {
	$sockets[0]->close;
	warn( ts(), " Terminating\n" );
	last;
    }
}

exit 0;

################ Subroutines ################

sub new_conn {
    my ($host, $port) = @_;
    for ( 0..4 ) {
	my $s = IO::Socket::INET->new( PeerAddr => $host,
				       PeerPort => $port
				     );
	return $s if $s;
	warn( "==== ", ts(), " Unable to connect to $host:$port: $! (retrying) ====\n\n" );
	sleep 2 + rand(2);
    }
    die( "==== ", ts(), " Unable to connect to $host:$port: $! ====\n\n" );
}

sub ts {
    my @tm = localtime(time);
    sprintf( "%04d-%02d-%02d %02d:%02d:%02d",
	     1900 + $tm[5], 1+$tm[4], @tm[3,2,1,0] );
}

sub client_ip {
    my $client = shift;
    return ( eval { $client->peerhost } || "?.?.?.?" );
}

# Messages always start with pack("nn", HB1, HB2)
sub HB1();	# first word
sub HB2();	# second word
my $msg_pat;	# to match a message start

sub set_proto {
    my $ahoy = m_ahoy();
    $datalogger = substr( $ahoy, 8, 10 );
    if ( substr( $ahoy, 3, 1 ) eq "\x00" ) {
	# WiFi sticks version 1.0.0.0 use these.
	eval "sub HB1() { 1 } sub HB2() { 0 }";
    }
    else {
	# WiFi sticks version >= 3.0.0.0 use these.
	eval "sub HB1() { 1 } sub HB2() { 2 }";
    }
    $msg_pat = eval "qr(".pack("nn", HB1, HB2).")";
}

sub split_msg {
    my ( $bufref ) = @_;

    if ( $$bufref =~ /^$msg_pat(..)/o ) {
	my $length = unpack( "n", $1 );
	return substr( $$bufref, 0, $length+6, '' );
    }
    return;
}

sub disassemble {
    my ( $msg ) = @_;
    return unless $msg =~ /^$msg_pat(..)(..)/o;

    my $length = unpack( "n", $1 );
    return { length => $length,
	     type   => unpack( "n", $2 ),
	     data   => substr( $msg, 8, $length-2 ),
	     prefix => substr( $msg, 0, 8 ) };
}

sub assemble {
    my ( $msg ) = @_;

    # Only data and type is used.
    return pack( "n4", HB1, HB2, 2+length($msg->{data}), $msg->{type} )
      . $msg->{data};
}

sub process_msg {
    my ( $socket, $msg ) = @_;

    my $tag = $socket != $server ? "client" : "server";

    my $ts = ts();

    my $m = disassemble($msg);
    unless ( $m ) {
	warn( "==== $ts $tag ==$state==\n", Hexify(\$msg), "\n" );
	return;
    }

    # PING.
    if ( $m->{type} == 0x0116 && $m->{length} == 12 ) {
	warn( "==== $ts $tag PING ",
	       substr( $m->{data}, 0, 10 ),
	       " ==$state==\n\n" );
	return;
    }

    # ACK.
    if ( $m->{length} == 3
	 && ( $m->{type} == 0x0104 || $m->{type} == 0x0103 ) ) {

	warn( sprintf( "==== %s %s ACK %04x %02x ==$state==\n\n",
		       $ts, $tag, $m->{type},
		       unpack( "C", substr( $m->{data}, 0, 1 ) ) ) );

	if ( $state == 1 && $m->{type} == 0x0103 ) {
	    my $msg = new_data(1);
	    warn( "==== $ts client DATA ==$state==\n", Hexify(\$msg), "\n" );
	    $server->syswrite($msg);
	    $state = 3
	}
	if ( $state == 3 && $m->{type} == 0x0104 ) {
	    $last_data = $now;
	    $state = 2;
	}
	return;
    }

    if ( $m->{type} == 0x0119 ) {
	warn( "==== $ts $tag ==$state==\n", Hexify(\$msg), "\n" );
	my ( $first, $last ) = unpack( "nn", substr( $m->{data}, 10 ) );
	my $msg = "";
	foreach my $i ( $first .. $last ) {
	    if ( $i == 0x10 ) {
		$server->syswrite($msg);
		$msg = "";
	    }
	    my $m = m_config($i);
	    next unless $m;
	    $msg .= $m;
	    warn( "==== $ts client ==$state==\n", Hexify(\$m), "\n" );
	}
	$server->syswrite($msg);
	$state = 0;
	return;
    }

    # Unhandled.
    warn( "==== $ts $tag ==$state==\n", Hexify(\$msg), "\n" );
    return;
}

sub m_ping {
    pack( "n[4]A[10]",
	  HB1, HB2, 2+length($datalogger), 0x0116,
	  $datalogger );
}

sub getdata {
    my ( $key ) = @_;
    my $df = "$datadir/$key.dat";
    return unless -s $df;
    my $len = -s _;
    my $fd;
    my $buf;
    sysopen( $fd, $df, O_RDONLY )
      && sysread( $fd, $buf, $len ) == $len
	&& return $buf;
    return;
}

sub m_ahoy {
    getdata("ahoy") or die("Missing AHOY data\n");
}

sub m_data {
    getdata("data");
}

sub m_config {
    my ( $ix ) = @_;
    my $xix = sprintf("config%02x",$ix);
    getdata($xix);
}

sub new_data {
    my $force = shift;
    my @st = stat("$datadir/data.dat");
    return if $st[9] <= $last_data && !$force;
    $last_data = $st[9];
    getdata("data");
}

################ Command line options ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally

    # Process options, if any.
    my $remote;

    if ( !GetOptions(
		     'remote=s' => \$remote,
		     'datadir'  => \$datadir,
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

    if ( $remote ) {
	( $remote_host, $remote_port ) = split( /:/, $remote );
    }
}

sub app_ident {
    print STDERR ("This is $my_package [$my_name $my_version]\n");
}

sub app_usage {
    my ($exit) = @_;
    app_ident();
    print STDERR <<EndOfUsage;
Usage: $0 [options] --logger=XXX

    --remote=XXXX:NNNN	Remote server name and port (must be $remote_host:$remote_port)
    --help		This message
    --ident		Shows identification
    --verbose		More verbose information

EndOfUsage
    exit $exit if defined $exit && $exit != 0;
}
