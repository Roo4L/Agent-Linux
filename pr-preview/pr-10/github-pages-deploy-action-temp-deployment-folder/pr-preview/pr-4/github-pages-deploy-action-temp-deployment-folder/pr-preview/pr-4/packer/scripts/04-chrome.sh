#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

###############################################################################
# Install Google Chrome
###############################################################################
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb
apt-get install -y /tmp/chrome.deb
rm -f /tmp/chrome.deb

###############################################################################
# Install Xvfb for headed mode support
###############################################################################
apt-get install -y xvfb

###############################################################################
# Lock Chrome version and remove Google apt repo (self-contained image)
###############################################################################
apt-mark hold google-chrome-stable
rm -f /etc/apt/sources.list.d/google-chrome.list
rm -f /etc/apt/sources.list.d/google-chrome.list.save
rm -f /etc/apt/trusted.gpg.d/google-chrome*.gpg
rm -f /usr/share/keyrings/google-chrome*.gpg

###############################################################################
# Verification
###############################################################################
echo "=== Chrome Verification ==="
google-chrome --version
which xvfb-run
apt-mark showhold | grep google-chrome-stable
# Confirm Google repo is gone
test ! -f /etc/apt/sources.list.d/google-chrome.list
echo "Chrome install complete"
