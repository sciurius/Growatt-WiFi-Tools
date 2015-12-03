# Standard settings for plots with a days on the x-axis.

# Depends on:
#  xwidth (pl_params.plot)
#  datafile (pl_params.plot)

# Horizontal axis: Time.
set xdata time

# Seconds per day.
daysecs = 86400

# Extract the start date from row 2, col 0.
mstart = `perl -an -e '$. == 2 && do { print q{"},$F[0],q{"};exit }' @datafile`
# Extract the end date from last row, col 0.
mend = `perl -an -e 'eof && do { print q{"},$F[0],q{"};exit }' @datafile`

# Range and ticks.
set xrange [ strptime('%Y-%m-%d',mstart)-daysecs:strptime('%Y-%m-%d',mend)+daysecs]

# Condensed font for horizontal tics.
set xtics font "Liberation Sans Narrow,12";

# If the graph is smaller, use 2-day tics.
if ( xwidth < 800 ) {
    set xtics mstart,2*daysecs,mend format "%1d" time
}
else {
    set xtics mstart,daysecs,mend format "%1d" time
}

# No minor tics.
unset mxtics

# Bar graphs with disconnected staves.
set boxwidth 0.8  relative
set style fill solid border -1

# Key usially goes below the graph.
set key below
