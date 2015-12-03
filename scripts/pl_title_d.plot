t1 = strftime("%B %Y",strptime('%Y-%m-%d',mstart))
t2 = strftime("%B %Y",strptime('%Y-%m-%d',mend))
if ( t1 eq t2 ) {
   set title mytitle . " " . t1
}
else {
   set title mytitle . " " . t1 . " — " . t2
}
