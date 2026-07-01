#!/bin/sh
### BEGIN INIT INFO
# Provides:          nginx
# Required-Start:    $local_fs $remote_fs $network
# Required-Stop:     $local_fs $remote_fs $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: nginx
### END INIT INFO
# Minimal SysV shim so `service nginx <action>` works in a container that has no
# systemd (the noble nginx package ships only a systemd unit). `service` falls
# back to /etc/init.d/nginx when /run/systemd/system is absent.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
NGINX=/usr/sbin/nginx
PIDFILE=/run/nginx.pid

running() {
  [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

case "$1" in
  start)
    running || $NGINX
    ;;
  stop)
    running && $NGINX -s quit
    ;;
  reload|force-reload)
    if running; then $NGINX -s reload; else $NGINX; fi
    ;;
  restart)
    # reload-if-running avoids a port-80 race between quit and re-start
    if running; then $NGINX -s reload; else $NGINX; fi
    ;;
  status)
    if running; then echo "nginx running"; else echo "nginx not running"; exit 3; fi
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|reload|status}" >&2
    exit 1
    ;;
esac
