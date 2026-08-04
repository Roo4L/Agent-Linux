#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

###############################################################################
# Section A: Install Node.js 22 LTS from NodeSource
###############################################################################
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
node --version
npm --version

###############################################################################
# Section B: Install fpm and dpkg-dev
###############################################################################
apt-get install -y ruby-dev build-essential dpkg-dev
gem install fpm
fpm --version

###############################################################################
# Section C: Build three .deb packages
###############################################################################

# --------------------------------------------------------------------------
# Package 1: agentlinux-claude-code
# --------------------------------------------------------------------------
mkdir -p /tmp/pkg-claude-code

cat > /tmp/postinst-claude-code.sh <<'POSTINST'
#!/bin/bash
npm install -g @anthropic-ai/claude-code || true
POSTINST

cat > /tmp/postrm-claude-code.sh <<'POSTRM'
#!/bin/bash
npm uninstall -g @anthropic-ai/claude-code || true
POSTRM

chmod 755 /tmp/postinst-claude-code.sh /tmp/postrm-claude-code.sh

fpm -s dir -t deb \
  --name agentlinux-claude-code \
  --version 1.0.0 \
  --architecture amd64 \
  --depends "nodejs (>= 22)" \
  --description "Claude Code CLI for AgentLinux" \
  --maintainer "AgentLinux" \
  --after-install /tmp/postinst-claude-code.sh \
  --after-remove /tmp/postrm-claude-code.sh \
  --deb-no-default-config-files \
  -C /tmp/pkg-claude-code \
  .

# --------------------------------------------------------------------------
# Package 2: agentlinux-gsd
# --------------------------------------------------------------------------
mkdir -p /tmp/pkg-gsd

cat > /tmp/postinst-gsd.sh <<'POSTINST'
#!/bin/bash
# Install GSD CLI globally
npm install -g get-shit-done-cc || true

# Install GSD integration files to /etc/skel/.claude/ for future users
# Run the installer targeting a temp HOME, then copy to /etc/skel
export HOME_BACKUP="$HOME"
export HOME="/tmp/gsd-skel-install"
mkdir -p "$HOME"
npx get-shit-done-cc@latest --claude --global 2>/dev/null || true

# Copy integration files to /etc/skel
if [ -d "$HOME/.claude" ]; then
  mkdir -p /etc/skel/.claude
  cp -r "$HOME/.claude/"* /etc/skel/.claude/
  # Fix Node.js paths in settings.json to use system Node
  if [ -f /etc/skel/.claude/settings.json ]; then
    sed -i "s|$HOME|/home/USER_PLACEHOLDER|g" /etc/skel/.claude/settings.json
    # Replace any hardcoded node paths with /usr/bin/node
    sed -i 's|/tmp/gsd-skel-install/[^ ]*/node|/usr/bin/node|g' /etc/skel/.claude/settings.json
    sed -i 's|"/home/[^"]*/.local/share/fnm/[^"]*/node"|"/usr/bin/node"|g' /etc/skel/.claude/settings.json
  fi
fi

# Clean temp install
rm -rf "$HOME"
export HOME="$HOME_BACKUP"

# Apply to existing users
for homedir in /home/*/; do
  [ -d "$homedir" ] || continue
  username=$(basename "$homedir")
  if [ -d /etc/skel/.claude ]; then
    cp -r /etc/skel/.claude/ "${homedir}.claude/"
    # Fix paths for this specific user
    if [ -f "${homedir}.claude/settings.json" ]; then
      sed -i "s|/home/USER_PLACEHOLDER|${homedir%/}|g" "${homedir}.claude/settings.json"
    fi
    chown -R "$username:$username" "${homedir}.claude/"
  fi
done
POSTINST

cat > /tmp/postrm-gsd.sh <<'POSTRM'
#!/bin/bash
npm uninstall -g get-shit-done-cc || true
# Remove GSD files from /etc/skel
rm -rf /etc/skel/.claude/get-shit-done
rm -rf /etc/skel/.claude/commands/gsd
rm -rf /etc/skel/.claude/agents
rm -rf /etc/skel/.claude/hooks
rm -f /etc/skel/.claude/gsd-file-manifest.json
# Remove from existing users
for homedir in /home/*/; do
  [ -d "$homedir" ] || continue
  rm -rf "${homedir}.claude/get-shit-done"
  rm -rf "${homedir}.claude/commands/gsd"
  rm -rf "${homedir}.claude/agents"
  rm -rf "${homedir}.claude/hooks"
  rm -f "${homedir}.claude/gsd-file-manifest.json"
done
POSTRM

chmod 755 /tmp/postinst-gsd.sh /tmp/postrm-gsd.sh

fpm -s dir -t deb \
  --name agentlinux-gsd \
  --version 1.0.0 \
  --architecture amd64 \
  --depends "nodejs (>= 22)" \
  --depends "agentlinux-claude-code" \
  --description "GSD framework for Claude Code on AgentLinux" \
  --maintainer "AgentLinux" \
  --after-install /tmp/postinst-gsd.sh \
  --after-remove /tmp/postrm-gsd.sh \
  --deb-no-default-config-files \
  -C /tmp/pkg-gsd \
  .

# --------------------------------------------------------------------------
# Package 3: agentlinux-chrome-devtools-mcp
# --------------------------------------------------------------------------
mkdir -p /tmp/pkg-chrome-mcp

cat > /tmp/postinst-chrome-mcp.sh <<'POSTINST'
#!/bin/bash
# Install MCP server globally
npm install -g chrome-devtools-mcp || true

# MCP config entry
MCP_ENTRY='{"mcpServers":{"chrome-devtools":{"command":"npx","args":["-y","chrome-devtools-mcp@latest","--headless","--no-sandbox"]}}}'

merge_mcp_config() {
  local target="$1"
  local dir=$(dirname "$target")
  mkdir -p "$dir"
  if [ -f "$target" ]; then
    jq -s '.[0] * .[1]' "$target" <(echo "$MCP_ENTRY") > "${target}.tmp" && mv "${target}.tmp" "$target"
  else
    echo "$MCP_ENTRY" | jq . > "$target"
  fi
}

# Apply to all existing users' ~/.claude.json
for homedir in /home/*/; do
  [ -d "$homedir" ] || continue
  merge_mcp_config "${homedir}.claude.json"
  chown $(stat -c '%U:%G' "$homedir") "${homedir}.claude.json"
done

# Apply to /etc/skel for future users
merge_mcp_config /etc/skel/.claude.json
POSTINST

cat > /tmp/postrm-chrome-mcp.sh <<'POSTRM'
#!/bin/bash
npm uninstall -g chrome-devtools-mcp || true

remove_mcp_config() {
  local target="$1"
  [ -f "$target" ] || return 0
  if command -v jq &>/dev/null; then
    jq 'del(.mcpServers["chrome-devtools"])' "$target" > "${target}.tmp" && mv "${target}.tmp" "$target"
  fi
}

for homedir in /home/*/; do
  [ -d "$homedir" ] || continue
  remove_mcp_config "${homedir}.claude.json"
done
remove_mcp_config /etc/skel/.claude.json
POSTRM

chmod 755 /tmp/postinst-chrome-mcp.sh /tmp/postrm-chrome-mcp.sh

fpm -s dir -t deb \
  --name agentlinux-chrome-devtools-mcp \
  --version 1.0.0 \
  --architecture amd64 \
  --depends "nodejs (>= 22)" \
  --depends "google-chrome-stable" \
  --depends "jq" \
  --description "Chrome DevTools MCP server for AgentLinux" \
  --maintainer "AgentLinux" \
  --after-install /tmp/postinst-chrome-mcp.sh \
  --after-remove /tmp/postrm-chrome-mcp.sh \
  --deb-no-default-config-files \
  -C /tmp/pkg-chrome-mcp \
  .

###############################################################################
# Section D: Create local apt repository
###############################################################################
apt-get install -y jq  # Needed by chrome-devtools-mcp postinst
mkdir -p /opt/agentlinux/apt-repo
cp /tmp/agentlinux-*.deb /opt/agentlinux/apt-repo/
cd /opt/agentlinux/apt-repo
dpkg-scanpackages -m . /dev/null > Packages
gzip -9c Packages > Packages.gz
echo "deb [trusted=yes] file:///opt/agentlinux/apt-repo ./" > /etc/apt/sources.list.d/agentlinux.list
apt-get update

###############################################################################
# Verification
###############################################################################
echo "=== Verification ==="
node --version
npm --version
fpm --version
ls -la /opt/agentlinux/apt-repo/*.deb
cat /opt/agentlinux/apt-repo/Packages | grep "^Package:"
apt-cache show agentlinux-claude-code
apt-cache show agentlinux-gsd
apt-cache show agentlinux-chrome-devtools-mcp
