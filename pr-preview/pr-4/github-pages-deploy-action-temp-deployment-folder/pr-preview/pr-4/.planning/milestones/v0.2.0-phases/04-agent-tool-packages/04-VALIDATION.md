---
phase: 4
slug: agent-tool-packages
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash assertions in Packer provisioner scripts |
| **Config file** | None — validation via build-time checks |
| **Quick run command** | `packer validate packer/agentlinux.pkr.hcl` |
| **Full suite command** | `cd packer && packer build agentlinux.pkr.hcl` |
| **Estimated runtime** | ~120 seconds (full image build) |

---

## Sampling Rate

- **After every task commit:** Run `packer validate packer/agentlinux.pkr.hcl`
- **After every plan wave:** Run `cd packer && packer build agentlinux.pkr.hcl`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | PKG-03 | smoke | `packer validate packer/agentlinux.pkr.hcl` | ✅ existing | ⬜ pending |
| 04-01-02 | 01 | 1 | PKG-01 | smoke | `grep -q 'agentlinux-claude-code' packer/scripts/04-packages.sh` | ❌ W0 | ⬜ pending |
| 04-01-03 | 01 | 1 | PKG-02 | smoke | `grep -q 'agentlinux-gsd' packer/scripts/04-packages.sh` | ❌ W0 | ⬜ pending |
| 04-01-04 | 01 | 1 | MCP-01 | smoke | `grep -q 'agentlinux-chrome-devtools-mcp' packer/scripts/04-packages.sh` | ❌ W0 | ⬜ pending |
| 04-01-05 | 01 | 1 | PKG-04 | smoke | `grep -q 'dpkg-scanpackages' packer/scripts/04-packages.sh` | ❌ W0 | ⬜ pending |
| 04-02-01 | 02 | 1 | MCP-02 | smoke | `grep -q 'mcpServers' packer/files/skel/.claude.json 2>/dev/null || grep -q 'mcpServers' packer/scripts/05-chrome.sh` | ❌ W0 | ⬜ pending |
| 04-02-02 | 02 | 1 | MCP-03 | e2e | Full `packer build` succeeds with all packages | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `packer/scripts/03-nodejs.sh` — NodeSource Node.js 22 + fpm installation
- [ ] `packer/scripts/04-packages.sh` — Build all .debs with fpm, create local repo, apt install
- [ ] `packer/scripts/05-chrome.sh` — Google Chrome + Xvfb + MCP config
- [ ] Rename existing `packer/scripts/03-cleanup.sh` to `packer/scripts/06-cleanup.sh`

*These provisioner scripts ARE the implementation — no separate test framework needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Claude Code launches and responds | MCP-03 | Requires API key + interactive session | SSH into built VM, export ANTHROPIC_API_KEY, run `claude --version` |
| MCP server connects and lists tools | MCP-03 | Requires Chrome runtime + Claude session | SSH into VM, start `claude`, verify MCP tools available |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
