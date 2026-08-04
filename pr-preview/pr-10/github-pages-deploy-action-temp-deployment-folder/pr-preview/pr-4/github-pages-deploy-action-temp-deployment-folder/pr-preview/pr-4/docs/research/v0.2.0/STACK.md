# Technology Stack

**Project:** AgentLinux v0.2.0 -- First Distro Image
**Researched:** 2026-03-10
**Scope:** New capabilities only (image build, .deb packaging, OpenNebula contextualization)

## Recommended Stack

### Base Distribution

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Debian 12 (Bookworm) | 12.x (current stable) | Base OS for AgentLinux image | See rationale below |

**Why Debian 12 over Ubuntu:**

1. **Stability over freshness.** Agents need predictable environments. Debian stable's conservative approach means fewer surprise breakages. Ubuntu's 6-month cadence introduces churn that adds no value for an agent runtime.
2. **Minimal by default.** Debian's cloud images ship at ~352 MiB (QCOW2). No snap, no unattended-upgrades bloat, no Canonical telemetry. What you install is what you get.
3. **Genuine upstream.** Ubuntu is a Debian derivative. Building on Debian means one fewer layer of indirection. When debugging package issues, you are at the source.
4. **LTS longevity.** Debian 12 Bookworm has security support through June 2028, with Debian LTS extending to ~2028. No Ubuntu Pro upsell.
5. **OpenNebula alignment.** OpenNebula's own one-apps toolchain builds Debian images. The contextualization packages target Debian as a first-class citizen.
6. **Cloud image availability.** Official QCOW2 images at `cloud.debian.org/images/cloud/bookworm/latest/` -- both `generic` (with cloud-init) and `genericcloud` (smaller, cloud-only drivers) variants.

**Why NOT Alpine:** musl libc breaks too many npm native modules. Node.js ecosystem assumes glibc. Would create constant friction packaging agent tools.

**Why NOT Ubuntu:** Adds snap/snapd weight, Canonical-specific packaging quirks, and Ubuntu Pro nag screens. No meaningful advantage for a headless agent VM.

### Image Build Tooling

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| HashiCorp Packer | 1.15.0 | Automated QCOW2 image building | Industry standard, declarative HCL, QEMU/KVM native support |
| Packer QEMU Plugin | 1.1.4 | QEMU/KVM builder for Packer | Official HashiCorp plugin, outputs QCOW2 directly |
| QEMU/KVM | system package | VM runtime for image builds | Required by Packer QEMU builder |
| cloud-init | (bundled in Debian cloud image) | Initial boot configuration | Handles preseed during Packer build |

**Build approach:** Use Packer with QEMU builder starting from the official Debian 12 genericcloud QCOW2 image (`debian-12-genericcloud-amd64.qcow2`). This avoids building from ISO (slow, complex preseed) and instead customizes an already-minimal cloud image.

Key Packer configuration decisions:
- `disk_image: true` -- start from existing QCOW2, not ISO
- `format: "qcow2"` -- native output format for OpenNebula/KVM
- `disk_compression: true` -- reduce image size for distribution
- Provisioners: shell scripts + file provisioners (no Ansible dependency needed for v0.2.0)

### Package Building

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| fpm | 1.17.0 | Create .deb packages from directories | Simple, battle-tested, no Debian packaging expertise required |
| Ruby | system package | fpm runtime dependency | fpm is a Ruby gem |
| dpkg-deb | system package | .deb manipulation/verification | Standard Debian tool for inspecting built packages |

**Why fpm over alternatives:**

- **Over `npm2deb`:** npm2deb tries to create Debian-policy-compliant packages with proper dependency trees. This is noble but impractical -- you'd need to package every transitive npm dependency as a separate .deb. We're building a distro, not submitting to Debian archives.
- **Over `node-deb`:** node-deb is Node-specific and less maintained. fpm handles dir-to-deb, npm-to-deb, and arbitrary source types. More flexible for the Chrome DevTools MCP server package which has non-npm components.
- **Over manual `debian/` directory:** Overkill for v0.2.0. Full debian packaging (rules, control, changelog, etc.) is needed if we ever submit to a PPA. For now, fpm generates correct .deb structure from a staged directory tree.

### Node.js Runtime

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Node.js | 22.x LTS | Runtime for Claude Code, GSD, MCP server | Current LTS, required by @anthropic-ai/claude-code (Node 18+) |
| NodeSource deb repo | setup_22.x | Provide Node.js .deb packages | Official Node.js binary distribution for Debian, avoids ancient Debian-packaged Node.js |

**Node.js packaging strategy: bundled per-package, NodeSource as system dependency.**

Each .deb package for agent tools will:
1. Declare `nodejs (>= 22)` as a dependency (satisfied by NodeSource repo pre-configured in image)
2. Bundle the npm package + all `node_modules` inside the .deb at `/opt/agentlinux/<package-name>/`
3. Install a wrapper script to `/usr/local/bin/` that invokes node with the bundled entry point

This avoids: global npm installs (fragile), shared node_modules (version conflicts), system Node.js from Debian repos (Node.js 18.19 in Bookworm, too old and won't receive updates).

### OpenNebula Integration

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| one-context | 6.6.1 | OpenNebula VM contextualization | Official OpenNebula package, handles SSH keys, networking, hostname |

**What one-context does on first boot:**
- Reads OpenNebula context CD-ROM
- Configures network interfaces
- Injects SSH authorized_keys
- Sets hostname
- Runs custom START_SCRIPT if provided
- Manages user accounts

**Installation approach:** Download .deb from GitHub releases (`github.com/OpenNebula/addon-context-linux/releases`), install during Packer build. Replaces cloud-init (one-context and cloud-init conflict; one-context is what OpenNebula expects).

### Supporting Tools (Build-time only)

| Tool | Purpose | When Used |
|------|---------|-----------|
| qemu-utils | `qemu-img` for image inspection/conversion | Build verification |
| guestfs-tools | `virt-customize` for image inspection | Debugging/verification |
| shellcheck | Lint shell scripts in packages | CI/development |

## Target Package Inventory

| .deb Package | Wraps | Key Dependencies | Entry Point |
|--------------|-------|-----------------|-------------|
| `agentlinux-claude-code` | `@anthropic-ai/claude-code` (npm) | `nodejs (>= 22)` | `/usr/local/bin/claude` |
| `agentlinux-gsd` | `get-shit-done` (npm) | `nodejs (>= 22)` | `/usr/local/bin/gsd` |
| `agentlinux-chrome-devtools-mcp` | Chrome DevTools MCP server | `nodejs (>= 22)`, `google-chrome-stable` | `/usr/local/bin/chrome-devtools-mcp` |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Base distro | Debian 12 | Ubuntu 24.04 LTS | Snap bloat, Canonical telemetry, extra layer of indirection |
| Base distro | Debian 12 | Alpine Linux | musl libc breaks npm native modules, no systemd |
| Image builder | Packer + QEMU | virt-builder | Less ecosystem, harder to extend, no HCL declarative config |
| Image builder | Packer + QEMU | OpenNebula one-apps | Over-engineered for our use case (designed for marketplace appliances), Ruby/Make build system adds complexity |
| Image builder | Packer + QEMU | debootstrap + manual | No automation, not reproducible, error-prone |
| Image builder | Packer + QEMU | live-build | Designed for live/ISO images, not cloud QCOW2 |
| .deb builder | fpm | npm2deb | Requires packaging every transitive dep separately |
| .deb builder | fpm | node-deb | Less flexible, Node-only, less maintained |
| .deb builder | fpm | manual debian/ | Overkill for v0.2.0, high learning curve |
| Node.js source | NodeSource repo | Debian default nodejs | Bookworm ships Node 18.19, too old, no updates |
| Node.js source | NodeSource repo | nvm in image | Per-user, fragile, not suitable for system packages |
| Node.js source | NodeSource repo | Bundle Node.js binary in each .deb | Massive package size, update nightmare |
| Contextualization | one-context | cloud-init | OpenNebula prefers one-context, cloud-init conflicts |

## Installation / Build Dependencies

```bash
# On build machine (not in the image)

# Packer
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update && apt-get install -y packer

# QEMU for Packer builds
apt-get install -y qemu-system-x86 qemu-utils

# fpm for .deb packaging
apt-get install -y ruby ruby-dev gcc make
gem install fpm

# Node.js (for npm install during package building)
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
```

```bash
# Pre-installed in the AgentLinux image

# NodeSource Node.js 22.x LTS
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# OpenNebula contextualization
wget https://github.com/OpenNebula/addon-context-linux/releases/download/v6.6.1/one-context_6.6.1-1.deb
dpkg -i one-context_6.6.1-1.deb || apt-get install -fy

# Agent user setup
useradd -m -s /bin/bash -G sudo agent
```

## Confidence Assessment

| Component | Confidence | Rationale |
|-----------|------------|-----------|
| Debian 12 as base | HIGH | Official cloud images verified, OpenNebula docs confirm support, one-apps builds Debian |
| Packer 1.15.0 + QEMU plugin | HIGH | Official HashiCorp releases verified, extensive QCOW2 examples in ecosystem |
| fpm 1.17.0 for .deb | HIGH | RubyGems version confirmed, well-documented npm-to-deb workflow |
| NodeSource Node.js 22 LTS | HIGH | Official repo confirmed for Debian 12, standard approach |
| one-context 6.6.1 | MEDIUM | Version confirmed on GitHub releases, but v6.6.1 is from June 2024 -- may have newer release by build time |
| Bundled node_modules strategy | MEDIUM | Standard practice for non-Debian-archive packages, but needs testing with large packages like claude-code |

## Sources

- [Debian Official Cloud Images](https://cloud.debian.org/images/cloud/bookworm/latest/)
- [Packer QEMU Builder Documentation](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu)
- [Packer QEMU Plugin Releases](https://github.com/hashicorp/packer-plugin-qemu/releases)
- [HashiCorp Packer Releases](https://releases.hashicorp.com/packer/)
- [fpm Documentation](https://fpm.readthedocs.io/en/latest/)
- [fpm npm Package Support](https://fpm.readthedocs.io/en/v1.14.2/packages/npm.html)
- [fpm RubyGems Versions](https://rubygems.org/gems/fpm/versions)
- [OpenNebula addon-context-linux Releases](https://github.com/OpenNebula/addon-context-linux/releases)
- [OpenNebula one-apps Repository](https://github.com/OpenNebula/one-apps)
- [NodeSource Distributions](https://github.com/nodesource/distributions)
- [@anthropic-ai/claude-code on npm](https://www.npmjs.com/package/@anthropic-ai/claude-code)
- [Debian Wiki: Node.js Packaging](https://wiki.debian.org/Javascript/Nodejs)
- [node-deb on npm](https://www.npmjs.com/package/node-deb)
