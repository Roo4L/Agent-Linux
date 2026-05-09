#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# Resize partition and filesystem to fill disk (Packer set disk_size=10G but base image is ~2GB)
growpart /dev/vda 1 || true
resize2fs /dev/vda1 || true

# Configure locale
apt-get update
apt-get install -y locales
sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen en_US.UTF-8

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Install essential packages
apt-get install -y \
  sudo \
  openssh-server \
  curl \
  wget \
  ca-certificates \
  gnupg
