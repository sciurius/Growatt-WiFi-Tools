#!/bin/sh

lib=$HOME/wrk/Growatt

while [ a = a ]
do
    logfile=`date "+%Y%m%d.log"`
    perl $lib/scripts/growatt_proxy.pl --debug >>$logfile  2>&1
    if [ $? != 0 ]
    then
	sleep 60
    fi
done
