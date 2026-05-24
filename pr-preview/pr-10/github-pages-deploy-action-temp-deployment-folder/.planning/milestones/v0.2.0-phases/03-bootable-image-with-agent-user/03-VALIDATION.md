---
phase: 3
slug: bootable-image-with-agent-user
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-15
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell scripts (bash) + Packer build verification |
| **Config file** | none — Wave 0 installs |
| **Quick run command** | `packer validate packer/agentlinux.pkr.hcl` |
| **Full suite command** | `packer build packer/agentlinux.pkr.hcl && test -f output/agentlinux-0.2.0-amd64.qcow2` |
| **Estimated runtime** | ~120 seconds (full build) / ~2 seconds (validate) |

---

## Sampling Rate

- **After every task commit:** Run `packer validate packer/agentlinux.pkr.hcl`
- **After every plan wave:** Run `packer build packer/agentlinux.pkr.hcl && test -f output/agentlinux-0.2.0-amd64.qcow2`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | IMG-01 | integration | `packer build packer/agentlinux.pkr.hcl && test -f output/agentlinux-0.2.0-amd64.qcow2` | ❌ W0 | ⬜ pending |
| 03-01-02 | 01 | 1 | IMG-02 | smoke | `timeout 60 qemu-system-x86_64 -enable-kvm -m 1024 -drive file=output/*.qcow2,format=qcow2 -nographic -serial mon:stdio` | ❌ W0 | ⬜ pending |
| 03-01-03 | 01 | 1 | ONE-01 | unit | `virt-customize -a output/*.qcow2 --run-command 'dpkg -l one-context && ! dpkg -l cloud-init'` | ❌ W0 | ⬜ pending |
| 03-02-01 | 02 | 2 | ONE-02 | manual | Deploy to OpenNebula, verify IP + SSH | N/A | ⬜ pending |
| 03-02-02 | 02 | 2 | USR-01 | manual | Deploy with USERNAME=agent, verify `id agent` | N/A | ⬜ pending |
| 03-02-03 | 02 | 2 | USR-02 | manual | SSH agent@VM_IP with injected key | N/A | ⬜ pending |
| 03-02-04 | 02 | 2 | USR-03 | manual | SSH in, run `sudo whoami` without password prompt | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Packer installation on build machine (`sudo yum install -y packer`)
- [ ] QEMU installation on build machine (`sudo yum install -y qemu-kvm qemu-img`)
- [ ] `packer/agentlinux.pkr.hcl` — main template (created by plan)
- [ ] `packer/scripts/*.sh` — provisioner scripts (created by plan)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| VM contextualizes on OpenNebula | ONE-02 | Requires live OpenNebula deployment | Deploy image to OpenNebula with ire_developers network, verify IP assigned and SSH keys injected |
| agent user created on first boot | USR-01 | Requires one-context execution on OpenNebula | Deploy with USERNAME=agent in context, SSH in, run `id agent` |
| agent user SSH-accessible | USR-02 | Requires OpenNebula SSH key injection | Deploy with SSH_PUBLIC_KEY, attempt `ssh agent@VM_IP` |
| agent user has passwordless sudo | USR-03 | Requires agent user from one-context | SSH in as agent, run `sudo whoami` — should return root without password prompt |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
