#!/bin/sh

lib=$HOME/wrk/Growatt

while [ a = a ]
do
    perl $lib/scripts/growatt_proxy.pl --debug > `date "+%Y%m%d%H%M%S.log"` 2>&1 || sleep 60
done
