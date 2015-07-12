#!/bin/sh

lib=$HOME/wrk/Growatt
logfile=`date "+%Y%m%d%H%M%S.log"`

while [ a = a ]
do
    perl $lib/scripts/growatt_proxy.pl --debug >>$logfile  2>&1
    if [ $? != 0 ]
    then
	sleep 60
	# logfile=`date "+%Y%m%d%H%M%S.log"`
    fi
done
