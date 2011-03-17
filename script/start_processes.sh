#!/bin/sh
this_dir=$(cd `dirname $0` && pwd)
nohup ruby $this_dir/../octopus_sinatra.rb -p 80 > /dev/null 2>&1 &
sleep 10
nohup ruby $this_dir/../octopus_daemon.rb > /dev/null 2>&1 &
nohup ruby $this_dir/../weather_daemon.rb > /dev/null 2>&1 &

