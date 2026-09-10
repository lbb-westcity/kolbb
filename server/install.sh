#!/usr/bin/env bash
set -euo pipefail
# Run from the unpacked server bundle on Ubuntu 24.04.
if [[ $(id -u) -ne 0 ]]; then
  echo 'Run with sudo: sudo bash install.sh' >&2
  exit 1
fi
cd -- "$(dirname -- "$0")"
id kolbb >/dev/null 2>&1 || useradd --system --home-dir /var/lib/kolbb --shell /usr/sbin/nologin kolbb
install -d -o root -g root /opt/kolbb
install -d -o kolbb -g kolbb /var/lib/kolbb /var/log/kolbb
touch /var/log/kolbb/server.log
chown kolbb:kolbb /var/log/kolbb/server.log
chmod 640 /var/log/kolbb/server.log
install -m 755 kolbb-server.x86_64 /opt/kolbb/kolbb-server.next
mv -f /opt/kolbb/kolbb-server.next /opt/kolbb/kolbb-server.x86_64
install -m 644 kolbb.service /etc/systemd/system/kolbb.service
install -m 644 kolbb.logrotate /etc/logrotate.d/kolbb
systemctl daemon-reload
systemctl enable kolbb
systemctl restart kolbb
systemctl --no-pager --full status kolbb
printf '\nAllow UDP 7000 in the cloud security group and host firewall.\n'
