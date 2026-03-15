# Roadmap: AgentLinux

## Milestones

- ✅ **v0.1.0 AgentLinux Landing Page** — Phases 1-2 (shipped 2026-03-10)
- 🚧 **v0.2.0 First Distro Image** — Phases 3-5 (in progress)

## Phases

<details>
<summary>✅ v0.1.0 AgentLinux Landing Page (Phases 1-2) — SHIPPED 2026-03-10</summary>

- [x] Phase 1: Complete Website (3/3 plans) — completed 2026-03-09
- [x] Phase 2: Deploy to Public (2/2 plans) — completed 2026-03-10

</details>

### v0.2.0 First Distro Image

- [ ] **Phase 3: Bootable Image with Agent User** - Packer builds a Debian 12 QCOW2 that boots on KVM, contextualizes on OpenNebula, and provides SSH access to an agent user
- [ ] **Phase 4: Agent Tool Packages** - Claude Code, GSD, and Chrome DevTools MCP server are packaged as .debs and available via apt install from a local repository in the image
- [ ] **Phase 5: End-to-End Validation** - Automated script deploys image to OpenNebula, verifies all agent tools work, and tears down the test VM

## Phase Details

### Phase 3: Bootable Image with Agent User
**Goal**: A Debian 12 QCOW2 image that boots on KVM, contextualizes on OpenNebula (SSH keys, networking), and provides SSH access to a non-root agent user with sudo
**Depends on**: Nothing (first phase of v0.2.0)
**Requirements**: IMG-01, IMG-02, ONE-01, ONE-02, USR-01, USR-02, USR-03
**Success Criteria** (what must be TRUE):
  1. `packer build` produces a QCOW2 file from the Debian 12 cloud base image without manual intervention
  2. The QCOW2 boots on KVM/QEMU and reaches a login prompt
  3. When deployed on OpenNebula, the VM contextualizes (gets IP from ire_developers network, injects SSH keys) using one-context (not cloud-init)
  4. A non-root `agent` user exists after first boot, is SSH-accessible with the injected key, and has passwordless sudo
**Plans**: 2 plans

Plans:
- [ ] 03-01-PLAN.md — Create Packer build infrastructure (template + provisioning scripts)
- [ ] 03-02-PLAN.md — Build QCOW2 image and verify boot + contextualization readiness

### Phase 4: Agent Tool Packages
**Goal**: Claude Code, GSD framework, and Chrome DevTools MCP server are each packaged as .debs with fpm, stored in a local apt repository within the image, and install cleanly via `apt install`
**Depends on**: Phase 3
**Requirements**: PKG-01, PKG-02, PKG-03, PKG-04, MCP-01, MCP-02, MCP-03
**Success Criteria** (what must be TRUE):
  1. Node.js 22 LTS is installed from NodeSource and available as shared runtime
  2. `apt install agentlinux-claude-code agentlinux-gsd` succeeds from the local repo, and `claude` / `gsd` commands work on PATH
  3. `apt install agentlinux-chrome-devtools-mcp` succeeds, pulling in Chrome as a dependency, and the MCP server binary is on PATH
  4. The agent user's Claude Code config (via /etc/skel) has the Chrome DevTools MCP server pre-configured so it works on first launch
  5. All packages are built by fpm from staged directory trees (not manual dpkg assembly)
**Plans**: TBD

Plans:
- [ ] 04-01: TBD
- [ ] 04-02: TBD

### Phase 5: End-to-End Validation
**Goal**: An automated script proves the full image works on real OpenNebula infrastructure -- deploy, verify all agent tools, tear down
**Depends on**: Phase 4
**Requirements**: TST-01, TST-02, TST-03, TST-04
**Success Criteria** (what must be TRUE):
  1. Script uploads the QCOW2 to OpenNebula datastore ceph-nvme-images (ID 100) via API at api.nebula.k8s.svcs.io
  2. Script creates a VM on ire_developers network (ID 500), waits for boot, and SSHs into the agent user
  3. Script verifies Claude Code, GSD, and Chrome DevTools MCP server are installed and callable
  4. Script tears down the test VM and reports pass/fail
**Plans**: TBD

Plans:
- [ ] 05-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 3 -> 4 -> 5

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Complete Website | v0.1.0 | 3/3 | Complete | 2026-03-09 |
| 2. Deploy to Public | v0.1.0 | 2/2 | Complete | 2026-03-10 |
| 3. Bootable Image with Agent User | v0.2.0 | 0/2 | Planned | - |
| 4. Agent Tool Packages | v0.2.0 | 0/? | Not started | - |
| 5. End-to-End Validation | v0.2.0 | 0/? | Not started | - |
