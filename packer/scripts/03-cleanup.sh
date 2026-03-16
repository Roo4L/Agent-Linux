#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# NOTE: packer user and sudoers cleanup moved to shutdown_command in
# agentlinux.pkr.hcl because removing them here breaks Packer's SSH-based
# shutdown command (packer user needs sudo to execute shutdown).

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
