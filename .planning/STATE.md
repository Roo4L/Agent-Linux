---
gsd_state_version: 1.0
milestone: v0.3.5
milestone_name: AlmaLinux 9 Support
status: ready
stopped_at: "v0.3.5 'AlmaLinux 9 Support' roadmap CREATED 2026-06-28 — 5 phases (18-22) mapped 1:1 across 14 requirements (EL-01..08, HARN-01/02, PAR-01/02, REC-01, REL-01); 100% coverage, 0 orphans. Phase numbering continues from v0.3.4 (last phase 17) → starts at Phase 18. Anchor AL-47 under Epic AL-48 (maintainer-VM daily-driver); blocker AL-38 Done. Scope: AlmaLinux 9 ONLY (no Alma 10 / RHEL / Rocky / Fedora). This is a PORT, not a feature milestone — behavior contract (BHV/RT/AGT/CLI/CAT/INST + DET/REUSE/REMEDIATE/UX) is the invariant; implementation branches apt→dnf, dpkg→rpm. SELinux stays enforcing (restorecon, never setenforce 0). AL-59 alt-user wiring deferred (separate AL-48 item). NEXT: /gsd-plan-phase 18."
last_updated: "2026-06-28T00:00:00.000Z"
last_activity: 2026-06-28 -- v0.3.5 roadmap created (5 phases 18-22; 14 requirements mapped; status planning→ready)
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-27)

**Core value:** An agent can be dropped into any supported Linux system and just work — a dedicated agent user with correctly-owned Node.js, agent binaries, and config paths, so self-updates, global npm installs, and tool provisioning happen without permission fights. v0.3.5 extends "any supported Linux system" past Ubuntu to AlmaLinux 9.
**Current focus:** v0.3.5 AlmaLinux 9 Support — roadmap-ready; first phase is detection + the distro-family branching foundation (Phase 18).

## Current Position

Milestone: v0.3.5 AlmaLinux 9 Support (Phases 18–22). Anchor AL-47 (Epic AL-48); blocker AL-38 Done. Scope: AlmaLinux 9 ONLY. Goal: port the plugin to AlmaLinux 9 with the same six-mode invocation contract + zero-EACCES self-update gate Ubuntu has (apt→dnf, dpkg→rpm; behavior contract unchanged). Milestone-close gate: AGT-02 (PAR-02) green on a real enforcing-SELinux EL9 QEMU guest.

Phase: 18 of 22 (Detection + Branching Foundation) — Not started
Plan: — of — (Phase 18 not yet planned)
Status: Ready to plan (roadmap ready)
Last activity: 2026-06-28 — v0.3.5 roadmap created; 14 requirements mapped to 5 phases (100% coverage)

Progress: [░░░░░░░░░░] 0% (0 of TBD plans)

### Phase list (v0.3.5)

| Phase | Name | Requirements | Depends on | Status |
|-------|------|--------------|------------|--------|
| 18 | Detection + Branching Foundation | EL-01, EL-02, EL-03, EL-04, EL-05, EL-07 | v0.3.4 baseline (Phase 17); co-dev 19 | Not started |
| 19 | Docker AlmaLinux 9 Row | HARN-01 | Phase 18 | Not started |
| 20 | Behavior-Test-Green on AlmaLinux 9 | EL-06, EL-08, PAR-01 | Phase 19 | Not started |
| 21 | Catalog Verify on AlmaLinux 9 | REC-01 | Phase 20 (may overlap) | Not started |
| 22 | QEMU Release-Gate + Pipeline | HARN-02, PAR-02, REL-01 | Phases 20 + 21 (exit gate) | Not started |

## Performance Metrics

**Velocity:**
- Total plans completed (this milestone): 0
- Historical: v0.3.0 (30 plans), v0.3.4 (12 plans) — see MILESTONES.md

**By Phase (v0.3.5):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 18-22 | 0 | - | - |

*Updated after each plan completion.*

## Accumulated Context

### Decisions

Full decision log in PROJECT.md Key Decisions table. Recent decisions affecting v0.3.5:

- AlmaLinux 9 support milestone (2026-06-27): extend the plugin past Ubuntu without changing the behavior contract — implementation branches, contract does not.
- AlmaLinux 9 ONLY (no Alma 10 / RHEL / Rocky / Fedora): first-person-friction scope rule; keeps the test matrix small.
- AL-59 alt-user wiring kept OUT of v0.3.5: distro-independent; planned separately under Epic AL-48.
- ADR-007 (carried): Docker proves fast, QEMU proves real — AlmaLinux 9 must be green in both before the v0.3.5 tag.
- ADR-017 (planned, Phase 18): record the distro-family bucket + dnf-branch decision.
- SELinux stays enforcing — `restorecon -R -F ~agent/.ssh`, never `setenforce 0` (CLAUDE.md "don't paper over the environment").

### Pending Todos

None new for v0.3.5. See `.planning/todos/pending/` (carried-forward website PR-preview idea — out of installer scope).

### Blockers/Concerns

- **Phase 21 (Playwright EL9 chromium) — OPEN:** whether any EL9 code path launches Chromium is unresolved; do NOT pre-scope a dnf-deps task until the live AGT-05 smoke on `almalinux:9` is in hand.
- **Phase 18/19 (NodeSource rpm version string):** confirm the `nodesource` substring in `rpm -q --qf '%{VERSION}-%{RELEASE}' nodejs` output on `almalinux:9` early — DET-02 / REUSE-02 classification depend on it.
- **Phase 22 (QEMU checksum guard):** the `≥1 file validated` assertion + a flipped-byte corruption test must land before the QEMU row is wired to the release gate.

## Deferred Items

Items acknowledged and carried forward:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Scope | AL-59 alt-user hollow-install wiring (distro-independent; touches 20/30/40 provisioners) | Deferred to separate AL-48 item | v0.3.5 scope |
| Scope | AlmaLinux 10 / RHEL / Rocky / Fedora (EL-family expansion) | Deferred until Alma 9 is daily driver one cycle | v0.3.5 scope |
| Verification | v0.3.0 Phase 05 human_needed re-runs (re-confirmed by v0.3.4 release gate) | Resolved at v0.3.4 close | v0.3.4 close |

## Session Continuity

Last session: 2026-06-28
Stopped at: v0.3.5 roadmap written (ROADMAP.md + REQUIREMENTS.md traceability + this STATE.md); 5 phases 18-22, 14 requirements mapped, 100% coverage.
Resume file: None — run `/gsd-plan-phase 18` to begin.
