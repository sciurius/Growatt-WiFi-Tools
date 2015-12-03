# Command line parameters.

# Term.
if ( ! exists("term") ) term = "png";

# Dimensions.
if ( ! exists("xwidth") ) xwidth = 960;
if ( ! exists("xheight") ) xheight = 360;

# Input/outout files.
if ( ! exists("imagefile") ) imagefile = 'current.' . term
set output imagefile
if ( ! exists("datafile") ) datafile = 'current.csv'
if ( ! exists("solarfile") ) solarfile = '../../Growatt/data/current.csv'
havesolarfile = `perl -e 'print 0 + -s shift' @solarfile`
