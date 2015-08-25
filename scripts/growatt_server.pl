#!/usr/bin/perl
#
# Author          : Johan Vromans
# Created On      : Tue Jul  7 21:59:04 2015
# Last Modified By: Johan Vromans
# Last Modified On: Mon Aug 24 20:43:53 2015
# Update Count    : 203
# Status          : Unknown, Use with caution!
#
################################################################
#
# Server for Growatt WiFi.
#
# The Growatt WiFi module communicates with the Growatt server
# (server.growatt.com, port 5279). This server can be used
# as a standalone replacement to intercept all traffic.
#
# Data packages that contain energy data from the data logger are
# written to disk in separate files for later processing.
#
# This server is loosely based on code by Peteris Krumins (peter@catonmat.net).

# Usage:
#
# In an empty directory, start the server. It will listen to port
# 5279.
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
# the current directory:
#
# 20150703135901.dat
# 20150703140004.dat
# ... and so on ...
#
# Alternatively, use systemd (or inetd, untested) to start the
# server.
#
################################################################

use warnings;
use strict;

################ Common stuff ################

use strict;

# Package name.
my $my_package = 'Growatt WiFi Tools';
# Program name and version.
my ($my_name, $my_version) = qw( growatt_server 0.23 );

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
my $local_port  = 5279;		# local port. DO NOT CHANGE
my $timeout;			# 30 minutes
my $verbose = 0;		# verbose processing
my $sock_act = 0;		# running through inetd or systemd

# Development options (not shown with -help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test = 0;			# test mode.

# Process command line options.
app_options();

# Post-processing.
$timeout //= $sock_act ? 300 : 1800;
$trace |= ($debug || $test);

################ Presets ################

my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';

################ The Process ################

use IO::Socket::INET;
use IO::Select;
use IO::Handle;
use Fcntl;
use Data::Hexify;

if ( $test ) {
    test();
    exit;
}

my $ioset = IO::Select->new;
my %socket_map;
my $s_reload = ".reload";
my $s_reboot = ".reboot";

$debug = 1;			# for the time being
$| = 1;				# flush standard output

my $server;
if ( $sock_act ) {
    my @tm = localtime(time);
    open( STDOUT, '>>',
	  sprintf( "%04d%02d%02d.log", 1900+$tm[5], 1+$tm[4], $tm[3] ) );
    print( ts(), " Starting Growatt server version $my_version",
	   " on stdin\n" );
    $server = IO::Socket::INET->new;
    $server->fdopen( 0, 'r' );
    print( ts(), " Connection accepted from ",
	   client_ip($server), "\n") if $debug;
    $ioset->add($server);

    $socket_map{$server} = $server;
}
else {
    print( ts(), " Starting Growatt server version $my_version",
	   " on 0.0.0.0:$local_port\n" );
    $server = new_server( '0.0.0.0', $local_port );
    $ioset->add($server);
}


my $busy;
while ( 1 ) {
    my @sockets = $ioset->can_read($timeout);
    unless ( @sockets ) {
	if ( !$sock_act && ( $busy || -f $s_reload ) ) {
	    unlink($s_reload);
	    print( "==== ", ts(), " TIMEOUT -- Reloading ====\n\n" );
	    exit 0;
	}
	else {
	    print( "==== ", ts(), " TIMEOUT ====\n\n" );
	    if ( $sock_act ) {
		unlink($s_reload);
		exit 0;
	    }
	    next;
	}
    }
    $busy = 1;
    for my $socket ( @sockets ) {
        if ( !$sock_act && $socket == $server ) {
            new_connection( $server );
        }
        else {
            next unless exists $socket_map{$socket};
            my $dest = $socket_map{$socket};
            my $buffer;
            my $len = $socket->sysread($buffer, 4096);
            if ( $len ) {
		while ( my $msg = split_msg( \$buffer ) ) {
		    $msg = preprocess_msg( $socket, $msg );
		    foreach ( process_msg( $socket, $msg ) ) {
			$dest->syswrite($_);
			postprocess_msg( $socket, $_ );
		    }
		}
            }
            else {
                close_connection($socket);
		if ( $sock_act ) {
		    print( ts(), " Server terminating\n\n" );
		    exit 0;
		}
            }
        }
    }
}

################ Subroutines ################

sub new_server {
    my ($host, $port) = @_;
    my $server = IO::Socket::INET->new(
        LocalAddr => $host,
        LocalPort => $port,
        ReuseAddr => 1,
        Listen    => 100
    ) || die "Unable to listen on $host:$port: $!";
}

sub ts {
    my @tm = localtime(time);
    sprintf( "%04d-%02d-%02d %02d:%02d:%02d",
	     1900 + $tm[5], 1+$tm[4], @tm[3,2,1,0] );
}

sub new_connection {
    my $server = shift;

    my $client = $server->accept;
    my $client_ip = client_ip($client);

    print( ts(), " Connection from $client_ip accepted\n") if $debug;

    $ioset->add($client);

    $socket_map{$client} = $client;
}

sub close_connection {
    my $client = shift;
    my $client_ip = client_ip($client);

    $ioset->remove($client);

    delete $socket_map{$client};

    $client->close;

    print( ts(), " Connection from $client_ip closed\n" ) if $debug;
}

sub client_ip {
    my $client = shift;
    return ( eval { $client->peerhost } || $ENV{REMOTE_ADDR} || "?.?.?.?" );
}

my $data_logger;

sub split_msg {
    my ( $bufref ) = @_;

    if ( $$bufref =~ /^\x00\x01\x00\x02(..)/ ) {
	my $length = unpack( "n", $1 );
	return substr( $$bufref, 0, $length+6, '' );
    }
    return;
}

sub disassemble {
    my ( $msg ) = @_;
    return unless $msg =~ /^\x00\x01\x00\x02(..)(..)/;

    my $length = unpack( "n", $1 );
    return { length => $length,
	     type   => unpack( "n", $2 ),
	     data   => substr( $msg, 8, $length-2 ),
	     prefix => substr( $msg, 0, 8 ) };
}

sub assemble {
    my ( $msg ) = @_;

    # Only data and type is used.
    return pack( "n4", 1, 2, 2+length($msg->{data}), $msg->{type} )
      . $msg->{data};
}

sub preprocess_msg {
    my ( $socket, $msg ) = @_;

    # Convenient telnet commands for testing.

    if ( $msg =~ /^ping(?:\s+(\S+))?/ ) {
	$msg = m_ping( $1 // $data_logger // "AH12345678" );
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
	print( ts(), " Server terminating\n" );
	exit 0;
    }

    return $msg;
}

my $identified;
BEGIN { $identified = 1 }	# skip identification

sub process_msg {
    my ( $socket, $msg ) = @_;

    # Processes a message.
    # Returns nothing, a (new) message, or a list of messages.

    my $tag = "client";

    my $ts = ts();

    my $m = disassemble($msg);
    unless ( $m ) {
	# Error?
	print( "==== $ts $tag ====\n", Hexify(\$msg), "\n" );
	return;
    }

    # PING.
    if ( $m->{type} == 0x0116 && $m->{length} == 12 ) {
	print( "==== $ts $tag PING ",
	       $data_logger = substr( $m->{data}, 0, 10 ),
	       " ====\n\n" ) if $debug;
	return m_ping();
    }

    if ( $m->{type} == 0x0103 && $m->{length} > 200 ) {
	# AHOY
	print( "==== $ts $tag AHOY ====\n", Hexify(\$msg), "\n" ) if $debug;
	$data_logger = substr( $m->{data}, 0, 10 );
	return $identified
	  ? m_ack( $m->{type} )
	  : ( m_ack( $m->{type} ), m_identify() );
    }

    # Dump energy reports to individual files.
    if ( $data_logger && $m->{type} == 0x0104 && $m->{length} > 210 ) {

	#### TODO: If supporting more than one inverter,
	#### prefix the filename by the inverter id.

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
	    $tag .= " ERROR $fn: $!";
	}

	# Dump message in hex.
	print( "==== $ts $tag ====\n", Hexify(\$msg), "\n" ) if $debug;

	return m_ack( $m->{type} );
    }

    # Ignore config messages.
    if ( $m->{type} == 0x0119 ) {
	$identified++;
	print( "==== $ts $tag ====\n", Hexify(\$msg), "\n" ) if $debug;
	return;
    }

    # Unhandled.
    print( "==== $ts $tag ====\n", Hexify(\$msg), "\n" ) if $debug;
    return;
}

sub postprocess_msg {
    my ( $socket, $msg ) = @_;

    my $tag = "server";

    my $ts = ts();

    my $m = disassemble($msg);
    unless ( $m ) {
	print( "==== $ts $tag ====\n", Hexify(\$msg), "\n" );
	return;
    }

    # PING.
    if ( $m->{type} == 0x0116 && $m->{length} == 12 ) {
	print( "==== $ts $tag PING ",
	       substr( $m->{data}, 0, 10 ), " ====\n\n" ) if $debug;
	return;
    }

    # ACK.
    if ( $m->{length} == 3
	 && ( $m->{type} == 0x0104 || $m->{type} == 0x0103 ) ) {

	printf( "==== %s %s ACK %04x %02x ====\n\n",
		$ts, $tag, $m->{type},
		unpack( "C", substr( $m->{data}, 0, 1 ) ) ) if $debug;

	# For development: If there's a file $s_reload in the current
	# directory, stop this instance of the server.
	# When invoked via the "run_server.sh" script this will
	# immedeately start a new server instance.
	# This can be used to upgrade to a new version of the
	# server.
	if ( -f $s_reload ) {
	    print( "==== $ts Reloading ====\n" );
	    unlink( $s_reload );
	    print( "\n" );
	    exit 0;
	}

	if ( -f $s_reboot ) {
	    unlink($s_reboot);
	    my $m = m_reboot();
	    print( "==== $ts $tag REBOOT ====\n", Hexify(\$m), "\n" );
	    $socket_map{$socket}->syswrite($m);
	}

	return;
    }

    # Dump energy reports to individual files.
    if ( $m->{type} == 0x0104 && $m->{length} > 210 ) {

	#### TODO: If supporting more than one inverter,
	#### prefix the filename by the inverter id.

	my $fn = $ts;
	$fn =~ s/[- :]//g;
	$fn .= ".dat";

	my $fd;

	if ( sysopen( $fd, $fn, O_WRONLY|O_CREAT )
	     and syswrite( $fd, $msg ) == length($msg)
	     and close($fd) ) {
	    # OK
	}
	else {
	    $tag .= " ERROR $fn: $!";
	}

	# Dump message in hex.
	print( "==== $ts $tag ====\n", Hexify(\$msg), "\n" ) if $trace;

	return;
    }

    # Unhandled.
    $tag .= " AHOY" if $m->{type} == 0x0103 && $m->{length} > 210;
    print( "==== $ts $tag ====\n", Hexify(\$msg), "\n" ) if $debug;
    return;
}

sub m_ping {
    my ( $dl ) = @_;
    $dl //= $data_logger;
    pack( "nnnn", 1, 2, 2+length($dl), 0x0116 ) . $dl;
}

sub m_ack {
    pack( "nnnnC", 1, 2, 3, $_[0], 0 );
}

sub m_identify {
    my ( $dl ) = @_;
    $dl //= $data_logger;
    pack( "n[4]A[10]n[2]",
	  1, 2, 6+length($dl), 0x0119,
	  $dl, 4, 0x15 );
}

sub m_reboot {
    my ( $dl ) = @_;
    $dl //= $data_logger;
    pack( "n[4]A[10]n[2]s",
	  1, 2, 7+length($dl), 0x0118,
	  $dl, 20, 1, "1" );
}

################ Command line options ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally

    # Process options, if any.
    my $remote;

    if ( !GetOptions(
		     'listen=i' => \$local_port,
		     'timeout=i' => \$timeout,
		     'inetd|systemd' => \$sock_act,
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
    --listen=NNNN	Local port to listen to (must be $local_port)
    --timeout=NNN	Timeout
    --inetd  --systemd	Running from inetd/systemd
    --help		This message
    --ident		Shows identification
    --verbose		More verbose information

EndOfUsage
    exit $exit if defined $exit && $exit != 0;
}

sub readhex {
    local $/;
    my $d = <DATA>;
    $d =~ s/^  ....: //gm;
    $d =~ s/  .*$//gm;
    $d =~ s/\s+//g;
    $d = pack("H*", $d);
    $d;
}

sub test {
    my $msg = readhex();
    my $new = preprocess_msg(123,$msg);
    print( "ORIG:\n", Hexify(\$msg), "\n\nNEW:\n", Hexify(\$new), "\n\n");
}

__DATA__
  0000: 00 01 00 02 00 21 01 19 41 48 34 34 34 36 30 34  .....!..AH444604
  0010: 37 37 00 10 00 11 41 43 3a 43 46 3a 32 33 3a 33  77....AC:CF:23:3
  0020: 44 3a 38 31 3a 45 35 00 01 00 02 00 22 01 19 41  D:81:E5....."..A
  0030: 48 34 34 34 36 30 34 37 37 00 11 00 12 67 72 6f  H44460477....gro
  0040: 70 72 78 2e 73 71 75 69 72 72 65 6c 2e 6e 6c 00  prx.squirrel.nl.
  0050: 01 00 02 00 14 01 19 41 48 34 34 34 36 30 34 37  .......AH4446047
  0060: 37 00 12 00 04 35 32 37 39 00 01 00 02 00 22 01  7....5279.....".
  0070: 19 41 48 34 34 34 36 30 34 37 37 00 13 00 12 67  .AH44460477....g
  0080: 72 6f 70 72 78 2e 73 71 75 69 72 72 65 6c 2e 6e  roprx.squirrel.n
  0090: 6c 00 01 00 02 00 17 01 19 41 48 34 34 34 36 30  l........AH44460
  00a0: 34 37 37 00 15 00 07 33 2e 31 2e 30 2e 30        477....3.1.0.0  
