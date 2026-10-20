#!/bin/bash
# Starts IRIS, then (in background) loads the knowledge base and starts the production.
(
  for i in $(seq 1 60); do
    bash -c "cat < /dev/null > /dev/tcp/localhost/1972" 2>/dev/null && break
    sleep 2
  done
  sleep 5
  printf 'zn "SOLAR"\ndo ##class(SolarAgents.Setup.Installer).Startup()\nhalt\n' > /tmp/demo-startup.script
  /usr/irissys/bin/irissession IRIS < /tmp/demo-startup.script > /tmp/demo-startup.log 2>&1
  cat /tmp/demo-startup.log
) &
exec /iris-main "$@"
