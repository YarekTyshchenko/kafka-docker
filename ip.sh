#!/bin/bash

/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print "host.name="$1}' >> $KAFKA_HOME/config/server.properties;