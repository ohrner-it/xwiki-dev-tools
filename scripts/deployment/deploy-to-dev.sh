#!/usr/bin/env sh

# Script to build the xar deployment artifact and automatically deploy it on the dev server.
# This script does the same as `deploy-xar.sh`, except that it will delete project specific
# pages first, pages that shall be redeployed.
# This is a workaround for a strange bug of XWiki.

# Constants
PAGE_TO_DELETE="spaces/Macros/spaces/Expandable/pages/WebHome"

set -e

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ] || { [ "$#" -eq 3 ] && [ "$1" != "--netrc-file" ]; }; then
  echo "Script will build the XWiki xar file and deploy it on the development server"
  echo
  echo "Usage:"
  echo "  sh $0 <USERNAME>:<PASSWORD> <REST_ENTRY_POINT>"
  echo "  or"
  echo "  sh $0 --netrc-file <PATH_TO_NETRC_FILE> <REST_ENTRY_POINT>"
  exit 1
fi

dir="$(dirname "$0")"

# XWiki seems to have from time to time problems deploying the xar file if the old versions of the deployed pages have
# not been deleted before deployment.
set +e
/usr/bin/env sh "$dir/delete-page.sh" $* "$PAGE_TO_DELETE"
set -e

/usr/bin/env sh "$dir/deploy-xar.sh" $*
