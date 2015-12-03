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

plot datafile \
     using "Time":"Eac" \
     with boxes lc rgb 'red' title "Eac (kWh)", \
     '' \
     using "Time":(column("Epv2")+column("Epv1")) \
     with boxes lc rgb 'green' title "PV2 (kWh)", \
     '' \
     using "Time":"Epv1" \
     with boxes lc rgb 'yellow' title "PV1 (kWh)"
