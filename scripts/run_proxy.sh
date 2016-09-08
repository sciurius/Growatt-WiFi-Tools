#!/bin/sh

lib=$HOME/wrk/Growatt

while [ a = a ]
do
    logfile=`date "+%Y%m%d.log"`
    # Remove --remote for standalone server.
    perl $lib/scripts/growatt_server.pl --debug --remote >>$logfile  2>&1
    if [ $? != 0 ]
    then
	sleep 60
    fi
done
