# Architecture Patterns

**Domain:** Agent-focused Linux distribution image build
**Researched:** 2026-03-10

## Recommended Architecture

### System Overview

```
Build Machine                          Target VM (OpenNebula/KVM)
+---------------------------+          +--------------------------------+
| Packer (HCL templates)   |          | Debian 12 Bookworm             |
| + QEMU plugin            |  builds  | + one-context (contextualization)|
| + shell provisioners     | -------> | + Node.js 22 LTS (NodeSource)  |
| + file provisioners      |          | + agentlinux-claude-code.deb   |
|                           |          | + agentlinux-gsd.deb           |
| fpm (deb builder)         |          | + agentlinux-chrome-mcp.deb    |
| + npm install --prefix    |          | + google-chrome-stable          |
| + staged directory tree   |          | + agent user (SSH-ready)       |
+---------------------------+          +--------------------------------+
```

### Repository Layout

```
agent-linux/
  packer/
    agentlinux.pkr.hcl          # Main Packer template
    variables.pkr.hcl           # Variable definitions
    http/                       # Files served during build (cloud-init)
    scripts/
      01-base.sh                # Base system config (locale, timezone, apt)
      02-nodesource.sh          # Install NodeSource repo + Node.js 22
      03-one-context.sh         # Install OpenNebula contextualization
      04-agent-user.sh          # Create agent user, sudo, shell config
      05-packages.sh            # Install .deb packages built by fpm
      06-chrome.sh              # Install Google Chrome for MCP server
      99-cleanup.sh             # Remove build artifacts, zero free space
  packages/
    build-all.sh                # Master build script for all .deb packages
    claude-code/
      build.sh                  # fpm build script
      wrapper.sh                # /usr/local/bin/claude wrapper
    gsd/
      build.sh
      wrapper.sh
    chrome-devtools-mcp/
      build.sh
      wrapper.sh
  Makefile                      # Top-level: `make packages`, `make image`, `make all`
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| Packer template | Defines VM specs, boot sequence, provisioner order | QEMU (via plugin), provisioner scripts |
| Shell provisioners | Configure base OS, install packages | apt, dpkg, NodeSource, one-context |
| fpm build scripts | Create .deb packages from npm packages | npm (install), fpm (package), output .deb files |
| Wrapper scripts | Provide clean CLI entry points for agent tools | Node.js runtime, bundled npm packages |
| one-context | First-boot VM configuration | OpenNebula API (via context CD-ROM) |
| Makefile | Orchestrates full build pipeline | fpm scripts, Packer |

### Data Flow

**Build pipeline:**
1. `make packages` -- runs fpm to build .deb files from npm packages
2. `make image` -- runs Packer, which:
   a. Downloads Debian 12 genericcloud QCOW2
   b. Boots VM with QEMU
   c. Runs provisioner scripts in order (01-base through 99-cleanup)
   d. Scripts copy and install pre-built .deb files
   e. Shuts down VM, outputs compressed QCOW2
3. Output: `output/agentlinux-0.2.0-amd64.qcow2`

**Runtime (first boot on OpenNebula):**
1. OpenNebula attaches context CD-ROM to VM
2. one-context reads context, configures networking
3. one-context injects SSH authorized_keys for `agent` user
4. one-context sets hostname
5. Agent connects via SSH as `agent` user
6. `claude`, `gsd`, `chrome-devtools-mcp` available on PATH

## Patterns to Follow

### Pattern 1: Layered Provisioning Scripts
**What:** Numbered shell scripts (01-base.sh, 02-nodesource.sh, etc.) each handling one concern.
**When:** Always -- this is the provisioning model.
**Why:** Each script handles one concern, debuggable individually, ordered execution is explicit in naming.

```hcl
# In agentlinux.pkr.hcl
provisioner "shell" {
  scripts = [
    "scripts/01-base.sh",
    "scripts/02-nodesource.sh",
    "scripts/03-one-context.sh",
    "scripts/04-agent-user.sh",
    "scripts/05-packages.sh",
    "scripts/06-chrome.sh",
    "scripts/99-cleanup.sh"
  ]
}
```

### Pattern 2: Staged Directory for fpm
**What:** Create a staging directory that mirrors the target filesystem, then pass it to fpm.
**When:** Building every .deb package.
**Why:** Full control over file placement. fpm's `--chdir` + dir source type maps the staging directory into the .deb.

```bash
# packages/claude-code/build.sh
STAGING=$(mktemp -d)
PKG_DIR="$STAGING/opt/agentlinux/claude-code"
BIN_DIR="$STAGING/usr/local/bin"

mkdir -p "$PKG_DIR" "$BIN_DIR"
npm install --prefix "$PKG_DIR" --omit=dev @anthropic-ai/claude-code
cp wrapper.sh "$BIN_DIR/claude"
chmod +x "$BIN_DIR/claude"

fpm -s dir -t deb \
  --name agentlinux-claude-code \
  --version "$(jq -r .version "$PKG_DIR/node_modules/@anthropic-ai/claude-code/package.json")" \
  --depends "nodejs (>= 22)" \
  --description "Claude Code - AI coding agent" \
  --maintainer "AgentLinux <packages@agentlinux.org>" \
  --url "https://agentlinux.org" \
  --chdir "$STAGING" \
  .
```

### Pattern 3: Wrapper Scripts for PATH Integration
**What:** Thin shell scripts in `/usr/local/bin/` that invoke the bundled Node.js entry point.
**When:** Every npm-based .deb package.
**Why:** Clean PATH integration, can set environment variables, handles the `/opt/agentlinux/` indirection.

```bash
#!/bin/bash
# /usr/local/bin/claude
exec /usr/bin/node /opt/agentlinux/claude-code/node_modules/.bin/claude "$@"
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Global npm Install in Image
**What:** Running `npm install -g @anthropic-ai/claude-code` during Packer provisioning.
**Why bad:** Fragile, not tracked by dpkg, upgrade/removal is manual, version conflicts between tools.
**Instead:** Bundle in .deb packages with fpm.

### Anti-Pattern 2: Building from ISO
**What:** Starting Packer build from a Debian netinst ISO with preseed.
**Why bad:** Slow (full install), complex (preseed is arcane), unnecessary when official cloud images exist.
**Instead:** Use `disk_image: true` with Debian genericcloud QCOW2.

### Anti-Pattern 3: cloud-init + one-context Together
**What:** Installing both cloud-init and one-context in the image.
**Why bad:** They conflict -- both try to manage networking, hostname, SSH keys on first boot. Race conditions.
**Instead:** Use one-context only. Remove cloud-init from the Debian cloud image during build.

### Anti-Pattern 4: Root-Only Access
**What:** Only providing root SSH access.
**Why bad:** Agents should run as unprivileged user. Root access is a security risk.
**Instead:** Create `agent` user with sudo, disable root SSH login.

## Scalability Considerations

| Concern | v0.2.0 (now) | v0.3.0+ (future) |
|---------|--------------|-------------------|
| Package distribution | Pre-installed in image | Local apt repository, PPA |
| Package updates | Rebuild image | apt update/upgrade |
| Image variants | Single amd64 QCOW2 | Multi-arch, multiple formats |
| Build automation | Makefile + local build | CI/CD pipeline (GitHub Actions) |
| Configuration | one-context defaults | Custom contextualization scripts |

## Sources

- [Packer QEMU Builder Docs](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu)
- [OpenNebula one-apps Repository](https://github.com/OpenNebula/one-apps)
- [fpm Getting Started](https://fpm.readthedocs.io/en/latest/getting-started.html)
- [Packer KVM Debian Example](https://github.com/fteychene/packer-kvm-debian-sample)
- [Packer KVM Multi-Distro Templates](https://github.com/goffinet/packer-kvm)
