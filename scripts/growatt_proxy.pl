#!/usr/bin/perl
#
# Author          : Johan Vromans
# Created On      : Tue Jul  7 21:59:04 2015
# Last Modified By: Johan Vromans
# Last Modified On: Thu Jul 16 08:38:04 2015
# Update Count    : 95
# Status          : Unknown, Use with caution!
#
################################################################
#
# Proxy server for Growatt WiFi.
#
# The Growatt WiFi module communicates with the Growatt server
# (server.growatt.com, port 5279). This proxy server can be put
# between de module and the server to untercept all traffic.
#
# The proxy is transparent, every data package from the module is sent
# to the server, and vice versa. An extensive logging is produced of
# all traffic.
#
# Data packages that contain energy data from the data logger are
# written to disk in separate files for later processing.
#
# This server is loosely based on code by Peteris Krumins (peter@catonmat.net).

# Usage:
#
# In an empty directory, start the proxy server. It will listen to
# port 5279 and connect to the Growatt server.
#
# Using the Growatt WiFi module administrative interface, go to the
# "STA Interface Setting" and change "Server Address" (default:
# server.growatt.com) to the name or ip of the system running the
# proxy server.
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
################################################################

use warnings;
use strict;

################ Common stuff ################

use strict;

# Package name.
my $my_package = 'Growatt WiFi Tools';
# Program name and version.
my ($my_name, $my_version) = qw( growatt_proxy 0.17 );

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
# NOTE: CURRENTLY, LOCAL HOST AND REMOTE HOST MUST BE EXACTLY 18 CHARS LONG
my $local_host  = "groprx.squirrel.nl";	# proxy server (this hist)
my $local_port  = 5279;		# local port. DO NOT CHANGE
my $remote_host = "server.growatt.com";		# remote server. DO NOT CHANGE
my $remote_port = 5279;		# remote port. DO NOT CHANGE
my $timeout = 1800;		# 30 minutes
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

use IO::Socket::INET;
use IO::Select;
use Fcntl;
use Data::Hexify;

if ( $test ) {
    test();
    exit;
}

my $ioset = IO::Select->new;
my %socket_map;
my $sentinel = ".reload";
my $remote_socket;

$debug = 1;			# for the time being
$| = 1;				# flush standard output

print( ts(), " Starting Growatt proxy server version $my_version",
       " on 0.0.0.0:$local_port\n" );
my $server = new_server( '0.0.0.0', $local_port );
$ioset->add($server);

my $busy;
while ( 1 ) {
    my @sockets = $ioset->can_read($timeout);
    unless ( @sockets ) {
	if ( $busy ) {
	    print( "==== ", ts(), " TIMEOUT -- Reloading ====\n\n" );
	    exit 0;
	}
	else {
	    print( "==== ", ts(), " TIMEOUT ====\n\n" );
	    next;
	}
	#close_all();
	#next;
    }
    $busy = 1;
    for my $socket ( @sockets ) {
        if ( $socket == $server ) {
            new_connection( $server, $remote_host, $remote_port );
        }
        else {
            next unless exists $socket_map{$socket};
            my $remote = $socket_map{$socket};
            my $buffer;
            my $len = $socket->sysread($buffer, 4096);
            if ( $len ) {
		$buffer = preprocess_package( $socket, $buffer );
                $remote->syswrite($buffer);
		postprocess_package( $socket, $buffer );
            }
            else {
                close_connection($socket);
            }
        }
    }
}

################ Subroutines ################

sub new_conn {
    my ($host, $port) = @_;
    for ( 0..4 ) {
	my $s = IO::Socket::INET->new( PeerAddr => $host,
				       PeerPort => $port
				     );
	return $s if $s;
	print( "==== ", ts(), " Unable to connect to $host:$port: $! (retrying) ====\n\n" );
	sleep 2 + random(2);
    }
    die( "==== ", ts(), " Unable to connect to $host:$port: $! ====\n\n" );
}

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
    my $remote_host = shift;
    my $remote_port = shift;

    my $client = $server->accept;
    my $client_ip = client_ip($client);

    print( ts(), " Connection from $client_ip accepted\n") if $debug;

    my $remote = new_conn( $remote_host, $remote_port );
    print( ts(), " Connection to $remote_host (",
	   $remote->peerhost, ") port $remote_port established\n") if $debug;

    $ioset->add($client);
    $ioset->add($remote);
    $remote_socket = $remote;

    $socket_map{$client} = $remote;
    $socket_map{$remote} = $client;
}

sub close_connection {
    my $client = shift;
    my $client_ip = client_ip($client);
    my $remote = $socket_map{$client};

    $ioset->remove($client);
    $ioset->remove($remote);

    delete $socket_map{$client};
    delete $socket_map{$remote};

    $client->close;
    $remote->close;

    print( ts(), " Connection from $client_ip closed\n" ) if $debug;
}

sub close_all {
    foreach my $socket ( keys %socket_map ) {
	next if $socket == $remote_socket;
	close_connection($socket);
    }
    #### OOPS: $remote_socket has already been closed.
    print( ts(), " Connection to ",
	   $remote_socket->peerhost, " closed\n" ) if $debug;
    $remote_socket->close;
    undef $remote_socket;
    %socket_map = ();
}

sub client_ip {
    my $client = shift;
    return $client->peerhost;
}

sub preprocess_package {
    my ( $socket, $buffer ) = @_;

    my $tag = $socket != $remote_socket ? "client" : "server";

    my $rhp = qr/$remote_host/;
    my $lhp = qr/$local_host/;
    my $fixed = $buffer;
    my $ts = ts();

    # Pretend that we're listening to their server.
    $buffer =~ s/(\x00(?:\x13|\x11)\x00\x12)$lhp/$1$remote_host/g;
    # Refuse to change the server.
    $buffer =~ s/(\x00\x13\x00\x12)$rhp/$1$local_host/g
      if $fixed eq $buffer;

    if ( $fixed ne $buffer ) {
	print( "==== $ts $tag FIXED ====\n", Hexify(\$fixed), "\n",
	       Hexify(\$buffer), "\n");
    }

    return $buffer;
}

sub postprocess_package {
    my ( $socket, $buffer ) = @_;

    my $tag = $socket != $remote_socket ? "client" : "server";

    my $ts = ts();
    my $fail = 0;

    my $handler = sub {
	$fail++, return unless $buffer =~ /^\x00\x01\x00\x02(..)(..)/;

	# Detach this message from the package.
	my $length = unpack( "n", $1 );
	my $type   = unpack( "n", $2 );
	my $data   = substr( $buffer, 8, $length-2 );
	my $prefix = substr( $buffer, 0, 8 );
	$buffer    = substr( $buffer, 6 + $length );

	# PING.
	if ( $type == 0x0116 && $length == 12 ) {
	    print( "==== $ts $tag PING ",
		   substr( $data, 0, 10 ), " ====\n\n" );
	    return 1;
	}

	# ACK.
	if ( $type == 0x0104 && $length == 3 && length($buffer) == 0 ) {

	    printf( "==== %s %s ACK %02x ====\n\n",
		    $ts, $tag,
		    unpack( "C", substr( $data, 0, 1 ) ) );

	    # For development: If there's a file $sentinel in the current
	    # directory, stop this instance of the server.
	    # When invoked via the "run_server.sh" script this will
	    # immedeately start a new server instance.
	    # This can be used to upgrade to a new version of the
	    # server.
	    if ( -f $sentinel ) {
		print( "==== $ts Reloading ====\n" );
		open( my $fd, '<', $sentinel );
		print <$fd>;
		close($fd);
		unlink( $sentinel );
		print( "\n" );
		exit 0;
	    }

	    return 1;
	}

	# NACK.
	if ( $type == 0x0103 && $length == 3 ) {

	    printf( "==== %s %s NACK %02x ====\n\n",
		    $ts, $tag,
		    unpack( "C", substr( $data, 0, 1 ) ) );
	    return 1;
	}

	# Dump energy reports to individual files.
	if ( $type == 0x0104 && $length > 210 ) {

	    my $fn = $ts;
	    $fn =~ s/[- :]//g;
	    $fn .= ".dat";

	    my $fd;
	    $data = $prefix.$data;

	    if ( sysopen( $fd, $fn, O_WRONLY|O_CREAT )
		 and syswrite( $fd, $data ) == length($data)
		 and close($fd) ) {
		# OK
	    }
	    else {
		$tag .= " ERROR $fn: $!";
	    }

	    # Dump message in hex.
	    print( "==== $ts $tag ====\n", Hexify(\$data), "\n" );

	    return 1;
	}

	# Unhandled.
	$data = $prefix.$data;
	print( "==== $ts $tag ====\n", Hexify(\$data), "\n" );
	return 1;
    };

    # Process all messages in the buffer.
    while ( length($buffer) && !$fail ) {
	next if $handler->();

	# Dump unhandled messages in hex.
	print( "==== $ts $tag ====\n", Hexify(\$buffer), "\n" );
    }
}

################ Command line options ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally

    # Process options, if any.
    my $remote;

    if ( !GetOptions(
		     'listen'   => \$local_port,
		     'remote'   => \$remote,
		     'timeout=i' => \$timeout,
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
Usage: $0 [options]
    --listen=NNNN	Local port to listen to (must be $local_port)
    --remote=XXXX:NNNN	Remote server name and port (must be $remote_host:$remote_port)
    --timeout=NNN	Timeout (default: $timeout seconds)
    --help		This message
    --ident		Shows identification
    --verbose		More verbose information.

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
    my $buffer = readhex();
    my $new = preprocess_package(123,$buffer);
    print( "ORIG:\n", Hexify(\$buffer), "\n\nNEW:\n", Hexify(\$new), "\n\n");
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
