#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# Purge cloud-init FIRST (conflicts with one-context -- they race on boot)
apt-get purge -y cloud-init
rm -rf /etc/cloud /var/lib/cloud

# Download and install one-context
# Version must match target OpenNebula server (6.10.0-3 for ONE 6.x)
ONE_CONTEXT_VERSION="${ONE_CONTEXT_VERSION:-6.10.0-3}"
wget -q "https://github.com/OpenNebula/one-apps/releases/download/v${ONE_CONTEXT_VERSION}/one-context_${ONE_CONTEXT_VERSION}.deb" \
  -O /tmp/one-context.deb
dpkg -i /tmp/one-context.deb || apt-get install -fy
rm -f /tmp/one-context.deb

# Verify one-context is installed and enabled
systemctl is-enabled one-context || systemctl enable one-context
systemctl is-enabled one-context-local || systemctl enable one-context-local
