#!/usr/bin/perl
#
# Author          : Johan Vromans
# Created On      : Tue Jul  7 21:59:04 2015
# Last Modified By: Johan Vromans
# Last Modified On: Fri Jul 10 09:36:38 2015
# Update Count    : 75
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
my ($my_name, $my_version) = qw( growatt_proxy 0.14 );

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
# NOTE: CURRENTLY, LOCAL HOST AND REMOTE HOST MUST BE EXACTLY 18 CHARS LONG
my $local_host  = "groprx.squirrel.nl";	# proxy server (this hist)
my $local_port  = 5279;		# local port. DO NOT CHANGE
my $remote_host = "server.growatt.com";		# remote server. DO NOT CHANGE
my $remote_port = 5279;		# remote port. DO NOT CHANGE
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

# Restrict connections to some ip's, or allow from all.
my @allowed_ips = ('all', '10.10.10.5');

my $ioset = IO::Select->new;
my %socket_map;
my $sentinel = ".reload";

$debug = 1;			# for the time being
$| = 1;				# flush standard output

print( ts(), " Starting Growatt proxy server version $my_version",
       " on 0.0.0.0:$local_port\n" );
my $server = new_server( '0.0.0.0', $local_port );
$ioset->add($server);

while ( 1 ) {
    for my $socket ( $ioset->can_read ) {
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
    return IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port
    ) || die "Unable to connect to $host:$port: $!";
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

    unless ( client_allowed($client) ) {
        print( ts(), " Connection from $client_ip denied.\n" ) if $debug;
        $client->close;
        return;
    }
    print( ts(), " Connection from $client_ip accepted.\n") if $debug;

    my $remote = new_conn( $remote_host, $remote_port );
    $ioset->add($client);
    $ioset->add($remote);

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

    print( ts(), " Connection from $client_ip closed.\n" ) if $debug;
}

sub client_ip {
    my $client = shift;
    return inet_ntoa($client->sockaddr);
}

sub client_allowed {
    my $client = shift;
    my $client_ip = client_ip($client);
    return grep { $_ eq $client_ip || $_ eq 'all' } @allowed_ips;
}

my $datalogger;			# keep track of C/S

sub preprocess_package {
    my ( $socket, $buffer ) = @_;

    # Assume the first message is from the data logger.
    $datalogger ||= $socket;
    my $tag = $socket == $datalogger ? "client" : "server";

    my $rhp = qr/$remote_host/;
    my $lhp = qr/$local_host/;
    my $fixed = $buffer;
    my $ts = ts();

    # Pretend that we're listening to their server.
    $buffer =~ s/^(.*\x00(?:\x13|\x11)\x00\x12)$lhp(.*)/$1$remote_host$2/g;
    # Refuse to change the server.
    $buffer =~ s/^(.*\x00\x13\x00\x12)$rhp(.*)/$1$local_host$2/g
      if $fixed eq $buffer;

    if ( $fixed ne $buffer ) {
	print( "==== $ts $tag FIXED ====\n", Hexify(\$fixed), "\n",
	       Hexify(\$buffer), "\n");
    }

    return $buffer;
}

sub postprocess_package {
    my ( $socket, $buffer ) = @_;

    # Assume the first message is from the data logger.
    $datalogger ||= $socket;
    my $tag = $socket == $datalogger ? "client" : "server";

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
	    # Only the server sends this.
	    undef $datalogger;
	    $tag = "server";

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
	    # Only the server sends this.
	    undef $datalogger;
	    $tag = "server";

	    printf( "==== %s %s NACK %02x ====\n\n",
		    $ts, $tag,
		    unpack( "C", substr( $data, 0, 1 ) ) );
	    return 1;
	}

	# Dump energy reports to individual files.
	if ( $type == 0x0104 && $length > 210 ) {
	    # Only the client sends this.
	    $tag = "client";
	    $datalogger = $socket;

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
    --listen=NNNN		local port to listen to
    --remote=XXXX:NNNN		remote server name and port
    --help			this message
    --ident			show identification
    --verbose			verbose information

EndOfUsage
    exit $exit if defined $exit && $exit != 0;
}
