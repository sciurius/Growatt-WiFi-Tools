#! /usr/bin/perl -w

# Create a status line to be shown on a Squeezebox using the
# FileviewerPlus plugin.

# Author          : Johan Vromans
# Created On      : Mon Jul 20 11:11:37 2015
# Last Modified By: Johan Vromans
# Last Modified On: Mon Jul 20 11:12:34 2015
# Update Count    : 1
# Status          : Unknown, Use with caution!

use strict;
use warnings;

use constant E_pv => 9;
use constant E_total => 23;

# Skip first line (column headings).
my $line = <>;

my $einit = 0;			# initial value for total energy.
my $epv;			# current amount of energy
my $etot;			# total amount

# Get final value for total energy from the last line.
while ( <> ) {
    next unless eof || $. == 2;
    s/,,/,0,/g;
    my @a = split( /,/, $_ );
    $epv = $a[E_pv];
    $etot = $a[E_total];
    $einit ||= $etot;
}

# Print status line.
printf( "[center][date]\n[time] - %.1f kW (%.1f kWh)\n",
	$epv/1000, $etot - $einit );
