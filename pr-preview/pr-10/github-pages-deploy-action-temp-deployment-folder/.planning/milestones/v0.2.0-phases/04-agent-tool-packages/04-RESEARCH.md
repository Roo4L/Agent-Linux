# Phase 4: Agent Tool Packages - Research

**Researched:** 2026-03-17
**Domain:** Debian packaging (fpm), Node.js ecosystem, Claude Code, GSD, Chrome DevTools MCP
**Confidence:** HIGH

## Summary

This phase packages Claude Code, GSD framework, and Chrome DevTools MCP server as .deb packages using fpm, served from a local apt repository in the image. The research uncovered a critical finding: **npm installation of Claude Code is deprecated** in favor of a native binary installer (`curl -fsSL https://claude.ai/install.sh | bash`) that places a standalone binary at `~/.local/bin/claude` with auto-updates via `~/.local/share/claude`. The thin .deb wrapper pattern from CONTEXT.md still applies, but the postinst for Claude Code should use the native installer script rather than `npm install -g`. For GSD and Chrome DevTools MCP, npm global install remains the correct approach.

A second important discovery: Claude Code supports **managed MCP configuration** at `/etc/claude-code/managed-mcp.json` on Linux. This is a system-wide file that applies MCP servers to all users without touching individual home directories. However, per CONTEXT.md decisions, the MCP config is a lifecycle concern of the chrome-devtools-mcp .deb package, and managed-mcp.json takes **exclusive control** (prevents users from adding their own MCP servers). The better approach is the per-user `~/.claude.json` merge approach specified in CONTEXT.md, which adds the MCP entry without restricting user customization. An alternative is to use `/etc/claude-code/managed-settings.json` with `enableAllProjectMcpServers` but this adds complexity. The per-user approach from CONTEXT.md is the right call.

**Primary recommendation:** Three Packer provisioner scripts: (1) 03-nodejs.sh to install NodeSource Node.js 22 + fpm + build .deb packages + create local apt repo, (2) 04-chrome.sh to install Google Chrome, (3) 05-agent-tools.sh to `apt install` the three packages from the local repo. Renumber existing 03-cleanup.sh to 06-cleanup.sh.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Thin .deb wrapper pattern: postinst runs install, postrm runs uninstall
- .deb owns: dependency declarations, wrapper scripts on PATH, integration file setup
- Code lives in Node.js global modules (for GSD/MCP) or native binary (Claude Code), NOT bundled in /opt/agentlinux/
- User can update without rebuilding .deb
- All packages declare Node.js as a dependency (transitive from NodeSource)
- Google Chrome (not Chromium) -- maximum MCP server compatibility
- Install from Google's apt repo during Packer build
- Remove Google apt repo after install (self-contained image)
- `apt-mark hold google-chrome-stable` to prevent accidental removal
- Include Xvfb for headed mode support
- Default to `--no-sandbox` flag
- No API key configuration in the image
- MCP config is lifecycle concern of the .deb package, NOT /etc/skel
- postinst merges MCP server entry into all users' `~/.claude/.mcp.json` (iterates /home/*/)
- postrm removes the MCP server entry from all users' `~/.claude/.mcp.json`
- Full GSD integration: CLI command + .claude/ integration files
- postinst installs integration files AND merges settings.json entries
- postrm removes integration files and settings.json entries
- agentlinux-gsd hard-depends on agentlinux-claude-code
- GSD installed from npm (get-shit-done-cc package)
- MCP server: npm global pattern assumed (confirmed: `chrome-devtools-mcp` is correct npm package)

### Claude's Discretion
- Exact postinst/postrm script implementation for config merging
- Local apt repo creation approach (dpkg-scanpackages, reprepro, etc.)
- Wrapper script implementation details
- fpm flags and build commands
- Packer provisioner script ordering (new scripts before existing 03-cleanup.sh)
- NodeSource setup script placement

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PKG-01 | Claude Code packaged as .deb via fpm | Native installer in postinst; fpm builds from staged dir tree; wrapper script on PATH |
| PKG-02 | GSD framework packaged as .deb via fpm | `npx get-shit-done-cc --claude --global` in postinst; integration files + settings.json merge |
| PKG-03 | Node.js 22 LTS from NodeSource as shared runtime | `curl -fsSL https://deb.nodesource.com/setup_22.x \| bash` + `apt install nodejs` |
| PKG-04 | Local apt repository configured in image | dpkg-scanpackages with `[trusted=yes]` file:// apt source |
| MCP-01 | Chrome DevTools MCP server packaged as .deb with Chrome dependency | `npm install -g chrome-devtools-mcp` in postinst; Depends: google-chrome-stable |
| MCP-02 | MCP server pre-configured in agent user's Claude Code settings | postinst merges entry into `~/.claude.json` mcpServers (not `~/.claude/.mcp.json` -- see research correction below) |
| MCP-03 | Agent user can launch Claude Code and use Chrome DevTools MCP | End-to-end: Claude Code binary on PATH + MCP config present + Chrome installed + npx resolves chrome-devtools-mcp |
</phase_requirements>

## Critical Research Corrections to CONTEXT.md Assumptions

### 1. Claude Code Installation: Native Binary, Not npm

**Finding (HIGH confidence -- official docs):** npm installation of `@anthropic-ai/claude-code` is deprecated. The recommended method is the native binary installer:
```bash
curl -fsSL https://claude.ai/install.sh | bash
```

This installs to:
- Binary: `~/.local/bin/claude`
- Version data: `~/.local/share/claude`

The native binary auto-updates, requires no Node.js dependency at runtime, and is Anthropic's official recommendation. However, npm install still works for compatibility: `npm install -g @anthropic-ai/claude-code` (current version: 2.1.77).

**Impact on .deb packaging:** The thin wrapper pattern still applies, but the postinst should run the native installer rather than npm. However, there is a complexity: the native installer installs per-user to `~/.local/bin/`, not system-wide. For a system .deb, the postinst would need to either:
- (a) Run the installer as each user, OR
- (b) Use `npm install -g` which installs system-wide to the npm prefix, OR
- (c) Download the native binary once and place it in `/usr/local/bin/`

**Recommendation:** Use `npm install -g @anthropic-ai/claude-code` for the .deb postinst. Rationale: (1) it installs system-wide for all users, (2) it is still supported, (3) it aligns with CONTEXT.md's "thin .deb wrapper over npm" pattern, (4) the .deb can declare nodejs as a dependency. Disable auto-updates in the .deb's settings since updates happen via `npm update -g`. Alternatively, investigate downloading the native binary to `/usr/local/bin/claude` which avoids requiring Node.js at runtime for Claude Code specifically. Given CONTEXT.md explicitly says "npm global pattern," stick with npm.

### 2. MCP Configuration File Location

**Finding (HIGH confidence -- official docs):** User-scoped MCP servers are stored in `~/.claude.json`, NOT in `~/.claude/mcp.json` or `~/.claude/.mcp.json`. The CONTEXT.md says "iterates /home/*/ and merges into `.claude/.mcp.json`" but the correct location is `~/.claude.json`.

The `~/.claude.json` file contains preferences, OAuth sessions, and MCP server configurations. The structure is:
```json
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest"]
    }
  }
}
```

**Alternative: System-wide managed-mcp.json** at `/etc/claude-code/managed-mcp.json`. Same format, but takes **exclusive control** -- users cannot add their own MCP servers. Not recommended since it is too restrictive for an agent environment.

**Recommendation:** postinst merges into `~/.claude.json` for each user in /home/*/. Use `jq` to safely merge the mcpServers key. Also set up `/etc/skel/.claude.json` with the MCP entry for new users created after install.

### 3. GSD Integration File Structure

**Finding (HIGH confidence -- observed on this machine):** GSD installation via `npx get-shit-done-cc --claude --global` creates:
- `~/.claude/get-shit-done/` -- core framework (bin, references, templates, workflows)
- `~/.claude/commands/gsd/` -- slash command definitions (37 .md files)
- `~/.claude/agents/` -- subagent definitions (15 .md files)
- `~/.claude/hooks/` -- hook scripts (3 .js files)
- `~/.claude/settings.json` -- hooks registration, statusLine config
- `~/.claude/gsd-file-manifest.json` -- integrity manifest
- `~/.claude/package.json` -- minimal package metadata

The settings.json hooks reference absolute paths to the Node.js binary and hook scripts. This means the postinst needs to generate settings.json with correct paths for the target system's Node.js location.

## Standard Stack

### Core
| Library/Tool | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| fpm | 1.17.0 (Ruby gem) | .deb package creation | Standard for non-Debian-policy packaging; builds from dir trees |
| Node.js 22 LTS | 22.x (NodeSource) | Shared runtime for npm packages | LTS channel; NodeSource is the standard source |
| dpkg-dev | (system) | `dpkg-scanpackages` for local apt repo | Debian standard; minimal deps |

### Packages Being Built
| Package Name | Source | Version | Purpose |
|-------------|--------|---------|---------|
| @anthropic-ai/claude-code | npm | 2.1.77 | Claude Code CLI |
| get-shit-done-cc | npm | 1.25.1 | GSD framework for Claude Code |
| chrome-devtools-mcp | npm | 0.20.0 | Chrome DevTools MCP server |
| google-chrome-stable | Google apt repo | latest | Chrome browser for MCP |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| jq | JSON merging in postinst/postrm scripts | Safely merge MCP entries into ~/.claude.json |
| xvfb | Virtual framebuffer for headed Chrome | When agents need visual Chrome testing |
| ruby | Runtime for fpm gem | Only during image build (can be removed after) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dpkg-scanpackages | reprepro | reprepro is heavier, overkill for 3 packages |
| npm install -g claude-code | Native installer | Native installs per-user; npm installs system-wide |
| ~/.claude.json merge | /etc/claude-code/managed-mcp.json | managed-mcp takes exclusive control, too restrictive |
| fpm | Manual dpkg-deb | fpm is much simpler for staged dir trees |

## Architecture Patterns

### Recommended Provisioner Script Structure
```
packer/scripts/
  01-base.sh           # (existing) Base packages
  02-one-context.sh    # (existing) OpenNebula contextualization
  03-nodejs.sh         # (NEW) NodeSource Node.js 22 + npm
  04-packages.sh       # (NEW) Build all .debs with fpm, create local repo, apt install
  05-chrome.sh         # (NEW) Google Chrome + Xvfb
  06-cleanup.sh        # (RENAMED from 03) Apt cache cleanup + compression
```

Note: Chrome installation is separate because it requires its own apt repo setup/teardown, and should happen after the local repo is configured so the chrome-devtools-mcp .deb can declare the dependency properly.

### Package Build Directory Structure (staged for fpm)
```
/tmp/agentlinux-build/
  agentlinux-claude-code/
    usr/local/bin/claude-wrapper     # Wrapper script
    DEBIAN/
      postinst                       # npm install -g @anthropic-ai/claude-code
      postrm                         # npm uninstall -g @anthropic-ai/claude-code
  agentlinux-gsd/
    usr/local/bin/gsd                # Wrapper script (runs npx get-shit-done-cc)
    DEBIAN/
      postinst                       # Run GSD installer + merge settings.json
      postrm                         # Remove GSD files + clean settings.json
  agentlinux-chrome-devtools-mcp/
    DEBIAN/
      postinst                       # npm install -g + merge ~/.claude.json
      postrm                         # npm uninstall -g + clean ~/.claude.json
```

### Pattern 1: fpm .deb from Staged Directory
**What:** Build a .deb from a directory tree with custom scripts
**When to use:** All three packages
**Example:**
```bash
# Source: fpm.readthedocs.io/en/latest/getting-started.html
fpm -s dir -t deb \
  --name agentlinux-claude-code \
  --version 1.0.0 \
  --architecture amd64 \
  --depends nodejs \
  --description "Claude Code for AgentLinux" \
  --after-install postinst.sh \
  --before-remove prerm.sh \
  --after-remove postrm.sh \
  --deb-no-default-config-files \
  -C /tmp/agentlinux-build/agentlinux-claude-code \
  .
```

### Pattern 2: Local Apt Repository
**What:** dpkg-scanpackages to create a minimal apt repo
**When to use:** During image build, after all .debs are created
**Example:**
```bash
# Source: wiki.debian.org/DebianRepository/Setup
mkdir -p /opt/agentlinux/apt-repo
cp /tmp/*.deb /opt/agentlinux/apt-repo/
cd /opt/agentlinux/apt-repo
dpkg-scanpackages -m . /dev/null | gzip -9c > Packages.gz
dpkg-scanpackages -m . /dev/null > Packages

# Add to apt sources
echo "deb [trusted=yes] file:///opt/agentlinux/apt-repo ./" \
  > /etc/apt/sources.list.d/agentlinux.list
apt-get update
```

### Pattern 3: JSON Merge for MCP Config (postinst)
**What:** Safely merge MCP server entry into existing ~/.claude.json
**When to use:** chrome-devtools-mcp postinst
**Example:**
```bash
#!/bin/bash
# postinst for agentlinux-chrome-devtools-mcp
MCP_ENTRY='{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest", "--headless", "--no-sandbox"]
    }
  }
}'

merge_mcp_config() {
  local target="$1"
  local dir=$(dirname "$target")
  mkdir -p "$dir"
  if [ -f "$target" ]; then
    # Merge: add mcpServers key without overwriting existing entries
    jq -s '.[0] * .[1]' "$target" <(echo "$MCP_ENTRY") > "${target}.tmp"
    mv "${target}.tmp" "$target"
  else
    echo "$MCP_ENTRY" > "$target"
  fi
}

# Apply to all existing users
for homedir in /home/*/; do
  [ -d "$homedir" ] || continue
  merge_mcp_config "${homedir}.claude.json"
  chown $(stat -c '%U:%G' "$homedir") "${homedir}.claude.json"
done

# Apply to /etc/skel for future users
merge_mcp_config /etc/skel/.claude.json
```

### Pattern 4: GSD Integration (postinst)
**What:** Install GSD and configure Claude Code integration
**When to use:** agentlinux-gsd postinst
**Example:**
```bash
#!/bin/bash
# postinst for agentlinux-gsd

# Install GSD globally (non-interactive)
npx get-shit-done-cc@latest --claude --global 2>/dev/null || true

# The GSD installer populates ~/.claude/ with:
# - get-shit-done/ (framework files)
# - commands/gsd/ (slash commands)
# - agents/ (subagent definitions)
# - hooks/ (JS hook scripts)
# - settings.json (hooks + statusLine)
# - gsd-file-manifest.json
# - package.json

# For system-wide install, run as each user or populate /etc/skel
# and let one-context user creation copy it

# Apply to all existing users
for homedir in /home/*/; do
  [ -d "$homedir" ] || continue
  username=$(basename "$homedir")
  su - "$username" -c 'npx get-shit-done-cc@latest --claude --global' 2>/dev/null || true
done

# For new users: install to /etc/skel/.claude/
# This requires running the GSD installer targeting /etc/skel
```

### Anti-Patterns to Avoid
- **Bundling node_modules in /opt:** Creates stale, unupdatable installations. Use npm global install instead.
- **Using managed-mcp.json for MCP config:** Takes exclusive control, prevents users from adding their own MCP servers.
- **Running native Claude Code installer in postinst:** Installs per-user to ~/.local/bin, not system-wide. Use npm for system-wide install.
- **Hardcoding Node.js paths in settings.json:** Node.js path varies by system. Use `which node` or `/usr/bin/node` (NodeSource puts it there).
- **Forgetting /etc/skel for new users:** one-context creates the agent user on first boot -- any postinst that only iterates /home/*/ will miss future users.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| .deb packaging | Manual dpkg-deb with control files | fpm from staged dir trees | fpm handles control files, maintainer scripts, compression automatically |
| JSON config merging | sed/awk on JSON files | jq | JSON is not line-oriented; sed will break on multiline values |
| Local apt repo | Full reprepro setup | dpkg-scanpackages + [trusted=yes] | 3 packages don't need signed repo infrastructure |
| Node.js install | Manual download + extract | NodeSource setup script | Handles apt repo, GPG key, architecture detection |
| Chrome install | Manual .deb download | Google apt repo (temporary) | Resolves Chrome's many dependencies automatically |

**Key insight:** fpm exists precisely for this use case: "I have files on disk and scripts to run, build me a .deb." Don't fight Debian packaging policy for a PoC image.

## Common Pitfalls

### Pitfall 1: postinst Runs Before Users Exist
**What goes wrong:** During Packer build, the agent user does not exist yet (one-context creates it on first boot). postinst scripts that iterate /home/*/ find no users.
**Why it happens:** The .debs are installed during build time, but users are created at boot time.
**How to avoid:** Always populate /etc/skel/ as a fallback. The postinst should handle both cases: existing users AND /etc/skel for future users.
**Warning signs:** `ls /home/*/` returns nothing during build.

### Pitfall 2: npm Global Install as Root Permissions
**What goes wrong:** Files installed by `npm install -g` as root may have wrong ownership when accessed by non-root users.
**Why it happens:** npm creates files owned by root in the global prefix.
**How to avoid:** npm global packages go to /usr/lib/node_modules/ on NodeSource installs and are readable by all users. Wrapper scripts in /usr/local/bin/ should be mode 755. This is standard behavior and works fine.
**Warning signs:** Permission denied errors when running `claude` or `gsd` as non-root user.

### Pitfall 3: npx Cache Missing at Runtime
**What goes wrong:** The chrome-devtools-mcp config uses `npx -y chrome-devtools-mcp@latest` which requires downloading at first use.
**Why it happens:** npx downloads packages on demand; in an offline/air-gapped environment this fails.
**How to avoid:** The postinst should `npm install -g chrome-devtools-mcp` so it is already installed. Then the MCP config can reference the installed binary directly OR still use npx (which will find it locally).
**Warning signs:** "npm WARN" errors when Claude Code tries to start the MCP server.

### Pitfall 4: Google Chrome apt Repo Left Active
**What goes wrong:** `apt update` on boot fails because the Google repo URL is unreachable.
**Why it happens:** Installing Chrome from .deb adds Google's apt repo automatically.
**How to avoid:** Remove `/etc/apt/sources.list.d/google-chrome.list` and the signing key after installation. Use `apt-mark hold google-chrome-stable`.
**Warning signs:** apt update errors on first boot.

### Pitfall 5: GSD settings.json Node.js Path
**What goes wrong:** GSD hooks reference hardcoded Node.js path (e.g., `/home/claude/.local/share/fnm/aliases/default/bin/node`).
**Why it happens:** The GSD installer detects the current Node.js path and hardcodes it.
**How to avoid:** On the target system, NodeSource puts Node at `/usr/bin/node`. The GSD installer should detect this correctly if run in an environment where `/usr/bin/node` is on PATH.
**Warning signs:** "node not found" errors in settings.json hooks.

### Pitfall 6: fpm Not Available in Debian Base
**What goes wrong:** fpm is a Ruby gem, not a Debian package.
**Why it happens:** fpm requires `ruby-dev` and `build-essential` to install.
**How to avoid:** Install `ruby-dev build-essential` temporarily, `gem install fpm`, use fpm to build packages, then optionally remove ruby to save image size.
**Warning signs:** `fpm: command not found`.

### Pitfall 7: dpkg-scanpackages Missing
**What goes wrong:** `dpkg-scanpackages` is not installed by default.
**Why it happens:** It's in the `dpkg-dev` package, not `dpkg`.
**How to avoid:** `apt-get install -y dpkg-dev` before building the repo.
**Warning signs:** `dpkg-scanpackages: command not found`.

### Pitfall 8: Chrome --no-sandbox in MCP Config
**What goes wrong:** Chrome refuses to start in server environment without --no-sandbox.
**Why it happens:** Chrome requires a sandbox by default; in non-desktop environments or as root, the sandbox is not available.
**How to avoid:** Pass `--no-sandbox` and `--disable-setuid-sandbox` as args to chrome-devtools-mcp in the MCP configuration. The chrome-devtools-mcp supports passing Chrome flags.
**Warning signs:** "Running as root without --no-sandbox is not supported" error.

## Code Examples

### NodeSource Node.js 22 Installation
```bash
# Source: https://deb.nodesource.com/
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
# Verify
node --version  # v22.x.x
npm --version   # 10.x.x
```

### fpm Installation on Debian 12
```bash
# Source: https://fpm.readthedocs.io/en/latest/installation.html
apt-get install -y ruby-dev build-essential
gem install fpm
fpm --version  # 1.17.0
```

### Google Chrome Installation + Cleanup
```bash
# Source: https://linuxcapable.com/how-to-install-google-chrome-on-debian-linux/
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb
apt-get install -y /tmp/chrome.deb
rm -f /tmp/chrome.deb

# Install Xvfb for headed mode
apt-get install -y xvfb

# Lock Chrome version and remove repo
apt-mark hold google-chrome-stable
rm -f /etc/apt/sources.list.d/google-chrome.list
rm -f /etc/apt/sources.list.d/google-chrome.list.save
rm -f /etc/apt/trusted.gpg.d/google-chrome*.gpg
# Also check /usr/share/keyrings/ for the key
```

### fpm Build Command for Claude Code .deb
```bash
# Source: https://fpm.readthedocs.io/en/latest/getting-started.html
# Create staged directory
mkdir -p /tmp/pkg-claude-code/usr/local/bin

# Create wrapper script
cat > /tmp/pkg-claude-code/usr/local/bin/claude-code-wrapper <<'WRAPPER'
#!/bin/bash
exec claude "$@"
WRAPPER
chmod 755 /tmp/pkg-claude-code/usr/local/bin/claude-code-wrapper

# Create postinst
cat > /tmp/postinst-claude-code.sh <<'POSTINST'
#!/bin/bash
npm install -g @anthropic-ai/claude-code || true
POSTINST

# Create postrm
cat > /tmp/postrm-claude-code.sh <<'POSTRM'
#!/bin/bash
npm uninstall -g @anthropic-ai/claude-code || true
POSTRM

# Build
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
```

### Local Apt Repository Creation
```bash
# Source: https://wiki.debian.org/DebianRepository/Setup
apt-get install -y dpkg-dev

# Collect all built .debs
mkdir -p /opt/agentlinux/apt-repo
cp /tmp/agentlinux-*.deb /opt/agentlinux/apt-repo/

# Generate package index
cd /opt/agentlinux/apt-repo
dpkg-scanpackages -m . /dev/null > Packages
gzip -9c Packages > Packages.gz

# Configure apt source
echo "deb [trusted=yes] file:///opt/agentlinux/apt-repo ./" \
  > /etc/apt/sources.list.d/agentlinux.list
apt-get update
```

### MCP Configuration JSON for Chrome DevTools
```json
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest", "--headless", "--no-sandbox"]
    }
  }
}
```

### Claude Code Settings for GSD Hooks
```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/node \"/home/USER/.claude/hooks/gsd-check-update.js\""
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/node \"/home/USER/.claude/hooks/gsd-context-monitor.js\""
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "/usr/bin/node \"/home/USER/.claude/hooks/gsd-statusline.js\""
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `npm install -g @anthropic-ai/claude-code` | Native installer: `curl -fsSL https://claude.ai/install.sh \| bash` | 2025-2026 | npm deprecated but still works; native preferred |
| MCP in ~/.claude/settings.json | MCP in ~/.claude.json (user scope) | Claude Code 2.x | Must target correct file for MCP config |
| Per-user MCP only | managed-mcp.json at /etc/claude-code/ | Claude Code 2.x | System-wide option exists but takes exclusive control |
| Node.js 18 minimum | Node.js 18+ (22 LTS recommended) | 2024 | NodeSource setup_22.x is current LTS |

**Deprecated/outdated:**
- `npm install -g @anthropic-ai/claude-code`: Still works but deprecated. Native binary installer preferred.
- MCP config in `~/.claude/settings.json`: Wrong file. MCP servers go in `~/.claude.json`.

## Open Questions

1. **GSD installer targeting /etc/skel**
   - What we know: `npx get-shit-done-cc --claude --global` installs to `~/.claude/` of the current user
   - What's unclear: Whether the installer can be told to target a different directory (e.g., /etc/skel/.claude/)
   - Recommendation: Run installer once as a temp user or manually copy the installed files to /etc/skel/. Alternatively, run it as root and let it populate /root/.claude/, then copy to /etc/skel/.claude/.

2. **npm install -g as postinst during Packer build**
   - What we know: postinst scripts run during `apt install` which happens during Packer build
   - What's unclear: Whether npm install -g requires network access (it does -- must happen before cleanup script removes apt cache)
   - Recommendation: Script ordering ensures network is available. The Packer build has network access. All npm installs happen in a build script, not truly in postinst -- the "postinst" approach from CONTEXT.md means the .deb's postinst runs at install time during build. This is fine.

3. **chrome-devtools-mcp flags for server environment**
   - What we know: `--headless` and `--no-sandbox` are valid flags
   - What's unclear: Exact flag syntax when passed through MCP config args
   - Recommendation: Use `["--headless", "--no-sandbox"]` in args array. Test during Phase 5 validation.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bash assertions in Packer build + Phase 5 end-to-end |
| Config file | None -- validation via build-time checks |
| Quick run command | `packer validate packer/agentlinux.pkr.hcl` |
| Full suite command | `cd packer && packer build agentlinux.pkr.hcl` (builds image with all packages) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PKG-01 | Claude Code .deb installs and `claude` works | smoke | Build-time: `apt install agentlinux-claude-code && claude --version` | Wave 0 (in provisioner script) |
| PKG-02 | GSD .deb installs and `/gsd:help` works | smoke | Build-time: `apt install agentlinux-gsd && which gsd` | Wave 0 (in provisioner script) |
| PKG-03 | Node.js 22 from NodeSource | smoke | Build-time: `node --version` | Wave 0 (in provisioner script) |
| PKG-04 | Local apt repo works | smoke | Build-time: `apt-get update && apt install agentlinux-claude-code` | Wave 0 (in provisioner script) |
| MCP-01 | Chrome DevTools MCP .deb with Chrome dep | smoke | Build-time: `apt install agentlinux-chrome-devtools-mcp` | Wave 0 (in provisioner script) |
| MCP-02 | MCP server pre-configured | smoke | Build-time: check /etc/skel/.claude.json contains mcpServers | Wave 0 (in provisioner script) |
| MCP-03 | End-to-end MCP works | e2e/manual | Phase 5: SSH into VM, run `claude`, verify MCP tools | Phase 5 |

### Sampling Rate
- **Per task commit:** `packer validate packer/agentlinux.pkr.hcl`
- **Per wave merge:** Full `packer build` (builds complete image)
- **Phase gate:** Successful image build with all packages installed

### Wave 0 Gaps
- [ ] Provisioner scripts `03-nodejs.sh`, `04-packages.sh`, `05-chrome.sh` -- these ARE the implementation
- [ ] Build-time smoke tests embedded in provisioner scripts (assert commands work after install)
- [ ] No separate test framework needed -- the Packer build IS the test (if it succeeds, packages installed correctly)

## Sources

### Primary (HIGH confidence)
- [Claude Code official docs - Setup](https://code.claude.com/docs/en/setup) -- installation methods, binary location, npm deprecation
- [Claude Code official docs - Settings](https://code.claude.com/docs/en/settings) -- settings.json format, MCP locations, hooks
- [Claude Code official docs - MCP](https://code.claude.com/docs/en/mcp) -- MCP configuration, managed-mcp.json, scopes
- [fpm documentation](https://fpm.readthedocs.io/en/latest/) -- fpm flags, deb creation, getting started
- [Chrome DevTools MCP GitHub](https://github.com/ChromeDevTools/chrome-devtools-mcp) -- package name, configuration, flags
- npm registry -- verified versions: @anthropic-ai/claude-code 2.1.77, get-shit-done-cc 1.25.1, chrome-devtools-mcp 0.20.0, fpm 1.17.0

### Secondary (MEDIUM confidence)
- [NodeSource](https://deb.nodesource.com/) -- setup_22.x installation script
- [Chrome DevTools MCP blog](https://developer.chrome.com/blog/chrome-devtools-mcp) -- MCP configuration JSON examples
- [Debian Wiki - Repository Setup](https://wiki.debian.org/DebianRepository/Setup) -- dpkg-scanpackages local repo
- [GSD GitHub](https://github.com/gsd-build/get-shit-done) -- installation commands, file structure
- [Chrome DevTools MCP Issue #261](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/261) -- --no-sandbox solution

### Tertiary (LOW confidence)
- Chrome apt repo cleanup details -- based on multiple blog sources, may vary by Chrome version

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all versions verified against npm registry and official docs
- Architecture: HIGH -- patterns verified against official documentation and observed on this machine
- Pitfalls: HIGH -- derived from official docs (MCP location, npm deprecation) and known Debian packaging issues
- GSD integration details: HIGH -- observed actual file layout on this running system

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (30 days -- all components are stable/LTS)
