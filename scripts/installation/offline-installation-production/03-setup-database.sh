#!/bin/bash
# 03-setup-database.sh
# Run this on the offline machine as root (or via sudo), AFTER PostgreSQL
# has been installed (see your note above) and is running.
#
# Creates the role + database for XWiki. The password is requested
# interactively and is never stored or printed anywhere.
#
# Note: XWiki recommends UTF8 encoding and "C" collation for PostgreSQL,
# since some indexes can otherwise become too long with the default,
# accent-sensitive collations.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo $0)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-config.sh"

if ! command -v psql >/dev/null 2>&1; then
  echo "psql not found - is PostgreSQL installed?" >&2
  exit 1
fi

if [[ -n "${XWIKI_DB_PASSWORD:-}" ]]; then
  DB_PASSWORD="${XWIKI_DB_PASSWORD}"
else
  read -rsp "New password for DB user '${DB_USER}': " DB_PASSWORD
  echo
  read -rsp "Repeat password: " DB_PASSWORD_CONFIRM
  echo
  if [[ "${DB_PASSWORD}" != "${DB_PASSWORD_CONFIRM}" ]]; then
    echo "Passwords do not match." >&2
    exit 1
  fi
fi

# Only create the role if it doesn't already exist
ROLE_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'")
if [[ "${ROLE_EXISTS}" == "1" ]]; then
  echo ">>> Role ${DB_USER} already exists, resetting password"
  sudo -u postgres psql -v ON_ERROR_STOP=1 \
    -c "ALTER ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';"
else
  echo ">>> Creating role ${DB_USER}"
  sudo -u postgres psql -v ON_ERROR_STOP=1 \
    -c "CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';"
fi

DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'")
if [[ "${DB_EXISTS}" == "1" ]]; then
  echo ">>> Database ${DB_NAME} already exists, skipping creation"
else
  echo ">>> Creating database ${DB_NAME} (UTF8, C collation)"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
    "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER} ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0;"
fi

unset DB_PASSWORD DB_PASSWORD_CONFIRM

echo ""
echo ">>> Database set up. Continue with: sudo ./04-configure-xwiki.sh"
