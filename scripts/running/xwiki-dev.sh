#!/bin/bash
#
# xwiki-dev.sh - start/restart/stop a local XWiki dev server with readiness polling
#
# Usage:
#   ./xwiki-dev.sh start
#   ./xwiki-dev.sh restart
#   ./xwiki-dev.sh stop
#   ./xwiki-dev.sh status
#
# Adjust the variables below to match your setup.

set -u

# --- Configuration ---------------------------------------------------------

# Path to your XWiki start script (e.g. the standalone distribution's start_xwiki.sh)
START_CMD="./start_xwiki.sh"

# URL XWiki should answer with HTTP 200 once fully initialized
READY_URL="http://localhost:8080/xwiki/bin/view/Main/WebHome"

# Where to keep logs and the PID file (adjust if /tmp is wiped between reboots
# and you want this to survive)
LOGFILE="/tmp/xwiki-dev.log"
PIDFILE="/tmp/xwiki-dev.pid"

# Max seconds to wait for readiness before giving up
TIMEOUT=180

# --- Functions ---------------------------------------------------------------

start() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "XWiki already running with PID $(cat "$PIDFILE")."
    exit 0
  fi

  echo "Starting XWiki..."
  nohup $START_CMD > "$LOGFILE" 2>&1 &
  XWIKI_PID=$!
  echo "$XWIKI_PID" > "$PIDFILE"
  echo "XWiki starting with PID $XWIKI_PID, logs at $LOGFILE"

  echo "Waiting for XWiki to come up and finish initializing..."
  START_TIME=$(date +%s)
  SECONDS_WAITED=0
  until curl -s -o /dev/null -w "%{http_code}" "$READY_URL" | grep -q "200"; do
    if ! kill -0 "$XWIKI_PID" 2>/dev/null; then
      echo ""
      echo "XWiki process exited unexpectedly. Check $LOGFILE"
      rm -f "$PIDFILE"
      exit 1
    fi

    if [ "$SECONDS_WAITED" -ge "$TIMEOUT" ]; then
      echo ""
      echo "Timed out after ${TIMEOUT}s waiting for $READY_URL to return 200."
      echo "XWiki process (PID $XWIKI_PID) is still running, check $LOGFILE."
      exit 1
    fi

    sleep 1
    SECONDS_WAITED=$((SECONDS_WAITED + 1))
    echo -n "."
  done

  echo ""
  END_TIME=$(date +%s)
  ELAPSED=$((END_TIME - START_TIME))
  echo "XWiki is up and initialized (PID $XWIKI_PID) after ${ELAPSED}s."
}

stop() {
  if [ ! -f "$PIDFILE" ]; then
    echo "XWiki is not running (no PID file at $PIDFILE)."
    return 0
  fi

  PID=$(cat "$PIDFILE")
  if kill -0 "$PID" 2>/dev/null; then
    echo "Stopping XWiki (PID $PID)..."
    kill "$PID"

    # wait a bit for graceful shutdown
    for _ in $(seq 1 30); do
      if ! kill -0 "$PID" 2>/dev/null; then
        break
      fi
      sleep 1
    done

    if kill -0 "$PID" 2>/dev/null; then
      echo "XWiki did not stop gracefully, forcing kill..."
      kill -9 "$PID"
    fi

    echo "Stopped."
  else
    echo "Process $PID not running, removing stale PID file."
  fi

  rm -f "$PIDFILE"
}

restart() {
  stop
  start
}

status() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "XWiki is running with PID $(cat "$PIDFILE")."
  else
    echo "XWiki is not running."
  fi
}


# --- Entry point -------------------------------------------------------------

case "${1:-}" in
  start)   start ;;
  stop)    stop ;;
  restart) restart ;;
  status)  status ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac

