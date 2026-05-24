#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# Remove build-time-only tools (fpm, ruby, build-essential) to save image space
# These were only needed during package building in 03-nodejs.sh
gem uninstall -x fpm 2>/dev/null || true
apt-get purge -y ruby-dev build-essential ruby 2>/dev/null || true

# Schedule packer user removal for next boot via a oneshot systemd service.
# We cannot use 'userdel' during provisioning (Packer SSH session keeps user active)
# or in shutdown_command (same problem). The oneshot service runs before login.
cat > /etc/systemd/system/cleanup-packer-user.service <<'UNIT'
[Unit]
Description=Remove packer build user
Before=multi-user.target
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'userdel -rf packer 2>/dev/null; rm -f /etc/sudoers.d/90-cloud-init-users; systemctl disable cleanup-packer-user.service; rm -f /etc/systemd/system/cleanup-packer-user.service'
RemainAfterExit=false

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable cleanup-packer-user.service

# Clean apt cache
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

# Remove any remaining cloud-init artifacts
rm -rf /etc/cloud /var/lib/cloud

# Remove machine-id (regenerated on first boot for unique identity)
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Clear logs
journalctl --flush 2>/dev/null || true
journalctl --rotate 2>/dev/null || true
journalctl --vacuum-time=0 2>/dev/null || true
truncate -s 0 /var/log/wtmp
truncate -s 0 /var/log/lastlog

# Zero free space for better QCOW2 compression
dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
rm -f /EMPTY
sync
