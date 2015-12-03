# Standard settings for plots with a hours on the x-axis.

# Horizontal axis: Time.
set xdata time
set format x "%H:%M"

# Override time format of CSV file.
set timefmt '%Y-%m-%d %H:%M:%S'

# Key usually goes below.
set key outside maxrows 1 below
