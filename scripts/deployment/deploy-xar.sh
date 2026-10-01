#!/usr/bin/env sh
# Uses "local" and "test -nt", which dash (/bin/sh on Debian and Ubuntu) and bash both support.
# shellcheck shell=dash

# Script to build the xar deployment artifact and automatically deploy it on the dev server.

set -u

usage() {
  echo "Script will build the XWiki xar file and deploy it on the development server"
  echo
  echo "Usage:"
  echo "  sh $0 [OPTIONS] [<USERNAME>:<PASSWORD>] [<REST_ENTRY_POINT>] [-- <MAVEN_ARGUMENTS>]"
  echo
  echo "  <USERNAME>:<PASSWORD>  Credentials of an XWiki account allowed to import pages. Without them,"
  echo "                         they are taken from ~/.netrc, or from the file given with --netrc-file."
  echo "                         Prefer a netrc file: arguments are visible to other users in the"
  echo "                         process list for as long as the build and the deployment take."
  echo "  <REST_ENTRY_POINT>     Default: http://localhost:8080/xwiki/rest"
  echo "  <MAVEN_ARGUMENTS>      Passed on to Maven, e.g. -DskipTests."
  echo
  echo "Options:"
  echo "  --netrc-file <FILE>    Read the credentials from this netrc file."
  echo "  --wiki <WIKI>          Wiki to import into. Default: xwiki (the main wiki)."
  echo "  --no-build             Deploy the xar file in ./target as it is, without building it first."
  echo "  -h, --help             Show this help."
  echo
  echo "Run it in the folder of the Maven module that builds the xar. In a module of a multi-module"
  echo "project, the modules it depends on are built along with it (\"mvn -pl <module> -am package\")."
  echo
  echo "The pages are imported as they are, without the Extension Manager: Java code is not deployed,"
  echo "and the Extension Manager does not learn about the new pages. To install an extension, also a"
  echo "new build of one that is installed already, use deploy-extension.sh."
  echo
  echo "Examples:"
  echo "  sh $0"
  echo "  sh $0 -- -DskipTests"
  echo "  sh $0 Admin:admin http://localhost:8080/xwiki/rest"
  echo "  sh $0 --netrc-file ~/.netrc-xwiki http://localhost:8081/xwiki/rest"
}

credentials=""
netrcFile=""
restEntryPoint="http://localhost:8080/xwiki/rest"
wiki="xwiki"
build=true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --netrc-file|--wiki)
      if [ "$#" -lt 2 ]; then
        echo >&2 "Error: $1 needs a value."
        exit 1
      fi ;;
  esac
  case "$1" in
    --) shift; break ;;
    --netrc-file) netrcFile="$2"; shift 2 ;;
    --wiki) wiki="$2"; shift 2 ;;
    --no-build) build=false; shift ;;
    -h|--help) usage; exit 0 ;;
    http://*|https://*) restEntryPoint="${1%/}"; shift ;;
    -*) echo >&2 "Error: Unknown option \"$1\" - Maven arguments go after \"--\"."; echo >&2; usage >&2; exit 1 ;;
    *:*)
      # A second one is most likely a REST entry point given without http:// or https://.
      if [ -n "$credentials" ]; then
        echo >&2 "Error: \"$1\" is neither credentials, which were given already, nor a REST entry point, which has to start with http:// or https://."
        exit 1
      fi
      credentials="$1"; shift ;;
    *) echo >&2 "Error: Unexpected argument \"$1\"."; echo >&2; usage >&2; exit 1 ;;
  esac
done
# The remaining arguments are Maven's.

if [ -n "$credentials" ] && [ -n "$netrcFile" ]; then
  echo >&2 "Error: Pass either credentials or --netrc-file, not both."
  exit 1
fi

if ! [ -d "./src" ]; then
   echo >&2 "Error: Please start this script in the folder of the Maven module that builds the xar!"
   exit 2
fi

if [ -n "$netrcFile" ] && ! [ -r "$netrcFile" ]; then
  echo >&2 "Error: Cannot read netrc file \"$netrcFile\"."
  exit 2
fi

callMaven() {
  local mvnCommand exitCode

  # Use `mvnd` if available as it is much faster, otherwise use `mvn`.
  mvnCommand=$(command -v mvnd || command -v mvn)

  if [ -z "$mvnCommand" ]; then
    echo >&2 "Error: You need Maven to run this script!"
    exit 2
  fi

  "$mvnCommand" -B -ntp "$@"
  exitCode=$?

  if [ "$exitCode" -ne 0 ]; then
    echo >&2 "Error: Maven call failed with exit code $exitCode"
    exit $exitCode
  fi
}

# Credentials given on the command line are handed to curl through its standard input rather than
# as an argument, so they do not show up in the process list. In a curl config file, backslashes
# and double quotes inside a quoted value have to be escaped.
callCurl() {
  local escapedCredentials

  if [ -n "$credentials" ]; then
    escapedCredentials=$(printf '%s' "$credentials" | sed 's/[\\"]/\\&/g')
    printf 'user = "%s"\n' "$escapedCredentials" | curl --config - "$@"
  elif [ -n "$netrcFile" ]; then
    curl --netrc-file "$netrcFile" "$@"
  else
    curl --netrc-optional "$@"
  fi
}

if [ "$build" = true ]; then
  # In a module of a multi-module project, the modules it depends on are built along with it, so
  # that they do not have to be in the local Maven repository already.
  reactorRoot=$(pwd -P)
  module=""
  while parent=$(dirname "$reactorRoot") && [ -f "$parent/pom.xml" ] \
    && grep -Eq "<module>[[:space:]]*(\./)?${reactorRoot##*/}/?[[:space:]]*</module>" "$parent/pom.xml"; do
    module="${reactorRoot##*/}${module:+/$module}"
    reactorRoot="$parent"
  done

  # "package" is given twice due to some strange maven issues.
  if [ -n "$module" ]; then
    echo "Building $module with the modules it depends on in $reactorRoot..."
    callMaven -f "$reactorRoot/pom.xml" -pl "$module" -am package package "$@"
  else
    callMaven package package "$@"
  fi
fi

# The newest xar file in ./target is the one just built.
xarFile=""
for candidate in ./target/*.xar; do
  [ -f "$candidate" ] || continue
  if [ -z "$xarFile" ] || [ "$candidate" -nt "$xarFile" ]; then
    xarFile="$candidate"
  fi
done

if [ -z "$xarFile" ]; then
  echo >&2 "Error: There is no xar file in ./target to deploy - is this the folder of the module that builds it?"
  exit 2
fi

echo
echo "Deploying xar file \"$xarFile\" to wiki \"$wiki\" at $restEntryPoint..."

# The xar is posted as the request body rather than as a multipart form: XWiki's CSRF protection
# only applies to form submissions, so this needs no form token.
responseFile=$(mktemp)
httpCode=$(callCurl -sS -o "$responseFile" -w '%{http_code}' \
  -X POST \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@$xarFile" \
  "$restEntryPoint/wikis/$wiki?backup=false&history=RESET")
exitCode=$?

if [ "$exitCode" -ne 0 ] || [ "$httpCode" != "200" ]; then
  echo >&2 "Error: Deployment failed (curl exit code $exitCode, HTTP status ${httpCode:-none})."
  # For these status codes the response is a generic error page; for others, such as a 500, it
  # carries XWiki's own error message.
  case "$httpCode" in
    401) echo >&2 "The credentials were missing or rejected - see --help for how to pass them. XWiki also answers 401 if wiki \"$wiki\" does not exist." ;;
    403) echo >&2 "The account is not allowed to import pages into wiki \"$wiki\"." ;;
    404|405) echo >&2 "$restEntryPoint is not an XWiki REST entry point." ;;
    *) head -c 2000 "$responseFile" >&2 ;;
  esac
  rm -f "$responseFile"
  exit 1
fi
rm -f "$responseFile"

echo "Deployment of \"$xarFile\" was successful ($(date "+%Y-%m-%d %H:%M:%S"))."
