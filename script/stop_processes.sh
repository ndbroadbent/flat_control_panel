#!/bin/sh
pid=$(pgrep -f 'octopus_sinatra'); if [ $pid ]; then sudo kill -9 $pid; fi
pid=$(pgrep -f 'octopus_daemon');  if [ $pid ]; then sudo kill -9 $pid; fi
pid=$(pgrep -f 'weather_daemon');  if [ $pid ]; then sudo kill -9 $pid; fi

