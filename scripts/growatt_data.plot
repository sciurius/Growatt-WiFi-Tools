# Produce PNG images.

# Usage:
#
#   cd data	# where current.csv lives
#   gnuplot ../scripts/growatt_data.plot
#
# Alternatively:
#
#   gnuplot -e 'datafile="data/20150704.csv";imagefile="here/plot.png" growatt_data.plot

set term png size 1024,600;

# Allow setting of imagefile on the command line.
if ( ! exists("imagefile") ) imagefile = 'current_plot%d.png'
imagecnt = 0;

# Horizontal axis: time
set xdata time

# Left vertical axis: Power. My plant is 7kW max.
set yrange [ 0:7 ]
set format y "%g kW"

# Input time format from CSV file.
set timefmt '%H:%M:%S'
# Output time format ( x-axis).
set format x "%H:%M"

# Extract the current date from row 2, col 1.
set macros
# Allow setting of datafile on the command line.
if ( ! exists("datafile") ) datafile = 'current.csv'
set datafile separator ","
today = `perl -an -F, -e '$. == 2 && do { print q{"},$F[0],q{"};exit }' @datafile`
today = strptime( "%d-%m-%Y", today )

# Column definitions in CSV data file.
ix = 1;
F_SampleDate	= ix; ix = ix + 1;
F_SampleTime	= ix; ix = ix + 1;
F_DataLoggerId	= ix; ix = ix + 1;
F_InverterId	= ix; ix = ix + 1;
F_InvStat	= ix; ix = ix + 1;
F_InvStattxt	= ix; ix = ix + 1;
F_Ppv		= ix; ix = ix + 1;
F_Vpv1		= ix; ix = ix + 1;
F_Ipv1		= ix; ix = ix + 1;
F_Ppv1		= ix; ix = ix + 1;
F_Vpv2		= ix; ix = ix + 1;
F_Ipv2		= ix; ix = ix + 1;
F_Ppv2		= ix; ix = ix + 1;
F_Pac		= ix; ix = ix + 1;
F_Fac		= ix; ix = ix + 1;
F_Vac1		= ix; ix = ix + 1;
F_Iac1		= ix; ix = ix + 1;
F_Pac1		= ix; ix = ix + 1;
F_Vac2		= ix; ix = ix + 1;
F_Iac2		= ix; ix = ix + 1;
F_Pac2		= ix; ix = ix + 1;
F_Vac3		= ix; ix = ix + 1;
F_Iac3		= ix; ix = ix + 1;
F_Pac3		= ix; ix = ix + 1;
F_E_Today	= ix; ix = ix + 1;
F_E_Total	= ix; ix = ix + 1;
F_Tall		= ix; ix = ix + 1;
F_Tmp		= ix; ix = ix + 1;
F_ISOF		= ix; ix = ix + 1;
F_GFCIF		= ix; ix = ix + 1;
F_DCIF		= ix; ix = ix + 1;
F_Vpvfault	= ix; ix = ix + 1;
F_Vacfault	= ix; ix = ix + 1;
F_Facfault	= ix; ix = ix + 1;
F_Tmpfault	= ix; ix = ix + 1;
F_Faultcode	= ix; ix = ix + 1;
F_IPMtemp	= ix; ix = ix + 1;
F_Pbusvolt	= ix; ix = ix + 1;
F_Nbusvolt	= ix; ix = ix + 1;
F_Epv1today	= ix; ix = ix + 1;
F_Epv1total	= ix; ix = ix + 1;
F_Epv2today	= ix; ix = ix + 1;
F_Epv2total	= ix; ix = ix + 1;
F_Epvtotal	= ix; ix = ix + 1;
F_Rac		= ix; ix = ix + 1;
F_ERactoday	= ix; ix = ix + 1;
F_ERactotal	= ix; ix = ix + 1;

set title strftime( "%A, %d %B %Y", today )
set ytics nomirror
set grid xtics ytics

#### Plot power and the Ppv the individual strings.

# Right vertical axis: Accum. power for this day.
set output sprintf( imagefile, imagecnt ); imagecnt = imagecnt + 1

u0 = "using " . F_SampleTime . ":(\$" . F_Ppv     . "/1000)";
u1 = "using " . F_SampleTime . ":(\$" . F_Ppv1    . "/1000)";
u2 = "using " . F_SampleTime . ":(\$" . F_Ppv2    . "/1000)";
u3 = "using " . F_SampleTime . ":(\$" . F_E_Today . "/1000)";

set format y2 "%g kW"
set y2tics
set autoscale y2
set key left

plot datafile @u0     with lines lw 2 title "Power (kW)", \
     '' @u1           with lines title "PV1 (kW)", \
     '' @u2           with lines title "PV2 (kW)", \
     '' @u3 axes x1y2 with lines lw 3 title "Cum. (kW)"

