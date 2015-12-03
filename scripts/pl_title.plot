# Standard title.

# Depends on:
#  mytitle (script)
#  datafile (pl_params.plot)

# The date is fetched from the datafile, col 0 or 1, depending on dateindex.
if ( !exists("dateindex") ) {
    today = `perl -an -F, -e 'eof && do { print q{"},$F[0],q{"};exit }' @datafile`
}
else {
    today = `perl -an -F, -e 'eof && do { print q{"},$F[1],q{"};exit }' @datafile`
}

# Non-final graphs have the last time included.
if ( exists("final") && final > 0 ) {
  today = strptime( '%Y-%m-%d %H:%M:%S', today )
  set title mytitle . strftime( " %A %d %B %Y", today )
}
else {
  today = strptime( '%Y-%m-%d %H:%M:%S', today )
  set title mytitle . strftime( " %A %d %B %Y, %H:%M:%S", today )
}
