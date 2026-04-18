---
gsd_state_version: 1.0
milestone: v0.3.0
milestone_name: AgentLinux Plugin (Ubuntu)
status: ready_to_plan
stopped_at: Roadmap created for v0.3.0 (6 phases, 46/46 requirements mapped) — ready to plan Phase 1 Harness Setup
last_updated: "2026-04-18T00:00:00.000Z"
last_activity: 2026-04-18 — Roadmap created; Phase 1 (Harness Setup) ready for planning
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-18)

**Core value:** An agent can be dropped into any supported Linux system and just work — a dedicated agent user with correctly-owned Node.js, agent binaries, and config paths, so self-updates, global npm installs, and tool provisioning happen without permission fights.
**Current focus:** Phase 1 — Harness Setup (project skeleton, pre-commit, CLAUDE.md, ADRs, review subagents, skills, GH Actions scaffolding)

## Current Position

Phase: 1 of 6 (Harness Setup)
Plan: — (not yet planned)
Status: Ready to plan
Last activity: 2026-04-18 — Roadmap created; 46/46 v0.3.0 requirements mapped across 6 phases. Next: `/gsd-plan-phase 1`.

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 10 (5 v0.1.0, 5 v0.2.0)
- Average duration: ~3 min per plan

**By Phase (historical):**

| Phase | Milestone | Plans | Total | Avg/Plan |
|-------|-----------|-------|-------|----------|
| 1. Complete Website | v0.1.0 | 3 | ~6min | ~2min |
| 2. Deploy to Public | v0.1.0 | 2 | ~3min | ~1.5min |
| 3. Bootable Image | v0.2.0 | 3 | ~14min | ~4.7min |
| 4. Agent Tool Packages | v0.2.0 | 2 | ~5min | ~2.5min |

*v0.3.0 phases will populate as plans complete.*

## Accumulated Context

### Decisions

Full decision log in PROJECT.md Key Decisions table. Seed ADR set (ADR-001..ADR-010) to be created in Phase 1 per `docs/HARNESS.md` §2.3:
- ADR-001: Pivot from custom distro to installable Ubuntu plugin (v0.2.0 → v0.3.0)
- ADR-002: Behavior-contract framing — requirements are BHV-XX, not INST-XX; tests are the spec
- ADR-003: No default agents installed in v0.3.0
- ADR-004: Per-user npm prefix as the keystone ownership decision
- ADR-005: System Node.js (NodeSource) over version managers (nvm/fnm/volta)
- ADR-006: curl-pipe-bash primary + optional .deb distribution
- ADR-007: Docker (fast) + QEMU (release gate) test harness; Docker-only is disqualified
- ADR-008: Commander.js for the registry CLI
- ADR-009: Snap is structurally disqualified as a distribution mechanism
- ADR-010: Review loop triggered by CLAUDE.md instruction, not a Stop hook

**Carried forward from v0.2.0 (still relevant for plugin installer):**
- Node.js 22 LTS from NodeSource as the runtime baseline (install path proven)
- npm install -g for Claude Code / GSD packages (but now as the agent user, not root)
- MCP config merged into ~/.claude.json via jq (works for default-agent setup)
- Chrome install pattern for browser-access tool (now under Playwright in the v0.3.0 catalog)
- Provisioner script chain pattern (ordered numbered scripts) translates to installer phases

**Retired with pivot:**
- Debian 12 Bookworm base — superseded by "target user's existing Ubuntu"
- Packer + QEMU image build — replaced by Docker (fast) + QEMU (release gate) test harnesses
- fpm-built `.deb`s as distribution artifacts — superseded by in-installer npm install (fpm may return as the plugin's own optional .deb packaging)
- Local apt repo in image — N/A
- OpenNebula contextualization — N/A
- one-context-based agent user creation — replaced by direct useradd in installer
- chrome-devtools-mcp as the canonical browser tool — replaced by Playwright per locked decision

**New for v0.3.0:**
- Ubuntu as initial target distro (22.04 + 24.04)
- Canonical acceptance test: agent user can self-update Claude Code without sudo/EACCES (AGT-02)
- Behavior-contract framing: bats test suite is the spec
- No default agents — catalog ships claude-code, gsd, playwright as *available*; users opt in
- Phase 1 is Harness Setup (non-negotiable); restart phase numbering at 1
- Mutation testing is advisory in v0.3.0; promotion to release gate is a v0.4 decision

### Key Infrastructure Details

OpenNebula API and target VM details from v0.2.0 are no longer load-bearing. Test infrastructure for v0.3.0:
- Docker matrix (ubuntu:22.04, ubuntu:24.04) — fast, every PR (lands in Phase 2)
- QEMU with fresh Ubuntu cloud images — nightly + release gate (lands in Phase 6)

### Pending Todos

- [ ] Add PR preview deployments for website (tooling)
- [ ] Convert OG image from SVG to PNG for broader social platform support

### Blockers/Concerns

None. Roadmap created; all 46 requirements mapped; Phase 1 is ready to plan.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-04-18
Stopped at: Roadmap created for v0.3.0 (6 phases, 46/46 requirements mapped, 0 orphans). STATE updated to reflect Phase 1 Harness Setup ready to plan. REQUIREMENTS.md Traceability table populated.
Resume file: None — next action is `/gsd-plan-phase 1`.
