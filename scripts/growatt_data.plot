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
set term term size 960,540;
set lmargin 10
set rmargin 10
set locale ""

# Allow setting of imagefile on the command line.
if ( ! exists("imagefile") ) imagefile = 'current_plot%d.' . term
imagecnt = 0;

# Horizontal axis: time
set xdata time

# Left vertical axis: Power. My plant is 7kW max.
set yrange [ 0:7 ]
set format y "%g kW"

# Input time format from CSV file.
set timefmt '%Y-%m-%d %H:%M:%S'
# Output time format ( x-axis).
set format x "%H:%M"

# Extract the current date from row 2, col 1.
set macros
# Allow setting of datafile on the command line.
if ( ! exists("datafile") ) datafile = 'current.csv'
set datafile separator ","
if ( exists("final") ) {
  today = `perl -an -F, -e '$. == 2 && do { print q{"},$F[1],q{"};exit }' @datafile`
  today = strptime( '%Y-%m-%d %H:%M:%S', today )
  set title strftime( "Zonnepanelen %A %d %B %Y", today )
}
else {
  today = `perl -an -F, -e 'eof && do { print q{"},$F[1],q{"};exit }' @datafile`
  today = strptime( '%Y-%m-%d %H:%M:%S', today )
  set title strftime( "Zonnepanelen %A %d %B %Y, %H:%M:%S", today )
}
set ytics nomirror
set grid xtics ytics

#### Plot power and the Ppv the individual strings.

# Right vertical axis: Accum. power for this day.
set output sprintf( imagefile, imagecnt ); imagecnt = imagecnt + 1

set format y2 "%g kWh"
set y2tics
set y2range [0:*]
set key left reverse Left

# The daily accum values are not useful, since they are reset during
# the day. So use the total energy and subtract the initial value.
E_init = `perl -an -F, -e '$. == 2 && do { print $F[23];exit }' @datafile`

plot datafile \
    using "Time":(column("Eac_total(kWh)")-E_init) \
        axes x1y2  with lines lw 3 title "Totaal opgewekte energie (kWh)", \
    '' using "Time":(column("Ppv1(W)")/1000)+(column("Ppv2(W)")/1000) \
	with lines lw 2 title "Opgewekt vermogen (kW)", \
    '' using "Time":(column("Ppv1(W)")/1000) \
        with lines title "Opgewekt door PV1 (kW)", \
    '' using "Time":(column("Ppv2(W)")/1000) \
        with lines title "Opgewekt door PV2 (kW)"

