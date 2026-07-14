#!/bin/bash
# 05-install-systemd-service.sh
# Run this on the offline machine as root.
# Creates a systemd service that starts Tomcat (with XWiki) on boot.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo $0)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-config.sh"

SERVICE_FILE="/etc/systemd/system/xwiki-tomcat.service"

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
Environment=CATALINA_HOME=${INSTALL_DIR}
Environment=CATALINA_BASE=${INSTALL_DIR}
Environment=CATALINA_PID=${INSTALL_DIR}/temp/tomcat.pid
ExecStart=${INSTALL_DIR}/bin/startup.sh
ExecStop=${INSTALL_DIR}/bin/shutdown.sh
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
echo ">>> XWiki should be reachable shortly at http://<host>:8080/xwiki"
echo "    Logs: journalctl -u xwiki-tomcat.service -f"
echo "          tail -f ${INSTALL_DIR}/logs/catalina.out"
