#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# Update apt to pick up local repo (already configured by 03-nodejs.sh)
apt-get update

# Install packages -- apt resolves dependencies automatically
# agentlinux-gsd depends on agentlinux-claude-code, so order matters
# google-chrome-stable is already installed by 04-chrome.sh
apt-get install -y agentlinux-claude-code
apt-get install -y agentlinux-gsd
apt-get install -y agentlinux-chrome-devtools-mcp

echo "=== Agent Tools Smoke Tests ==="

# PKG-01: Claude Code
claude --version || echo "WARNING: claude --version failed (may need interactive terminal)"
which claude && echo "PASS: claude on PATH" || echo "FAIL: claude not on PATH"
npm list -g @anthropic-ai/claude-code && echo "PASS: claude-code npm package installed"

# PKG-02: GSD
npm list -g get-shit-done-cc && echo "PASS: gsd npm package installed"
test -d /etc/skel/.claude/get-shit-done && echo "PASS: GSD integration files in /etc/skel"
test -d /etc/skel/.claude/commands/gsd && echo "PASS: GSD slash commands in /etc/skel"
test -f /etc/skel/.claude/settings.json && echo "PASS: settings.json in /etc/skel"

# Check settings.json has /usr/bin/node (not a hardcoded user path)
grep -q "/usr/bin/node" /etc/skel/.claude/settings.json && echo "PASS: settings.json uses /usr/bin/node" || echo "WARNING: settings.json may have wrong node path"

# MCP-01: Chrome DevTools MCP
npm list -g chrome-devtools-mcp && echo "PASS: chrome-devtools-mcp npm package installed"
google-chrome --version && echo "PASS: Google Chrome installed"

# MCP-02: MCP config present
test -f /etc/skel/.claude.json && echo "PASS: .claude.json in /etc/skel"
grep -q "chrome-devtools" /etc/skel/.claude.json && echo "PASS: MCP server configured in .claude.json"

# PKG-04: Local repo
test -f /opt/agentlinux/apt-repo/Packages && echo "PASS: Local apt repo Packages index exists"
test -f /etc/apt/sources.list.d/agentlinux.list && echo "PASS: Apt source configured"

echo "=== Smoke Tests Complete ==="
