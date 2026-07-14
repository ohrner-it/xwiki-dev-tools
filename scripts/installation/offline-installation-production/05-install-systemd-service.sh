#!/bin/bash
# 05-install-systemd-service.sh
# Run this on the offline machine as root.
# Creates a systemd service that starts Tomcat (with XWiki) on boot,
# listening on HTTP_PORT (see 00-config.sh). If HTTP_PORT is a privileged
# port (<1024, e.g. 80), the unit is granted CAP_NET_BIND_SERVICE via
# systemd so Tomcat can still run as the unprivileged SERVICE_USER.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo $0)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-config.sh"

SERVICE_FILE="/etc/systemd/system/xwiki-tomcat.service"

# For privileged ports (<1024, e.g. 80) Tomcat still runs as SERVICE_USER;
# systemd grants just the CAP_NET_BIND_SERVICE capability instead of running
# the whole service as root or relying on setcap against the java binary
# (which would otherwise get stripped by chown and require libcap2-bin).
CAP_LINES=""
if [[ "${HTTP_PORT}" -lt 1024 ]]; then
  CAP_LINES=$'AmbientCapabilities=CAP_NET_BIND_SERVICE\nCapabilityBoundingSet=CAP_NET_BIND_SERVICE'
fi

echo ">>> Writing ${SERVICE_FILE}"
tee "${SERVICE_FILE}" > /dev/null <<EOSERVICE
[Unit]
Description=XWiki (Apache Tomcat) Service
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=forking
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
${CAP_LINES}
Environment=CATALINA_HOME=${TOMCAT_DIR}
Environment=CATALINA_BASE=${TOMCAT_DIR}
Environment=CATALINA_PID=${TOMCAT_DIR}/temp/tomcat.pid
ExecStart=${TOMCAT_DIR}/bin/startup.sh
ExecStop=${TOMCAT_DIR}/bin/shutdown.sh
SuccessExitStatus=143
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOSERVICE

echo ">>> Reloading systemd, enabling and starting the service"
systemctl daemon-reload
systemctl enable xwiki-tomcat.service
systemctl restart xwiki-tomcat.service

echo ""
echo ">>> Status:"
systemctl --no-pager status xwiki-tomcat.service || true

echo ""
echo ">>> XWiki should be reachable shortly at http://<host>:${HTTP_PORT}/xwiki"
echo "    Logs: journalctl -u xwiki-tomcat.service -f"
echo "          tail -f ${TOMCAT_DIR}/logs/catalina.out"
