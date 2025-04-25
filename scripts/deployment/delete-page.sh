#!/usr/bin/env sh

# Script to delete an XWiki page
set -e

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ] || { [ "$#" -eq 4 ] && [ "$1" != "--netrc-file" ]; }; then
  echo "Script will delete an XWiki page."
  echo
  echo "Usage:"
  echo "  sh $0 <USERNAME>:<PASSWORD> <REST_ENTRY_POINT> <PAGE_TO_DELETE>"
  echo "  or"
  echo "  sh $0 --netrc-file <PATH_TO_NETRC_FILE> <REST_ENTRY_POINT> <PAGE_TO_DELETE>"
  exit 1
fi

if [ "$#" -eq 3 ]; then
  usingNetrcFile=false
  credentials=$1
  netrcFile=""
  restEntryPoint=$2
  pageToDelete=$3
else
  usingNetrcFile=true
  credentials=""
  netrcFile=$2
  restEntryPoint=$3
  pageToDelete=$4
fi

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
    curl -v  --fail-with-body -u "$credentials" "$@"
  fi

  local exitCode=$?

  if [ "$exitCode" -ne 0 ]; then
    echo >&2 "Error: cURL call failed with exit code $exitCode"
    exit $exitCode
  fi
}

pageContent=$(callCurl "$restEntryPoint/../bin/view/Main")
formToken=$(echo "$pageContent" | grep -oP 'data-xwiki-form-token="\K[^"]+')

if [ "$formToken" = "" ]; then
  echo >&2 "Error: Could not determine form token"
  exit 2
fi

echo
echo "Deleting page \"$pageToDelete\" if available:"

callCurl -X DELETE \
  -H "XWiki-Form-Token: $formToken" \
  "$restEntryPoint/wikis/xwiki/$pageToDelete"

echo
echo "XWiki page \"$pageToDelete\" has been successfully deleted ($(date "+%Y-%m-%d %H:%M:%S"))."
