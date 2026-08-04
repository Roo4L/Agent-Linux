# Project Research Summary

**Project:** AgentLinux v0.2.0 -- First Distro Image
**Domain:** Agent-focused Linux distribution (image build, .deb packaging, OpenNebula integration)
**Researched:** 2026-03-10
**Confidence:** HIGH

## Executive Summary

AgentLinux v0.2.0 is a purpose-built Linux distribution image that packages AI agent tools (Claude Code, GSD, Chrome DevTools MCP server) as native .deb packages on a minimal Debian 12 base, targeting OpenNebula/KVM infrastructure. This is fundamentally an image build and packaging project, not a software application. Experts in this space use Packer with QEMU for reproducible image creation, fpm for pragmatic .deb packaging (avoiding the complexity of full Debian archive compliance), and layered shell provisioners for image customization. The pattern is well-established and all recommended tools are mature.

The recommended approach is a two-stage build pipeline: first, use fpm to create .deb packages that bundle npm packages with their node_modules under `/opt/agentlinux/`, then use Packer to compose these packages into a Debian 12 QCOW2 image with OpenNebula contextualization. Each .deb provides a clean wrapper script on PATH, making agent tools feel like native Linux commands. The build is orchestrated by a Makefile with `make packages` and `make image` targets. Node.js 22 LTS from NodeSource serves as the shared system runtime dependency -- avoiding global npm installs (fragile), bundled Node.js binaries (wasteful), and Debian-policy-compliant npm packaging (impractical).

The primary risks are: (1) the cloud-init / one-context conflict that ships in Debian cloud images and must be resolved during build, (2) oversized .deb packages from unbounded node_modules trees, and (3) KVM access requirements for Packer builds that determine whether iteration cycles take 5 minutes or 5 hours. All three have straightforward mitigations. The riskiest individual feature is the Chrome DevTools MCP server package, which pulls in Chrome and its extensive library dependencies on a headless system. No novel or experimental technology is required.

## Key Findings

### Recommended Stack

The stack is entirely composed of mature, well-documented tools. Debian 12 Bookworm was chosen over Ubuntu (snap bloat, telemetry) and Alpine (musl libc breaks npm native modules). Node.js comes from NodeSource rather than Debian's stale packages (Bookworm ships Node 18.19). See `.planning/research/STACK.md` for full rationale and alternatives matrix.

**Core technologies:**
- **Debian 12 Bookworm**: base OS -- minimal cloud images (~352 MiB QCOW2), LTS through 2028, first-class OpenNebula support
- **Packer 1.15.0 + QEMU plugin 1.1.4**: image build -- declarative HCL, outputs QCOW2 directly from existing cloud image (`disk_image: true`)
- **fpm 1.17.0**: .deb packaging -- builds packages from staged directory trees, no Debian packaging expertise required
- **Node.js 22 LTS (NodeSource)**: agent tool runtime -- current LTS, required by Claude Code (Node 18+ minimum)
- **one-context 6.6.1**: OpenNebula contextualization -- handles SSH keys, networking, hostname on first boot

### Expected Features

See `.planning/research/FEATURES.md` for the complete feature landscape.

**Must have (table stakes):**
- Bootable QCOW2 image on KVM
- OpenNebula contextualization (SSH, networking, hostname)
- Agent user with SSH access
- Claude Code .deb package
- GSD framework .deb package
- Chrome DevTools MCP server .deb package
- Node.js 22 LTS pre-installed
- Automated, reproducible build (Packer + Makefile)

**Should have (differentiators):**
- Agent user as default persona (boots ready for agents, not human admins)
- Native apt-managed agent tools (no npm/pip fragility)
- Pre-configured tool paths (everything on PATH, no activation needed)
- Minimal attack surface (no desktop, no unnecessary services)

**Defer (v0.3.0+):**
- Local apt repository / PPA
- Package groups / workload bundles
- Multi-arch support (ARM)
- Auto-update mechanism
- Agent skills system
- Docker-in-Docker

### Architecture Approach

The architecture is a two-stage build pipeline with clear separation between package building (fpm) and image composition (Packer). The repository layout splits into `packages/` (per-tool build scripts and wrappers) and `packer/` (HCL template + numbered provisioner scripts). A top-level Makefile orchestrates both stages. At runtime, one-context handles first-boot configuration and agent tools are available as standard Linux commands. See `.planning/research/ARCHITECTURE.md` for component boundaries and data flow.

**Major components:**
1. **fpm build scripts** (`packages/*/build.sh`) -- create .deb packages from npm installs via staged directory trees
2. **Packer template** (`packer/agentlinux.pkr.hcl`) -- defines VM specs, provisioner order, output format
3. **Layered provisioners** (`packer/scripts/01-*.sh` through `99-*.sh`) -- each handles one concern (base config, NodeSource, one-context, agent user, packages, Chrome, cleanup)
4. **Wrapper scripts** (`/usr/local/bin/claude`, etc.) -- thin shims that invoke Node.js with bundled entry points
5. **Makefile** -- top-level orchestrator: `make packages`, `make image`, `make all`

### Critical Pitfalls

See `.planning/research/PITFALLS.md` for the full list (12 pitfalls across critical/moderate/minor).

1. **cloud-init / one-context conflict** -- purge cloud-init BEFORE installing one-context; both race to manage networking and SSH on first boot, causing unreliable access
2. **npm native module architecture mismatch** -- build .deb packages inside a Debian 12 environment matching the target image; cross-built native modules crash at runtime
3. **Packer KVM access required** -- verify `/dev/kvm` exists on build machine; without KVM acceleration, builds are 10-50x slower, making iteration impossible
4. **Oversized .deb packages** -- use `npm install --omit=dev`, prune aggressively, target each package under 100MB; unbounded node_modules creates 200-500MB packages
5. **Chrome headless missing libraries** -- install Chrome from Google's official .deb repo (properly declares deps), then `apt-get install -f`; test headless mode during build

## Implications for Roadmap

Based on research, the build has a clear dependency chain that dictates phase ordering. The image must boot before packages can be tested in it, and packages must be built before they can be installed in the image. The dependency graph is: KVM access -> Packer works -> base image boots -> one-context works -> SSH works -> packages can be tested.

### Phase 1: Packer + Base Image
**Rationale:** Everything depends on a working Packer build producing a bootable QCOW2. This is the longest feedback loop (3-10 min per cycle with KVM) and the gate for all subsequent work. Get it working first.
**Delivers:** Packer HCL template, QEMU plugin config, base provisioner scripts (01-base.sh, 99-cleanup.sh), Makefile skeleton, a bootable (but bare) Debian 12 QCOW2
**Addresses:** "Bootable QCOW2 image on KVM", "Automated/reproducible build"
**Avoids:** Packer KVM access pitfall (#3), SSH timeout pitfall (#7), disk space pitfall (#10)

### Phase 2: OpenNebula Integration + Agent User
**Rationale:** Before any tool packages can be tested on target infrastructure, the image must contextualize properly and provide SSH access. This is the second gate.
**Delivers:** one-context installation (03-one-context.sh), cloud-init removal, agent user creation (04-agent-user.sh), SSH access working on OpenNebula
**Addresses:** "OpenNebula contextualization", "Agent user with SSH access", "Agent user as default persona"
**Avoids:** cloud-init/one-context conflict (#1), one-context version mismatch (#6)

### Phase 3: Agent Tool Packaging
**Rationale:** With a working base image and SSH access, build and integrate the .deb packages. Do Claude Code first (proves the pattern), then GSD (same pattern, fast follow), then Chrome DevTools MCP (most complex due to Chrome dependency).
**Delivers:** Three .deb packages with fpm build scripts, wrapper scripts, NodeSource integration (02-nodesource.sh), packages provisioner (05-packages.sh, 06-chrome.sh)
**Addresses:** "Claude Code .deb", "GSD .deb", "Chrome DevTools MCP .deb", "Node.js 22 LTS pre-installed", "Native package manager for agent tools", "Pre-configured tool paths"
**Avoids:** Oversized packages (#4), native module mismatch (#2), Chrome headless deps (#9), package name collision (#8)

### Phase 4: Image Finalization + Validation
**Rationale:** Final integration testing, size optimization, and end-to-end validation on OpenNebula. Avoid debugging multiple variables at once by doing this after all components work individually.
**Delivers:** Production-ready QCOW2, `make all` working end-to-end, validation checklist, documented build process
**Addresses:** "Minimal attack surface", image size optimization, build reproducibility verification
**Avoids:** GPG key expiry (#5), locale issues (#11), big-bang integration failures

### Phase Ordering Rationale

- Packer first because it has the longest feedback loop and every other phase depends on a working image build
- OpenNebula integration second because SSH access is required to test anything in the running image
- Package building third because fpm work is partially independent (can build .debs without the image) but testing requires Phases 1-2
- Chrome DevTools MCP last within Phase 3 because it has the most system dependencies and is the least critical to the core concept
- Integration/finalization last to avoid debugging multiple variables simultaneously

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1:** Packer cloud-init user-data configuration for SSH during build -- the specific http_directory + user-data setup needs to be worked out for the Debian genericcloud base
- **Phase 2:** one-context configuration specifics should be validated against the target OpenNebula cluster version
- **Phase 3 (Chrome DevTools MCP):** Chrome headless on minimal Debian needs testing; the exact library dependency chain is the least predictable part of the build; the MCP server npm package name and entry point need identification

Phases with standard patterns (skip research-phase):
- **Phase 3 (Claude Code, GSD):** fpm dir-to-deb with staged directory is straightforward and well-documented
- **Phase 4:** Standard image verification and testing practices, no novel work

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All tools verified with official sources, versions confirmed, current releases |
| Features | HIGH | Tightly scoped by PROJECT.md, clear table stakes vs. defer boundaries |
| Architecture | HIGH | Two-stage pipeline (fpm then Packer) is the established pattern, multiple reference implementations |
| Pitfalls | HIGH | cloud-init/one-context conflict well-documented in OpenNebula forums; package size and KVM issues are standard knowledge |

**Overall confidence:** HIGH

### Gaps to Address

- **one-context version currency:** v6.6.1 is from June 2024; check for newer releases at build time and verify compatibility with the target OpenNebula cluster version
- **Claude Code package size:** Actual size of `@anthropic-ai/claude-code` with production dependencies is unknown until first `npm install --omit=dev`; if it exceeds 150MB, additional pruning strategies will be needed
- **Build machine KVM access:** KVM is mandatory but may not be available in all CI environments; validate early in Phase 1
- **Chrome version pinning:** Google Chrome updates frequently; decide whether to pin a specific version or use latest stable
- **Chrome DevTools MCP server identity:** The exact npm package name, version, and entry point for the MCP server need to be confirmed before Phase 3 planning

## Sources

### Primary (HIGH confidence)
- [Debian Official Cloud Images](https://cloud.debian.org/images/cloud/bookworm/latest/)
- [Packer QEMU Builder Documentation](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu)
- [Packer QEMU Plugin Releases](https://github.com/hashicorp/packer-plugin-qemu/releases)
- [fpm Documentation](https://fpm.readthedocs.io/en/latest/)
- [OpenNebula addon-context-linux Releases](https://github.com/OpenNebula/addon-context-linux/releases)
- [NodeSource Distributions](https://github.com/nodesource/distributions)
- [@anthropic-ai/claude-code on npm](https://www.npmjs.com/package/@anthropic-ai/claude-code)

### Secondary (MEDIUM confidence)
- [OpenNebula one-apps Repository](https://github.com/OpenNebula/one-apps) -- build patterns reference
- [Packer KVM Debian Example](https://github.com/fteychene/packer-kvm-debian-sample) -- template reference
- [Packer KVM Multi-Distro Templates](https://github.com/goffinet/packer-kvm) -- additional reference
- [OpenNebula Forum: one-context vs cloud-init](https://forum.opennebula.io/t/one-context-vs-cloud-init/1641) -- conflict documentation
- [fpm RubyGems Versions](https://rubygems.org/gems/fpm/versions)

### Tertiary (LOW confidence)
- [fpm npm Package Support](https://fpm.readthedocs.io/en/v1.14.2/packages/npm.html) -- older docs version, patterns still apply
- [Debian Wiki: Node.js Packaging](https://wiki.debian.org/Javascript/Nodejs) -- context only, we are not following Debian policy packaging

---
*Research completed: 2026-03-10*
*Ready for roadmap: yes*
