---
gsd_state_version: 1.0
milestone: v0.3.0
milestone_name: AgentLinux Plugin (Ubuntu)
status: defining_requirements
stopped_at: Milestone v0.3.0 started — pivot from custom distro to installable plugin
last_updated: "2026-04-18T00:00:00.000Z"
last_activity: 2026-04-18 — Pivoted from distro to plugin; v0.3.0 milestone initialized
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-18)

**Core value:** An agent can be dropped into any supported Linux system and just work — a dedicated agent user with correctly-owned Node.js, agent binaries, and config paths, so self-updates, global npm installs, and tool provisioning happen without permission fights.
**Current focus:** v0.3.0 milestone defining requirements (pivot from distro to plugin)

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements for v0.3.0 (AgentLinux Plugin for Ubuntu)
Last activity: 2026-04-18 — Pivoted from custom distro to installable plugin; v0.3.0 milestone bootstrapped

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

Full decision log in PROJECT.md Key Decisions table.

**Carried forward from v0.2.0 (still relevant for plugin installer):**
- Node.js 22 LTS from NodeSource as the runtime baseline (install path proven)
- npm install -g for Claude Code / GSD packages (thin wrapper pattern works)
- MCP config merged into ~/.claude.json via jq (works for default-agent setup)
- Chrome install pattern for Chrome DevTools MCP server dependency
- Provisioner script chain pattern (base → runtime → tools → cleanup) translates to installer phases

**Retired with pivot:**
- Debian 12 Bookworm base — superseded by "target user's existing Ubuntu"
- Packer + QEMU image build — replaced by container/QEMU test harness only
- fpm-built `.deb`s as distribution artifacts — superseded by in-installer npm install (fpm may return as the *plugin's* own packaging)
- Local apt repo in image — N/A
- OpenNebula contextualization, ire_developers network, ceph-nvme-images datastore — N/A
- one-context-based agent user creation — replaced by direct useradd in installer

**New for v0.3.0:**
- Ubuntu as initial target distro (apt-based, leverages v0.2.0 install learnings)
- Canonical acceptance test: agent user can `claude` self-update without sudo
- Restart phase numbering at 1 (clean break from distro era)

### Key Infrastructure Details

OpenNebula API and target VM details from v0.2.0 are no longer load-bearing. Test infrastructure for v0.3.0 (Docker / QEMU) will be defined during research and planning.

### Pending Todos

- [ ] Add PR preview deployments for website (tooling)
- [ ] Convert OG image from SVG to PNG for broader social platform support

### Blockers/Concerns

None. Pivot decision is fresh; research about to start.

## Session Continuity

Last session: 2026-04-18
Stopped at: v0.3.0 milestone bootstrap complete; ready for research → requirements → roadmap.
Resume file: None
