#!/usr/bin/perl
#
# Author          : Johan Vromans
# Created On      : Tue Jul  7 21:59:04 2015
# Last Modified By: Johan Vromans
# Last Modified On: Sun Jul 12 20:48:32 2015
# Update Count    : 135
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
my ($my_name, $my_version) = qw( growatt_proxy 0.40 );

################ Command line parameters ################

use Getopt::Long 2.13;

use constant REMOTE_SERVER => "server.growatt.com";
use constant REMOTE_PORT   => 5279;
use constant LOCAL_PORT    => 5279;

# Command line options.
my $local_host  = "groprx.squirrel.nl";	# proxy server (this host)
my $local_port  = LOCAL_PORT;		# local port. DO NOT CHANGE
my $remote_host = REMOTE_SERVER;	# remote server. DO NOT CHANGE
my $remote_port = LOCAL_PORT;		# remote port. DO NOT CHANGE
my $data_logger = "AH44460477";
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

if ( $test ) {
    test();
    exit;
}

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
my $remote_socket;

$debug = 1;			# for the time being
$| = 1;				# flush standard output

print( "==== ", ts(), " Starting Growatt proxy server version $my_version",
       " on 0.0.0.0:$local_port\n" );
my $server = new_server( '0.0.0.0', $local_port );
$ioset->add($server);

while ( 1 ) {
    for my $socket ( $ioset->can_read ) {
        if ( $socket == $server ) {
            new_connection( $server, $remote_host, $remote_port );
	    next;
        }

	next unless exists $socket_map{$socket};

	my $ts = ts();
	my $tag = $socket == $remote_socket ? "server" : "client";

	my $remote = $socket_map{$socket};
	my $buffer;
	my $len = $socket->sysread( $buffer, 40960 );
	unless ( defined $len ) {
	    warn( $ts, "  Socket read error ($tag): $!\n");
	    next;
	}
	if ( $len == 0 ) {
	    close_connection($socket);
            next;
	}

	my $orig = $buffer;
	my $dgrams = split_message( $socket, $buffer );
	foreach ( @$dgrams ) {
	    $_ = process_datagram($_);
	}
	$buffer = assemble_message($dgrams);

	my $did;
	if ( @$dgrams == 1 ) {
	  for ( $dgrams->[0] ) {
	    if ( $_->{type} == 0x0116 ) {
		print( "==== $ts  $tag PING\n\n" );
		$did++;
	    }
	    elsif ( $_->{data_raw} eq "\x01\x04\x00" ) {
		print( "==== $ts  $tag ACK\n\n" );
		$did++;
	    }
	    elsif ( $_->{data_raw} eq "\x01\x03\x00" ) {
		print( "==== $ts  $tag NACK\n\n" );
		$did++;
	    }
	  }
	}

	print( "==== $ts\n", Hexify(\$orig), "\n" ) unless $did++;
	if ( $orig ne $buffer ) {
	    print( "==== $ts  $tag FIXED\n",
		   Hexify(\$buffer), "\n" );
	}

	$len = $remote->syswrite($buffer);
	unless ( defined $len ) {
	    warn( "==== $ts  Socket wite error ($tag): $!\n" );
	    next;
	}
	if ( $len == 0 ) {
	    warn( "==== $ts  Socket wite error ($tag): EOF\n" );
            next;
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
        print( "==== ", ts(), " Connection from $client_ip denied.\n" ) if $debug;
        $client->close;
        return;
    }
    print( "==== ", ts(), " Connection from $client_ip accepted.\n") if $debug;

    my $remote = new_conn( $remote_host, $remote_port );
    $ioset->add($client);
    $ioset->add($remote);
    $remote_socket ||= $remote;

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

    print( "==== ", ts(), " Connection from $client_ip closed.\n" ) if $debug;
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

sub split_message {
    my ( $socket, $buffer ) = @_;

    my $d = [];

    while ( length($buffer) ) {
	unless ( $buffer =~ /^\x00\x01\x00\x02(..)(..)/ ) {
	    push( @$d, { type   => -1,
			 length => length($buffer),
			 data   => $buffer,
			 socket => $socket,
		       } );
	    return $d;
	}
	my $length = unpack( "n", $1 );
	my $type   = unpack( "n", $2 );
	my $data   = substr( $buffer, 8, $length-2 );
	$buffer    = substr( $buffer, 6 + $length );
	my $res = { type     => $type,
		    length   => $length,
		    data_raw => $data,
		    socket   => $socket,
		  };
	if ( $type == 0x0118 || $type == 0x0119 ) {
	    $res->{data} =
	      { logger   => substr($data,0,10),
		type     => unpack("n",substr($data,10,2)),
		length   => unpack("n",substr($data,12,2)),
		data_raw => substr($data,14),
	      };
	}
	push( @$d, $res );
    }

    return $d;
}

sub process_datagram {
    my ( $dgram ) = @_;

    my $fix;

    # Reports from client to server.
    if ( $dgram->{type} == 0x0119
	 && ( $dgram->{data}->{type} == 0x0011
	      || $dgram->{data}->{type} == 0x0013 ) ) {
	$dgram->{data}->{data_raw} = REMOTE_SERVER;
	$fix++;
    }

    # Server reconfig client.
    if ( $dgram->{type} == 0x0118
	 && $dgram->{data}->{type} == 0x0013 ) {
	$dgram->{data}->{data_raw} = $local_host;
	$fix++;
    }

    return $dgram;
}

sub assemble_message {
    my ( $dgrams ) = @_;
    my $buffer = "";
    foreach ( @$dgrams ) {
	if ( defined $_->{data} ) {
	    $_->{data_raw} = $_->{data}->{logger} .
			     pack( "nn",
				   $_->{data}->{type},
				   length($_->{data}->{data_raw})) .
			     $_->{data}->{data_raw}
	}
	$buffer .= pack("nnnn", 1, 2,
			length($_->{data_raw}) + 2,
			$_->{type} ) .
		   $_->{data_raw};
    }
    return $buffer;
}

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
    my $local;

    if ( !GetOptions(
		     'listen'   => \$local_port,
		     'remote'   => \$remote,
		     'remote'   => \$local,
		     'logger=s' => \$data_logger,
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

    $local_port ||= LOCAL_PORT;
    if ( $remote ) {
	( $remote_host, $remote_port ) = split( /:/, $remote );
    }
    if ( $local ) {
	( $local_host, $local_port ) = split( /:/, $local );
    }

    warn( "Possible configuration problem: listen port should be ",
	  LOCAL_PORT, " instead of $local_port\n")
      unless $local_port == LOCAL_PORT;
    warn( "Possible configuration problem: remote server should be ",
	  REMOTE_SERVER, " instead of $remote_host\n")
      unless $remote_host eq REMOTE_SERVER;
    warn( "Possible configuration problem: remote port should be ",
	  LOCAL_PORT, " instead of $remote_port\n")
      unless $remote_port == LOCAL_PORT;

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
    --proxy=XXXX:NNNN		proxy server name and port
    --remote=XXXX:NNNN		remote server name and port
    --help			this message
    --ident			show identification
    --verbose			verbose information

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
    my $dgrams = split_message( 123, $buffer );
    use Data::Dumper;
    $Data::Dumper::Useqq = 1;
    warn(Dumper($dgrams));
    foreach ( @$dgrams ) {
	$_ = process_datagram($_);
    }
    my $new = assemble_message($dgrams);
    if ( $new eq $buffer ) {
	print("OK\n");
    }
    else {
	print( "ORIG:\n", Hexify(\$buffer), "\n\nNEW:\n", Hexify(\$new), "\n\n");
    }
}

__DATA__
  0000: 00 01 00 02 00 d9 01 04 41 48 34 34 34 36 30 34  ........AH444604
  0010: 37 37 4f 50 32 34 35 31 30 30 31 37 00 00 00 00  77OP24510017....
  0020: 00 00 02 00 00 00 2c 00 01 00 00 02 c2 0c 5f 00  ......,......._.
  0030: 01 00 00 01 3c 0f 3c 00 01 00 00 01 86 00 00 01  ....<.<.........
  0040: f2 13 83 08 f4 00 00 00 00 00 00 08 e3 00 01 00  ................
  0050: 00 00 e3 08 f4 00 01 00 00 00 e5 00 00 01 00 00  ................
  0060: 00 0a 81 00 14 0d 8e 01 a4 00 00 00 00 00 00 00  ................
  0070: 00 09 04 12 60 00 00 00 00 01 ab 0b 40 0b 43 00  ....`.......@.C.
  0080: 00 00 2d 00 59 4e 20 00 00 00 00 00 00 00 6a 00  ..-.YN .......j.
  0090: 00 00 6a 00 00 00 99 00 00 09 c3 00 00 0a 2d 00  ..j...........-.
  00a0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
  00b0: 01 00 01 11 70 00 00 00 00 00 00 00 00 00 00 00  ....p...........
  00c0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
  00d0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00     ............... 
