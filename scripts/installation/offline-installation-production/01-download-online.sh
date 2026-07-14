#!/bin/bash
# 01-download-online.sh
# Run this on the internet-connected machine.
# Downloads JRE 21, Tomcat 10.1.x, the XWiki WAR, and the PostgreSQL JDBC
# driver into ~/temp-xwiki-offline, so the directory can then be transferred
# to the offline machine (e.g. via USB).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-config.sh"

echo ">>> (Re-)creating ${TRANSFER_DIR}"
rm -rf "${TRANSFER_DIR}"
mkdir -p "${TRANSFER_DIR}"
cd "${TRANSFER_DIR}"

echo ">>> Downloading JRE"
curl -L -O "${JRE_URL}"

echo ">>> Downloading Tomcat"
curl -L -O "${TOMCAT_URL}"

echo ">>> Downloading XWiki WAR"
curl -L -O "${XWIKI_URL}"

echo ">>> Downloading PostgreSQL JDBC driver"
curl -L -O "${JDBC_URL}"

# Copy the config script into the transfer directory as well, so the offline
# machine uses exactly the same versions/paths.
cp "${SCRIPT_DIR}/00-config.sh" "${TRANSFER_DIR}/"

echo ""
echo ">>> Done. Contents of ${TRANSFER_DIR}:"
ls -lh "${TRANSFER_DIR}"
echo ""
echo "Now transfer ${TRANSFER_DIR} (including install scripts 02-05) to the"
echo "offline machine, e.g. via USB."
