#!/bin/bash

while true
do
    sleep 5
    if docker-compose run metalctl switch ls | grep ● > /dev/null; then
      break
    fi
done