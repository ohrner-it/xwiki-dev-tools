#!/bin/bash
# 04-configure-xwiki.sh
# Run this on the offline machine as root, AFTER 02-install-offline.sh and
# 03-setup-database.sh, but BEFORE starting Tomcat for the first time.
#
# 1. Rewrites WEB-INF/hibernate.cfg.xml to use PostgreSQL instead of the
#    bundled HSQLDB default configuration. The <mapping resource=".../>
#    entries are preserved by extracting them from the original file, so
#    this works regardless of the exact comment layout of the shipped file
#    for a given XWiki version.
# 2. Sets the "permanent directory" in xwiki.properties.
#
# The DB password is requested interactively again here (it was
# intentionally not stored after step 03) and ends up only in
# hibernate.cfg.xml, which gets restrictive file permissions (600, owned by
# SERVICE_USER).

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo $0)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-config.sh"

HIBERNATE_CFG="${WEBAPP_DIR}/WEB-INF/hibernate.cfg.xml"
XWIKI_PROPERTIES="${WEBAPP_DIR}/WEB-INF/classes/xwiki.properties"

if [[ ! -f "${HIBERNATE_CFG}" ]]; then
  echo "Not found: ${HIBERNATE_CFG} - did you run 02-install-offline.sh?" >&2
  exit 1
fi

if [[ -n "${XWIKI_DB_PASSWORD:-}" ]]; then
  DB_PASSWORD="${XWIKI_DB_PASSWORD}"
else
  read -rsp "Password for DB user '${DB_USER}' (from step 03): " DB_PASSWORD
  echo
fi

echo ">>> Backing up original as hibernate.cfg.xml.orig"
if [[ ! -f "${HIBERNATE_CFG}.orig" ]]; then
  cp "${HIBERNATE_CFG}" "${HIBERNATE_CFG}.orig"
fi

echo ">>> Extracting <mapping resource=.../> entries from the original"
MAPPINGS=$(grep -o '<mapping resource="[^"]*"[[:space:]]*/>' "${HIBERNATE_CFG}.orig" | sort -u)

if [[ -z "${MAPPINGS}" ]]; then
  echo "Could not find any <mapping resource=.../> lines - please check" >&2
  echo "${HIBERNATE_CFG}.orig manually and adjust this script if needed." >&2
  exit 1
fi

echo ">>> Writing new hibernate.cfg.xml for PostgreSQL"
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<!DOCTYPE hibernate-configuration PUBLIC'
  echo '        "-//Hibernate/Hibernate Configuration DTD 3.0//EN"'
  echo '        "http://hibernate.org/dtd/hibernate-configuration-3.0.dtd">'
  echo '<hibernate-configuration>'
  echo '  <session-factory>'
  echo "    <property name=\"connection.url\">jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}</property>"
  echo "    <property name=\"connection.username\">${DB_USER}</property>"
  echo "    <property name=\"connection.password\">${DB_PASSWORD}</property>"
  echo '    <property name="connection.driver_class">org.postgresql.Driver</property>'
  echo '    <property name="dialect">org.hibernate.dialect.PostgreSQLDialect</property>'
  echo "${MAPPINGS}"
  echo '  </session-factory>'
  echo '</hibernate-configuration>'
} > "${HIBERNATE_CFG}"

unset DB_PASSWORD

echo ">>> Setting permanent directory in xwiki.properties: ${XWIKI_DATA_DIR}"
if grep -q '^environment.permanentDirectory' "${XWIKI_PROPERTIES}" 2>/dev/null; then
  sed -i "s|^environment.permanentDirectory.*|environment.permanentDirectory=${XWIKI_DATA_DIR}|" "${XWIKI_PROPERTIES}"
elif grep -q '^#environment.permanentDirectory' "${XWIKI_PROPERTIES}" 2>/dev/null; then
  sed -i "s|^#environment.permanentDirectory.*|environment.permanentDirectory=${XWIKI_DATA_DIR}|" "${XWIKI_PROPERTIES}"
else
  echo "environment.permanentDirectory=${XWIKI_DATA_DIR}" >> "${XWIKI_PROPERTIES}"
fi

echo ">>> Setting ownership / permissions"
chown "${SERVICE_USER}:${SERVICE_GROUP}" "${HIBERNATE_CFG}"
chmod 600 "${HIBERNATE_CFG}"
chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${WEBAPP_DIR}"

echo ""
echo ">>> Configuration complete."
echo "    Worth a quick manual check: ${HIBERNATE_CFG}"
echo "    Continue with: sudo ./05-install-systemd-service.sh"
