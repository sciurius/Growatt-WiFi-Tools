#! gnuplot

mytitle = "Zonnepanelen"

load 'pl_std.plot'
load 'pl_params.plot'
load 'pl_term.plot'
load 'pl_x_days.plot'
load 'pl_title_d.plot'

# Left vertical axis: Power.
set autoscale y
set format y "%g kWh"

# Right vertical axis: Accumulated values.
set autoscale y2
set format y2 "%g kWh"
set y2tics

set key maxrows 1 samplen 2 width -1

plot datafile \
     using "Time":(column("Epv2")+column("Epv1")) \
     with boxes lc rgb '#e69f00' title "PV2", \
     '' \
     using "Time":"Epv1" \
     with boxes lc rgb '#56b4e9' title "PV1", \
     '' \
     using "Time":"Epv_total" \
     axes x1y2 with lines lc 'black' title "Cumulatief PV", \
     '' \
     using "Time":"Eac_total" \
     axes x1y2 with lines lc 'blue' title "Cumulatief AC", \
     '' \
     using "Time":(column("YpvResult")==0?NaN:(column("YpvResult"))) \
     axes x1y2 with lines lc 'red' title "PV Jaar", \
     '' \
     using "Time":(column("YacResult")==0?NaN:(column("YacResult"))) \
     axes x1y2 with lines lc 'green' title "AC Jaar", \
