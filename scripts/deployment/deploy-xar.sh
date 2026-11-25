#!/usr/bin/env sh

# Script to build the xar deployment artifact and automatically deploy it on the dev server.

verbose=false
clean=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    -v|--verbose) verbose=true; shift ;;
    -c|--clean) clean=true; shift ;;
    *) break ;;
  esac
done

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ] || { [ "$#" -eq 3 ] && [ "$1" != "--netrc-file" ]; }; then
  echo "Script will build the XWiki xar file and deploy it on the development server"
  echo
  echo "Usage:"
  echo "  sh $0 [-v|--verbose] [-c|--clean] <USERNAME>:<PASSWORD> <REST_ENTRY_POINT>"
  echo "  or"
  echo "  sh $0 [-v|--verbose] [-c|--clean] --netrc-file <PATH_TO_NETRC_FILE> <REST_ENTRY_POINT>"
  echo
  echo "Options:"
  echo "  -v, --verbose  Verbose cURL output for debugging."
  echo "                 WARNING: The output contains the credentials (Authorization header)!"
  echo "  -c, --clean    Run \"mvn clean package\" instead of an incremental \"mvn package\"."
  echo "                 Slower, but use it if an outdated xar gets deployed or the build behaves oddly."
  echo
  echo "Example REST entry point: https://xwiki-dev.example.com/xwiki/rest"
  echo "The xar is imported into the main wiki (\"xwiki\")."
  exit 1
fi

if [ "$verbose" = "true" ]; then
  echo >&2 "WARNING: Verbose mode, the cURL output contains the credentials (Authorization header)!"
  echo >&2 "         Do not use it in CI jobs or share the output."
fi

if ! [ -d "./src" ]; then
   echo >&2 "Error: Please start this script from project root!"
   exit 2
fi

if [ "$#" -eq 2 ]; then
  usingNetrcFile=false
  credentials=$1
  netrcFile=""
  restEntryPoint=$2
else
  usingNetrcFile=true
  credentials=""
  netrcFile=$2
  restEntryPoint=$3
fi

# Use `mvnd` if available as it is much faster, otherwise use `mvn`.
mvnCommand=$(command -v mvnd)

if [ "$mvnCommand" = "" ]; then
  mvnCommand=$(command -v mvn)
fi

if [ "$mvnCommand" = "" ]; then
  echo >&2 "Error: You need Maven to run this script!"
  exit 2
fi

callMaven() {
  "$mvnCommand" "$@"
  exitCode=$?

  if [ "$exitCode" -ne 0 ]; then
    echo >&2 "Error: Maven call failed with exit code $exitCode"
    exit $exitCode
  fi
}

curlVerboseFlag=""
if [ "$verbose" = "true" ]; then
  curlVerboseFlag="-v"
fi

callCurl() {
  # Log to stderr so that the output of callCurl can be captured
  {
    echo
    echo "--------------------------------------------------"
    echo "Calling curl with the following custom parameters:"
    printf '  %s\n' "$@"
    echo "--------------------------------------------------"
    echo
  } >&2

  if [ "$usingNetrcFile" = "true" ]; then
    curl -sS $curlVerboseFlag --fail-with-body --netrc-file "$netrcFile" "$@"
  else
    curl -sS $curlVerboseFlag --fail-with-body -u "$credentials" "$@"
  fi

  exitCode=$?

  if [ "$exitCode" -ne 0 ]; then
    echo >&2 "Error: cURL call failed with exit code $exitCode"
    exit $exitCode
  fi
}

pageContent=$(callCurl "$restEntryPoint/../bin/view/Main/")
formToken=$(echo "$pageContent" | LC_ALL=C.UTF-8 grep -oP 'data-xwiki-form-token="\K[^"]+')

if [ "$formToken" = "" ]; then
  echo >&2 "Error: Could not determine form token"
  exit 2
fi

if [ "$clean" = "true" ]; then
  callMaven clean package
else
  callMaven package
fi

ls ./target/*.xar > /dev/null || exit 2 # will fail if no xar file is available
xarFilename=$(ls -t ./target/*.xar | head -1 | xargs basename)

echo
echo "Trying to deploy xar file \"target/$xarFilename\" on $restEntryPoint..."

echo
echo "Installing xar file \"target/$xarFilename\":"

# The REST import expects the xar as raw request body, options are query parameters.
# POST is implied by --data-binary.
callCurl \
  -H "XWiki-Form-Token: $formToken" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@./target/$xarFilename" \
  "$restEntryPoint/wikis/xwiki?backup=false&history=RESET"

echo
echo
echo "Deployment of \"target/$xarFilename\" was successful ($(date "+%Y-%m-%d %H:%M:%S"))."
