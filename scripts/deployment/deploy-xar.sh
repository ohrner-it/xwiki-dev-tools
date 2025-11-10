#!/usr/bin/env sh

# Script to update some of the the other scripts by downloading their latest version from
# https://github.com/ohrner-it/xwiki-dev-tools - does not need any command line arguments to run.

set -e

if [ "$#" -gt 0 ]; then
  echo "This script will update some other scripts in the project's \"scripts\" directory (no arguments required)."
  echo "It will download the latest script versions from https://github.com/ohrner-it/xwiki-dev-tools."
  echo "Usage: sh $0 [--help]"
  exit 1
fi

if ! [ -d "./src" ] || ! [ -d "./scripts" ]; then
   echo >&2 "Error: Please start this script from project root."
   exit 2
fi

sourceDir=https://raw.githubusercontent.com/ohrner-it/xwiki-dev-tools/refs/heads/main/scripts/deployment
targetDir="./scripts"

for file in "deploy-xar.sh"; do
  echo "Downloading \"${file}\"..."
  tempFile=$(mktemp)
  set +e
  curl -s --fail-with-body --output "${tempFile}" "${sourceDir}/${file}"
  exitCode=$?
  set -e

  if [ $exitCode -ne 0 ]; then
    rm "${tempFile}"
    echo >&2 "Error: Could not download file \"${file}\"."
    exit $exitCode
  fi

  mv "${tempFile}" "${targetDir}/${file}"
done

echo "Script files have been updated successfully."
