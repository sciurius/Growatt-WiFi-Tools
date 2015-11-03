# Produce PNG images.

# Usage:
#
#   cd data	# where daily.csv lives
#   gnuplot ../scripts/growatt_data.plot
#
# Alternatively:
#
#   gnuplot -e 'datafile="data/daily.csv";imagefile="here/plot.png" growatt_daily.plot

if ( ! exists("term") ) term = "png";
set term term size 960,400;

# Allow setting of imagefile on the command line.
if ( ! exists("imagefile") ) imagefile = 'current_plot%d.' . term
imagecnt = 0;

# Horizontal axis: time
set xdata time

# Left vertical axis: Power.
set autoscale y
set format y "%g kWh"

# Input time format from CSV file.
set timefmt '%Y-%m-%d'
set locale ""

set macros
# Allow setting of datafile on the command line.
if ( ! exists("datafile") ) datafile = 'daily.csv'
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
set xtics mstart,daysecs,mend format "%1d" time
unset mxtics
set key below

t1 = strftime("%B %Y",strptime('%Y-%m-%d',mstart))
t2 = strftime("%B %Y",strptime('%Y-%m-%d',mend))
if ( t1 eq t2 ) {
   set title t1
}
else {
   set title t1 . " — " . t2
}
set xtics font "Liberation Sans Narrow,12";

plot datafile \
     using "Time":"Eac" \
     with boxes lc rgb 'red' title "Eac (kWh)", \
     '' \
     using "Time":(column("Epv2")+column("Epv1")) \
     with boxes lc rgb 'green' title "PV2 (kWh)", \
     '' \
     using "Time":"Epv1" \
     with boxes lc rgb 'yellow' title "PV1 (kWh)"
