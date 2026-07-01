#!/bin/bash
# Passenger's watchdog needs its instance-registry dir to pre-exist; /run is a
# plain dir here (no systemd tmpfs), so create it before starting nginx.
mkdir -p /var/run/passenger-instreg
nginx
exec /usr/sbin/sshd -D
