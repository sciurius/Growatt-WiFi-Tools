# Produce PNG images.

set term png size 1024,600;
imagefile = 'current_plot%d.png'
imagecnt = 1;

# Horizontal axis: time
set xdata time

# Left vertical axis: Power. My plant is 7kW max.
set yrange [ 0:7 ]
set format y "%g kW"

# Input time format.
set timefmt '%H:%M:%S'
# Output date format.
set format x "%H:%M"

# Extract the current date from row 2, col 1.
set macros
datafile = 'current_plot.csv'
set datafile separator ","
today = `perl -an -F, -e '$. == 2 && do { print q{"},$F[0],q{"};exit }' @datafile`

# Need to make more friendly. Later.
# set title strftime( "%A, %d %B %Y", today )
set title today
set ytics nomirror
set grid xtics ytics y2tics

#### Plot power and the current of the individual strings.

# Right vertical axis: Current per PV.
set y2range [ 0:14 ]
set format y2 "%g A"
set y2tics
set output sprintf( imagefile, imagecnt ); imagecnt = imagecnt + 1

plot datafile using 2:($7/1000)   with lines title "Power (kW)", \
     datafile using 2:9 axes x1y2 with lines title "PV1 (A)", \
     datafile using 2:12 axes x1y2 with lines title "PV2 (A)" \

#### Plot power and temperature.

# Right vertical axis: Temperature.
set y2range [ 0:70 ]
set format y2 "%g ⁰C"
set y2tics
set output sprintf( imagefile, imagecnt ); imagecnt = imagecnt + 1

plot datafile using 2:($7/1000)   with lines title "Power (kW)", \
     datafile using 2:28 axes x1y2 with lines title "Temp (⁰C)" \

# Right vertical axis: Temperature.
set y2range [ 0:70 ]
set format y2 "%g kW"
set y2tics
set autoscale
set output sprintf( imagefile, imagecnt ); imagecnt = imagecnt + 1

plot datafile using 2:($7/1000)   with lines title "Power (kW)", \
     datafile using 2:($25/1000) axes x1y2 with lines title "Daily total (kW)" \
