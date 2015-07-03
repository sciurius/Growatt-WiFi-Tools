# Horizontal axis: time
set xdata time

# Left vertical axis: Power.
set yrange [ 0:7 ]
set format y "%g kW"

# Right vertical axis: Current per PV.
set y2range [ 0:14 ]
set format y2 "%g A"
set y2tics

# Input date format.
set timefmt '"%d-%m-%Y %H:%M:%S"'
# Output date format.
set format x "%H:%M"

set macros
datafile = 'current_plot.data'
today = `perl -ple 'print q{"},substr($_,1,10),q{"}; exit' @datafile`

# set title strftime( "%A, %d %B %Y", today )
set title today
set grid

plot datafile using 1:($2/1000) with lines title "Power (kW)", \
     datafile using 1:3 axes x1y2 with lines title "PV1 (A)", \
     datafile using 1:4 axes x1y2 with lines title "PV2 (A)" \

