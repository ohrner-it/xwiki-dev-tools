#!/usr/bin/env sh
# Uses "local", which dash (/bin/sh on Debian and Ubuntu) and bash both support.
# shellcheck shell=dash
#
# xwiki-dev.sh - start/restart/stop a local XWiki dev server with readiness polling
#
# Works on an installation created with create-dev-xwiki.sh (or any XWiki Jetty/HyperSQL
# distribution). Starting and stopping is left to the distribution's own start_xwiki.sh and
# stop_xwiki.sh; this script runs them in the background, keeps their output in a log file, and
# waits until XWiki actually answers - which takes a minute or more after the process has started.
#
# Run it with --help for the usage.

set -u

usage() {
  echo "Usage: $0 [--dir <INSTALLATION>] [--port <PORT>] [--timeout <SECONDS>] <COMMAND>"
  echo
  echo "Commands:"
  echo "  start     Start XWiki in the background and wait until it answers. Does nothing but wait"
  echo "            if it is already running."
  echo "  stop      Stop XWiki."
  echo "  restart   Stop XWiki, then start it again - on the same port, unless --port says otherwise."
  echo "  status    Tell whether XWiki is running and ready. Exit code 0 if ready, 1 if it is still"
  echo "            starting, 3 if it is not running."
  echo "  log       Show the end of the log. Add -f to follow it."
  echo
  echo "Options:"
  echo "  --dir <INSTALLATION>  The XWiki installation folder. Default: \$XWIKI_DEV_HOME if set,"
  echo "                        otherwise the current directory."
  echo "  --port <PORT>         HTTP port to start XWiki on. Default: \$XWIKI_DEV_PORT if set,"
  echo "                        otherwise 8080. XWiki also listens on the port below it, for the"
  echo "                        stop command, so keep installations that run at the same time at"
  echo "                        least two ports apart (e.g. 8080 and 8090)."
  echo "                        An installation runs only once at a time, so the other commands"
  echo "                        find the port of a running XWiki by themselves."
  echo "  --timeout <SECONDS>   How long start waits for XWiki to answer. Default: 300."
  echo "  -h, --help            Show this help."
}

# Fails with a message if the option given first has no value.
requireValue() {
  if [ "$2" -lt 2 ]; then
    echo >&2 "Error: $1 needs a value."
    exit 2
  fi
}

# Fails with a message unless the value of the option given first is a number.
requireNumber() {
  case "$2" in
    ''|*[!0-9]*) echo >&2 "Error: $1 must be a number, not \"$2\"."; exit 2 ;;
  esac
}

installationDir="${XWIKI_DEV_HOME:-.}"
requestedPort="${XWIKI_DEV_PORT:-8080}"
portGiven=false
[ -n "${XWIKI_DEV_PORT:-}" ] && portGiven=true
timeout=300
command=""
follow=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) requireValue "$1" "$#"; installationDir="$2"; shift 2 ;;
    --port) requireValue "$1" "$#"; requestedPort="$2"; portGiven=true; shift 2 ;;
    --timeout) requireValue "$1" "$#"; timeout="$2"; shift 2 ;;
    -f) follow=true; shift ;;
    -h|--help) usage; exit 0 ;;
    start|stop|restart|status|log) command="$1"; shift ;;
    *) echo >&2 "Error: Unknown argument \"$1\"."; echo >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$command" ]; then
  usage >&2
  exit 2
fi

requireNumber --port "$requestedPort"
requireNumber --timeout "$timeout"

if ! [ -x "$installationDir/start_xwiki.sh" ]; then
  echo >&2 "Error: \"$installationDir\" is not an XWiki installation (it has no start_xwiki.sh)."
  echo >&2 "Pass --dir, set XWIKI_DEV_HOME, or run this from the installation folder."
  exit 2
fi

installationDir=$(CDPATH='' cd -- "$installationDir" && pwd -P)

# --- Functions ---------------------------------------------------------------

# Sets the port and the values derived from it.
usePort() {
  port="$1"
  stopPort=$((port - 1))
  baseUrl="http://localhost:$port/xwiki"
  readyUrl="$baseUrl/bin/view/Main/WebHome"
  logFile="$installationDir/logs/xwiki-$port.log"
}

# Tells whether the process is the XWiki of this installation. A lock file left behind by a crash
# or a power cut can hold the id of a process that has since been reused by something else
# entirely, and that must neither be reported as XWiki nor be stopped.
#
# start_xwiki.sh runs Jetty's start.jar from the installation, with the path it was itself called
# by - absolute when started by this script. Started by hand as ./start_xwiki.sh, the path is
# relative, and the process's working directory, which start_xwiki.sh sets to the installation,
# decides instead (Linux only).
isOurXWiki() {
  local args

  args=$(ps -o args= -p "$1" 2>/dev/null) || return 1
  case "$args" in
    *"$installationDir/jetty/start.jar"*) return 0 ;;
    *start.jar*) [ "$(readlink "/proc/$1/cwd" 2>/dev/null)" = "$installationDir" ] ;;
    *) return 1 ;;
  esac
}

# Prints "<port> <pid>" of the running XWiki of this installation, if there is one.
#
# start_xwiki.sh writes the process id into tmp/xwiki-<port>.lck and removes the file once the
# process has ended. An installation can only run once at a time - its HyperSQL database is locked
# by the running instance - so the port it runs on is taken from that file rather than from the
# command line.
findRunning() {
  local lockFile lockPort pid

  for lockFile in "$installationDir"/tmp/xwiki-*.lck; do
    [ -f "$lockFile" ] || continue
    pid=$(cat "$lockFile")
    if [ -n "$pid" ] && isOurXWiki "$pid"; then
      lockPort="${lockFile##*/xwiki-}"
      echo "${lockPort%.lck} $pid"
      return 0
    fi
  done
  return 1
}

# Sets pid, and the port of the running XWiki. Without a running XWiki it returns 1 and leaves the
# port alone.
runningPid() {
  local running

  pid=""
  running=$(findRunning) || return 1
  usePort "${running% *}"
  pid="${running#* }"
}

# The first request after a start takes a while to answer, because the page is rendered for the
# first time; the time limit keeps a hanging server from blocking the caller past --timeout.
isReady() {
  [ "$(curl -s -o /dev/null --max-time 60 -w '%{http_code}' "$readyUrl")" = "200" ]
}

# curl exits with 7 when nothing accepts the connection. Anything else means some process is
# listening on the port.
portInUse() {
  curl -s -o /dev/null --max-time 5 "http://localhost:$1/"
  [ "$?" -ne 7 ]
}

# Serialises start and stop, so that several callers - people, scripts, coding agents - acting on
# the same installation at the same time do not start it twice. flock is part of util-linux; where
# it is missing, the commands run without the lock.
lockInstallation() {
  [ -x "$(command -v flock)" ] || return 0
  mkdir -p "$installationDir/tmp"
  exec 9> "$installationDir/tmp/xwiki-dev.lock"
  flock 9
}

waitUntilReady() {
  local startTime waited

  startTime=$(date +%s)
  echo "Waiting for XWiki to answer at $readyUrl (up to ${timeout}s)..."

  until isReady; do
    if ! kill -0 "$pid" 2>/dev/null; then
      [ -t 1 ] && echo
      echo >&2 "Error: XWiki exited during startup. The end of $logFile:"
      tail -n 30 "$logFile" >&2
      return 1
    fi

    waited=$(( $(date +%s) - startTime ))
    if [ "$waited" -ge "$timeout" ]; then
      [ -t 1 ] && echo
      echo >&2 "Error: XWiki (PID $pid) did not answer within ${timeout}s. It is still running - check $logFile."
      return 1
    fi

    sleep 2
    [ -t 1 ] && printf '.'
  done

  [ -t 1 ] && echo
  waited=$(( $(date +%s) - startTime ))
  echo "XWiki is ready at $baseUrl (PID $pid, after ${waited}s)."
  return 0
}

start() {
  if runningPid; then
    if [ "$portGiven" = true ] && [ "$port" != "$requestedPort" ]; then
      echo >&2 "Error: XWiki is already running on port $port (PID $pid). Stop it before starting it on port $requestedPort."
      return 1
    fi
    echo "XWiki is already running on port $port (PID $pid)."
    waitUntilReady
    return
  fi

  # Without --port, a restart comes back on the port XWiki was running on.
  [ "$portGiven" = true ] && usePort "$requestedPort"

  # Jetty fails to bind a port that is taken but the JVM keeps running, so XWiki would seem to
  # start while every request goes to whatever else holds the port.
  if portInUse "$port"; then
    echo >&2 "Error: Port $port is in use by another process. Stop it, or pass a different --port."
    return 1
  fi
  if portInUse "$stopPort"; then
    echo >&2 "Error: Port $stopPort, which XWiki listens on for the stop command, is in use by another process. Pass a different --port."
    return 1
  fi

  # A lock file still there belongs to an XWiki that has ended without removing it, or holds a
  # process id reused since. start_xwiki.sh would take the latter for a running XWiki and refuse.
  rm -f "$installationDir/tmp/xwiki-$port.lck"

  mkdir -p "$(dirname "$logFile")"
  echo "Starting XWiki from $installationDir on port $port, logging to $logFile..."

  # The server gets a session of its own, so it is not stopped along with the shell or the tool
  # that happened to start it. It must not inherit the descriptor of the start/stop lock either,
  # or the lock would be held for as long as XWiki runs.
  if [ -x "$(command -v setsid)" ]; then
    setsid "$installationDir/start_xwiki.sh" -ni -p "$port" -sp "$stopPort" > "$logFile" 2>&1 < /dev/null 9>&- &
  else
    nohup "$installationDir/start_xwiki.sh" -ni -p "$port" -sp "$stopPort" > "$logFile" 2>&1 < /dev/null 9>&- &
  fi

  # start_xwiki.sh writes the lock file just before it replaces itself with the JVM.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    runningPid && break
    sleep 1
  done

  if [ -z "$pid" ]; then
    echo >&2 "Error: XWiki did not start. The end of $logFile:"
    tail -n 30 "$logFile" >&2
    return 1
  fi

  waitUntilReady
}

# stop_xwiki.sh sends Jetty the stop command and, if XWiki does not end, kills it - first gently,
# then with SIGKILL. Its output is added to the log, where it is found along with the server's.
stop() {
  if ! runningPid; then
    echo "XWiki is not running."
    return 0
  fi

  echo "Stopping XWiki (PID $pid)..."
  "$installationDir/stop_xwiki.sh" -p "$port" -sp "$stopPort" -wt 30 >> "$logFile" 2>&1 9>&-

  if kill -0 "$pid" 2>/dev/null; then
    echo >&2 "Error: XWiki (PID $pid) could not be stopped. The end of $logFile:"
    tail -n 10 "$logFile" >&2
    return 1
  fi

  echo "Stopped."
}

status() {
  if ! runningPid; then
    echo "XWiki is not running."
    return 3
  fi

  if isReady; then
    echo "XWiki is running and ready at $baseUrl (PID $pid)."
    return 0
  fi

  echo "XWiki is running (PID $pid) but not ready yet at $baseUrl."
  return 1
}

log() {
  runningPid

  if ! [ -f "$logFile" ]; then
    echo >&2 "There is no log at $logFile yet."
    return 1
  fi

  if [ "$follow" = true ]; then
    tail -n 100 -f "$logFile"
  else
    tail -n 100 "$logFile"
  fi
}

# --- Entry point -------------------------------------------------------------

usePort "$requestedPort"

case "$command" in
  start) lockInstallation; start ;;
  stop) lockInstallation; stop ;;
  restart) lockInstallation; stop && start ;;
  status) status ;;
  log) log ;;
esac
