#!/usr/bin/env sh

# Script to build the xar deployment artifact and automatically deploy it on the dev server.

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ] || { [ "$#" -eq 3 ] && [ "$1" != "--netrc-file" ]; }; then
  echo "Script will build the XWiki xar file and deploy it on the development server"
  echo
  echo "Usage:"
  echo "  sh $0 <USERNAME>:<PASSWORD> <REST_ENTRY_POINT>"
  echo "  or"
  echo "  sh $0 --netrc-file <PATH_TO_NETRC_FILE> <REST_ENTRY_POINT>"
  exit 1
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

callCurl() {
  echo
  echo "--------------------------------------------------"
  echo "Calling curl with the following custom parameters:"
  echo $*
  echo "--------------------------------------------------"
  echo

  if [ "$usingNetrcFile" = "true" ]; then
    curl -v --fail-with-body -netrc-file "$netrcFile" "$@"
  else
    curl -v --fail-with-body -u "$credentials" "$@"
  fi

  local exitCode=$?

  if [ "$exitCode" -ne 0 ]; then
    echo >&2 "Error: cURL call failed with exit code $exitCode"
    exit $exitCode
  fi
}

pageContent=$(callCurl "$restEntryPoint/../bin/view/Main")
formToken=$(echo "$pageContent" | LC_ALL=C.UTF-8 grep -oP 'data-xwiki-form-token="\K[^"]+')

if [ "$formToken" = "" ]; then
  echo >&2 "Error: Could not determine form token"
  exit 2
fi

# Use `mvnd` if available as it is much faster, otherwise use `mvn`.
callMaven package package # will be called twice due to some strange maven issues

ls ./target/*.xar > /dev/null # will fail if no xar file is available
xarFilename=$(ls ./target/*.xar -t | head -1 | xargs basename)

echo
echo "Trying to deploy xar file \"target/$xarFilename\" on $restEntryPoint..."

echo
echo "Installing xar file \"target/$xarFilename\":"

callCurl \
  -H "XWiki-Form-Token: $formToken" \
  -H "Content-type: application/octet-stream" \
  -F "file=@./target/$xarFilename" \
  -F "backup=false" \
  -F "history=RESET" \
  "$restEntryPoint/wikis/xwiki"

echo
echo
echo "Deployment of \"target/$xarFilename\" was successful ($(date "+%Y-%m-%d %H:%M:%S"))."
