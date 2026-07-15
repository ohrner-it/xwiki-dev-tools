#!/bin/bash
# 00-config.sh
# Central configuration, sourced by all other scripts via `source`.
# NEVER put real passwords in here (see 03-setup-database.sh).

set -euo pipefail

# ---------------------------------------------------------------------------
# Versions / download URLs (only relevant for 01-download-online.sh)
# ---------------------------------------------------------------------------
JRE_ARCHIVE="OpenJDK21U-jre_x64_linux_hotspot_21.0.11_10.tar.gz"
JRE_URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.11%2B10/${JRE_ARCHIVE}"

TOMCAT_VERSION="10.1.57"
TOMCAT_ARCHIVE="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/${TOMCAT_ARCHIVE}"

XWIKI_VERSION="17.10.10"
XWIKI_WAR="xwiki-platform-distribution-war-${XWIKI_VERSION}.war"
XWIKI_URL="https://nexus.xwiki.org/nexus/content/groups/public/org/xwiki/platform/xwiki-platform-distribution-war/${XWIKI_VERSION}/${XWIKI_WAR}"

# XIP package: offline extension repository containing the Standard Flavor
# and all the extensions it depends on. Must match XWIKI_VERSION exactly.
# Without this, the first-start Distribution Wizard needs internet access
# to download the Standard Flavor from nexus.xwiki.org.
XIP_FILE="xwiki-platform-distribution-flavor-xip-${XWIKI_VERSION}.xip"
XIP_URL="https://nexus.xwiki.org/nexus/content/repositories/releases/org/xwiki/platform/xwiki-platform-distribution-flavor-xip/${XWIKI_VERSION}/${XIP_FILE}"

# PostgreSQL JDBC driver is also needed offline (not included in the WAR)
JDBC_VERSION="42.7.4"
JDBC_JAR="postgresql-${JDBC_VERSION}.jar"
JDBC_URL="https://repo1.maven.org/maven2/org/postgresql/postgresql/${JDBC_VERSION}/${JDBC_JAR}"

# ---------------------------------------------------------------------------
# Directories / users on the offline machine
# ---------------------------------------------------------------------------
TRANSFER_DIR="${TRANSFER_DIR:-$HOME/temp-xwiki-offline}"   # directory transferred via USB
INSTALL_DIR="/opt/xwiki"                                   # base install directory
JRE_DIR="${INSTALL_DIR}/jre"                                # JRE
TOMCAT_DIR="${INSTALL_DIR}/tomcat"                          # Tomcat (CATALINA_HOME/BASE)
WEBAPP_DIR="${TOMCAT_DIR}/webapps/xwiki"                    # extracted XWiki webapp
XWIKI_DATA_DIR="/var/lib/xwiki/data"                        # XWiki "permanent directory"
SERVICE_USER="xwiki"
SERVICE_GROUP="xwiki"

# HTTP port Tomcat's connector listens on. Ports below 1024 (e.g. 80)
# normally require root; 05-install-systemd-service.sh instead grants just
# the CAP_NET_BIND_SERVICE capability via systemd (AmbientCapabilities), so
# Tomcat keeps running as the unprivileged SERVICE_USER. No extra package
# needed - this is a systemd/kernel feature, not the 'setcap' CLI tool.
HTTP_PORT="${HTTP_PORT:-8080}"

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
DB_NAME="xwiki"
DB_USER="xwiki"
DB_HOST="localhost"
DB_PORT="5432"
# The DB password is NOT stored here. It is requested interactively in
# 03-setup-database.sh (read -s), or optionally provided via the
# XWIKI_DB_PASSWORD environment variable. Please do not enter/share real
# passwords in chat tools or similar.
