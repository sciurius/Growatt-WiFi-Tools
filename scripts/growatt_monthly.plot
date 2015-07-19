# Produce PNG images.

# Usage:
#
#   cd data	# where current.csv lives
#   gnuplot ../scripts/growatt_data.plot
#
# Alternatively:
#
#   gnuplot -e 'datafile="data/20150704.csv";imagefile="here/plot.png" growatt_data.plot

if ( ! exists("term") ) term = "png";
set term term size 1024,300;
set locale ""

# Allow setting of imagefile on the command line.
if ( ! exists("imagefile") ) imagefile = 'current_plot%d.' . term
imagecnt = 0;

# Horizontal axis: time
set xdata time

# Left vertical axis: Power. My plant is 7kW max.
set autoscale y
set format y "%g kWh"

# Input time format from CSV file.
set timefmt '%Y-%m-%d'
# Output time format ( x-axis).
set format x "%d"

set macros
# Allow setting of datafile on the command line.
if ( ! exists("datafile") ) datafile = 'monthly.csv'
set datafile separator ","
set ytics nomirror
set xtics nomirror
set grid ytics
set output sprintf( imagefile, imagecnt ); imagecnt = imagecnt + 1

set key inside top center maxrows 1
set boxwidth 0.8  relative
set style fill solid border -1
daysecs = 86400

# Extract the start date from row 2, col 0.
mstart = `perl -an -e '$. == 2 && do { print q{"},$F[0],q{"};exit }' @datafile`
# Extract the end date from last row, col 0.
mend = `perl -an -e 'eof && do { print q{"},$F[0],q{"};exit }' @datafile`

# Range and ticks.
set xrange [ strptime('%Y-%m-%d',mstart)-daysecs:strptime('%Y-%m-%d',mend)+daysecs]
set xtics mstart,daysecs,mend
unset mxtics

set title strftime("%B %Y",strptime('%Y-%m-%d',mend))

plot datafile \
     using "Time":"Eac" \
     with boxes lc rgb 'red' title "Eac (kWh)", \
     '' \
     using "Time":(column("Epv2")+column("Epv1")) \
     with boxes lc rgb 'green' title "PV2 (kWh)", \
     '' \
     using "Time":(column("Epv1")) \
     with boxes lc rgb 'yellow' title "PV1 (kWh)"
