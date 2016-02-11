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
     with boxes lc rgb 'green' title "PV2", \
     '' \
     using "Time":"Epv1" \
     with boxes lc rgb 'yellow' title "PV1", \
     '' using "Time":"Epv_total" axes x1y2 with lines lc 'green' title "Totaal Epv", \
