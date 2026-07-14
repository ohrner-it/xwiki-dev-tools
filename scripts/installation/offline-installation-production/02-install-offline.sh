#!/bin/bash
# 02-install-offline.sh
# Run this on the offline machine as root (or via sudo).
# Expects ${TRANSFER_DIR} (default: ~/temp-xwiki-offline), including
# 00-config.sh, to already have been transferred via USB.
#
# Steps:
#   1. Create a system user/group for the Tomcat/XWiki service
#   2. Extract JRE + Tomcat into ${INSTALL_DIR}
#   3. Extract the XWiki WAR into ${WEBAPP_DIR} (not deployed as a plain
#      .war, so we can adjust config files before the first start)
#   4. Copy the PostgreSQL JDBC driver into the webapp's WEB-INF/lib
#   5. Create the XWiki "permanent directory"
#   6. Write setenv.sh
#   7. Set ownership to SERVICE_USER

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo $0)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-config.sh"

if [[ ! -d "${TRANSFER_DIR}" ]]; then
  echo "Transfer directory ${TRANSFER_DIR} not found." >&2
  echo "Use TRANSFER_DIR=<path> $0 if it is located elsewhere." >&2
  exit 1
fi

echo ">>> Creating service user ${SERVICE_USER} (if not already present)"
if ! getent group "${SERVICE_GROUP}" >/dev/null; then
  groupadd --system "${SERVICE_GROUP}"
fi
if ! getent passwd "${SERVICE_USER}" >/dev/null; then
  useradd --system --gid "${SERVICE_GROUP}" --home-dir "${INSTALL_DIR}" \
    --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

echo ">>> Removing any previous installation in ${INSTALL_DIR}"
rm -rf "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}/jre"

echo ">>> Extracting JRE"
tar -xzf "${TRANSFER_DIR}/${JRE_ARCHIVE}" --strip-components=1 -C "${INSTALL_DIR}/jre"

echo ">>> Extracting Tomcat"
tar -xzf "${TRANSFER_DIR}/${TOMCAT_ARCHIVE}" --strip-components=1 -C "${INSTALL_DIR}"

echo ">>> Extracting XWiki WAR into ${WEBAPP_DIR}"
mkdir -p "${WEBAPP_DIR}"
if command -v unzip >/dev/null 2>&1; then
  unzip -q "${TRANSFER_DIR}/${XWIKI_WAR}" -d "${WEBAPP_DIR}"
elif command -v python3 >/dev/null 2>&1; then
  python3 -m zipfile -e "${TRANSFER_DIR}/${XWIKI_WAR}" "${WEBAPP_DIR}/"
else
  echo "Neither 'unzip' nor 'python3' is available - please provide one of them offline." >&2
  exit 1
fi

echo ">>> Copying PostgreSQL JDBC driver into WEB-INF/lib"
cp "${TRANSFER_DIR}/${JDBC_JAR}" "${WEBAPP_DIR}/WEB-INF/lib/"

echo ">>> Creating XWiki 'permanent directory': ${XWIKI_DATA_DIR}"
mkdir -p "${XWIKI_DATA_DIR}"

echo ">>> Writing ${INSTALL_DIR}/bin/setenv.sh"
tee "${INSTALL_DIR}/bin/setenv.sh" > /dev/null <<EOSETENV
#!/bin/sh
# Java Runtime Environment
export JAVA_HOME=${INSTALL_DIR}/jre
export JRE_HOME=${INSTALL_DIR}/jre

# Tomcat location
export CATALINA_HOME=${INSTALL_DIR}
export CATALINA_BASE=${INSTALL_DIR}

# JVM options for XWiki
export CATALINA_OPTS="\\
-Xms1024m \\
-Xmx2048m \\
-Dfile.encoding=UTF-8 \\
--add-opens=java.base/java.lang=ALL-UNNAMED \\
--add-opens=java.base/java.io=ALL-UNNAMED \\
--add-opens=java.base/java.util=ALL-UNNAMED \\
--add-opens=java.base/java.util.concurrent=ALL-UNNAMED"
EOSETENV
chmod +x "${INSTALL_DIR}/bin/setenv.sh"

echo ">>> Setting ownership"
chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${INSTALL_DIR}"
chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${XWIKI_DATA_DIR}"

echo ""
echo ">>> Done. Next steps:"
echo "    sudo ./03-setup-database.sh"
echo "    sudo ./04-configure-xwiki.sh"
echo "    sudo ./05-install-systemd-service.sh"
