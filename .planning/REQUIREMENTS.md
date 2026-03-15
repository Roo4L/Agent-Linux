# Requirements: AgentLinux

**Defined:** 2026-03-15
**Core Value:** An agent can boot into a Linux environment that works out of the box — no setup, no permission fights, no missing tools — with agent software available via the system package manager.

## v0.2.0 Requirements

Requirements for the first distro image. Each maps to roadmap phases.

### Image Build

- [ ] **IMG-01**: Packer builds a bootable Debian 12 QCOW2 image from the official cloud base image
- [ ] **IMG-02**: Built image boots successfully on KVM/QEMU

### OpenNebula Integration

- [ ] **ONE-01**: Image includes one-context package (cloud-init purged) for SSH key injection and network configuration
- [ ] **ONE-02**: Image deploys and contextualizes correctly on OpenNebula

### Agent User

- [ ] **USR-01**: Non-root agent user is created on first boot via one-context
- [ ] **USR-02**: Agent user is SSH-accessible with OpenNebula-injected public key
- [ ] **USR-03**: Agent user has passwordless sudo access

### Agent Tool Packages

- [ ] **PKG-01**: Claude Code is packaged as a .deb via fpm (installs to /opt/agentlinux/, wrapper on PATH)
- [ ] **PKG-02**: GSD framework is packaged as a .deb via fpm (same pattern)
- [ ] **PKG-03**: Node.js 22 LTS from NodeSource is installed as shared runtime dependency
- [ ] **PKG-04**: A local apt repository is configured in the image containing all .deb packages, and they install cleanly via `apt install`

### MCP Server Demo

- [ ] **MCP-01**: Chrome DevTools MCP server is packaged as a .deb with Chrome as a dependency
- [ ] **MCP-02**: MCP server is pre-configured in the agent user's Claude Code settings (via /etc/skel)
- [ ] **MCP-03**: Agent user can launch Claude Code and use the Chrome DevTools MCP server

### Automated Testing

- [ ] **TST-01**: Script uploads QCOW2 to OpenNebula (ceph-nvme-images, API at api.nebula.k8s.svcs.io)
- [ ] **TST-02**: Script creates VM on ire_developers network, waits for boot, and SSHs into agent user
- [ ] **TST-03**: Script verifies Claude Code, GSD, and Chrome DevTools MCP are installed and callable
- [ ] **TST-04**: Script tears down test VM after verification

## Future Requirements

Deferred to v0.3.0+. Tracked but not in current roadmap.

### Package Groups

- **GRP-01**: One-command install for web development workload
- **GRP-02**: One-command install for GUI testing workload

### Agent Skills

- **SKL-01**: Built-in skills for agents to manage their own OS

### Distribution Formats

- **FMT-01**: ISO installation image
- **FMT-02**: Docker micro-VM image

### Infrastructure

- **INF-01**: Public apt repository / PPA for package distribution
- **INF-02**: Auto-update mechanism for agent packages

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Multi-arch support (ARM) | x86_64 only for PoC |
| Agent-friendly CLI tools | Future milestone — needs design work |
| Docker-in-Docker support | High complexity, not needed for PoC |
| Public package repository | In-image local repo sufficient for PoC |
| Build reproducibility (version pinning) | Nice-to-have, not needed for PoC |
| Makefile build orchestrator | Manual build commands fine for PoC |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| IMG-01 | Phase 3 | Pending |
| IMG-02 | Phase 3 | Pending |
| ONE-01 | Phase 3 | Pending |
| ONE-02 | Phase 3 | Pending |
| USR-01 | Phase 3 | Pending |
| USR-02 | Phase 3 | Pending |
| USR-03 | Phase 3 | Pending |
| PKG-01 | Phase 4 | Pending |
| PKG-02 | Phase 4 | Pending |
| PKG-03 | Phase 4 | Pending |
| PKG-04 | Phase 4 | Pending |
| MCP-01 | Phase 4 | Pending |
| MCP-02 | Phase 4 | Pending |
| MCP-03 | Phase 4 | Pending |
| TST-01 | Phase 5 | Pending |
| TST-02 | Phase 5 | Pending |
| TST-03 | Phase 5 | Pending |
| TST-04 | Phase 5 | Pending |

**Coverage:**
- v0.2.0 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0

---
*Requirements defined: 2026-03-15*
*Last updated: 2026-03-15 after roadmap creation*
