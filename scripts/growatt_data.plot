#! gnuplot

mytitle = "Zonnepanelen"

load 'pl_std.plot'
load 'pl_params.plot'
load 'pl_term.plot'
load 'pl_x_hours.plot'
dateindex = 1
load 'pl_title.plot'

# Left vertical axis: Power. My plant is 7kW max.
set yrange [ 0:7 ]
set format y "%g kW"
set grid xtics ytics

# Right vertical axis: Accum. power for this day.
set format y2 "%g kWh"
set y2tics
set y2range [0:*]

set key inside left reverse Left

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

