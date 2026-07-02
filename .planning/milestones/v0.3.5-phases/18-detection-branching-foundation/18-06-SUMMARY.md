---
phase: 18-detection-branching-foundation
plan: 06
subsystem: docs
tags: [adr, decision-record, distro-family, almalinux, el9, pkg-dispatch, documentation]

# Dependency graph
requires:
  - phase: 18-detection-branching-foundation
    plan: 01
    provides: "distro_detect.sh exports AGENTLINUX_DISTRO_FAMILY ∈ {debian, rhel} — the decision this ADR records"
  - phase: 18-detection-branching-foundation
    plan: 02
    provides: "plugin/lib/pkg.sh verb-dispatch layer — the single apt↔dnf branch this ADR documents"
  - phase: 18-detection-branching-foundation
    plan: "03/04/05"
    provides: "the 13 call sites routed through pkg.sh verbs — the realized state the ADR describes"
provides:
  - "docs/decisions/017-distro-family-bucket.md — the decision record for the AGENTLINUX_DISTRO_FAMILY two-bucket abstraction + single pkg.sh dispatch"
  - "documented rejected alternatives (inline per-site case; AppStream dnf module install; localectl; ID_LIKE; microdnf) with rationale for a future EL-family expansion"
  - "documented AlmaLinux-9-ONLY scope boundary + deferred Alma 10 / RHEL / Rocky"
affects: [phase-19-docker, phase-20-behavior-green, future-el-family-expansion]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ADR mirrors the repo's ADR-005/012 structure: # NNN: Title / **Status:** Accepted / **Date:** / ## Context / ## Decision / ## Consequences / ## References"
    - "Decision record documents shipped reality (plans 18-01..18-05), not aspiration"

key-files:
  created:
    - docs/decisions/017-distro-family-bucket.md
    - .planning/phases/18-detection-branching-foundation/18-06-SUMMARY.md
  modified: []

key-decisions:
  - "ADR-017 documents the AGENTLINUX_DISTRO_FAMILY ∈ {debian, rhel} single fork point (ID-exact) + the lib/pkg.sh single-dispatch layer as shipped, not a new proposal"
  - "Rejected alternatives captured verbatim from 18-RESEARCH Alternatives Considered + Anti-Patterns so a future EL-family expansion inherits the reasoning"
  - "Cross-referenced ADR-002 (behavior-contract framing — the rule that lets the package manager branch while observables hold), ADR-005/006 (NodeSource), ADR-012 (sudoers drop-in) in addition to the plan-mandated ADR-005/012"

patterns-established:
  - "Phase-decision ADR pattern: the planned decision artifact for a port phase records the family bucket + dispatch-layer design after the implementation plans ship it"

requirements-completed: [EL-01, EL-02]

# Metrics
duration: ~6min
completed: 2026-06-28
---

# Phase 18 Plan 06: ADR-017 Distro-Family Bucket Decision Record Summary

**docs/decisions/017-distro-family-bucket.md records the v0.3.5 AlmaLinux 9 port's load-bearing design decision: a single `AGENTLINUX_DISTRO_FAMILY ∈ {debian, rhel}` bucket exported (ID-exact) from `distro_detect.sh` plus one `lib/pkg.sh` verb-dispatch layer that consolidates all ~13 apt↔dnf/locale/NodeSource call sites into one auditable branch — with the rejected alternatives (inline per-site `case`; AppStream `dnf module install nodejs:22`; `localectl set-locale`; `ID_LIKE` matching; `microdnf`), the AlmaLinux-9-ONLY scope boundary, and the deferred Alma 10 / RHEL / Rocky scope all documented, following the repo's ADR-005/012 Status/Context/Decision/Consequences structure.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-06-28T07:20:12Z
- **Tasks:** 1 (`type=auto`)
- **Files modified:** 1 (created; + this summary)

## Accomplishments
- Authored ADR-017 mirroring the established ADR-005/012 heading structure (`# 017: ...`, `**Status:** Accepted`, `**Date:** 2026-06-28`, `## Context` / `## Decision` / `## Consequences` / `## References`).
- **Context** frames the port as a behavior-contract-preserving (ADR-002) call-site substitution across ~13 hardcoded sites in five files, with the AlmaLinux-9-ONLY scope rule.
- **Decision** documents, as shipped: the `AGENTLINUX_DISTRO_FAMILY` ID-exact two-bucket export + escape-hatch family seed (plan 18-01); the nine-verb `lib/pkg.sh` dispatch layer with byte-for-byte debian arms (plan 18-02); the 13 call sites converted to verb calls + the `nodesource_repo_paths` single-source-of-truth lockstep (plans 18-03/04/05); the `can_sudo_apt` JSON-field-name preservation while the probe binary branches (plan 18-05); and the curl-installer lockstep pre-gate (plan 18-01).
- **Consequences** record the one-auditable-branch-point win, the provably-unchanged Ubuntu behavior, the small contained future EL-family expansion (with the explicit no-family-wide-claim caveat), and the deferred Alma 10 / RHEL / Rocky scope.
- **Rejected alternatives** documented with rationale, sourced from 18-RESEARCH "Alternatives Considered" + "Anti-Patterns": inline per-site `if`/`case` (13× drift); AppStream `dnf module install nodejs:22` (stream-availability drift, diverges from NodeSource-everywhere RT-01); `localectl set-locale` (needs systemd-localed/D-Bus, absent in Docker); `ID_LIKE` matching (silently admits Rocky/RHEL/CentOS/Fedora); `microdnf` (no `module` subcommand).
- Cross-referenced ADR-002, ADR-005, ADR-006, ADR-012, plus `distro_detect.sh`/`pkg.sh`, EL-01/EL-02, and the plan-18 SUMMARYs.

## Task Commits

1. **Task 1: Write ADR-017 distro-family-bucket** — `4a496f0` (docs)

## Files Created/Modified
- `docs/decisions/017-distro-family-bucket.md` (created, 141 lines) — the ADR. Status/Context/Decision/Consequences/References structure; documents the family bucket, the pkg.sh dispatch layer, the four rejected alternatives + microdnf, the AlmaLinux-9-ONLY scope, and the deferred scope.
- `.planning/phases/18-detection-branching-foundation/18-06-SUMMARY.md` (created) — this summary.

## Decisions Made
- **Document reality, not aspiration.** ADR-017 records the design that plans 18-01..18-05 already shipped (verified against each plan's SUMMARY), so the ADR and the code agree.
- **Broadened the cross-references** beyond the plan-mandated ADR-005/012 to also cite ADR-002 (behavior-contract framing — the rule that authorizes branching the package manager while observables hold) and ADR-006 (curl-pipe-bash + deb mechanism), because both are load-bearing for the NodeSource-RPM-mirrors-the-deb-path reasoning. This is an additive enrichment, not a scope change.
- **Included `microdnf` as a fifth rejected alternative** (from 18-RESEARCH Standard Stack: only full `dnf` has the `module` subcommand the AppStream defuse needs) — beyond the plan's named four — because it is part of the same "why dnf, why this way" rationale a future maintainer needs.

## Deviations from Plan
None — the single `type=auto` task executed exactly as written, committed atomically. Two additive enrichments (not scope changes): two extra ADR cross-references (ADR-002, ADR-006) and one extra rejected-alternative entry (`microdnf`), all drawn directly from 18-RESEARCH and consistent with what shipped. The ADR is exempt from `ai-deslop` per CLAUDE.md (technical-writer + fact-checker apply); it was kept factual and consistent with the plan-18 SUMMARYs.

## Issues Encountered
None.

## User Setup Required
None — documentation-only plan; no external service configuration.

## Next Phase Readiness
- ADR-017 is the planned decision artifact STATE.md + 18-RESEARCH flagged for this phase; the family-bucket design rationale is now durably recorded for Phase 19 (Docker substrate) and Phase 20 (behavior-green) maintainers and for any future EL-family expansion.
- No code surface introduced (T-18-20 disposition: accept — internal design record, docs/decisions/ is exempt from external-audience-auditor per CLAUDE.md).

## Self-Check: PASSED

- Files: `docs/decisions/017-distro-family-bucket.md`, `18-06-SUMMARY.md` — both present.
- Commit `4a496f0` — in git history.
- Acceptance: file exists; `AGENTLINUX_DISTRO_FAMILY`, `## Context`/`## Decision`/`## Consequences`, `**Status:** Accepted`, `localectl|module install|ID_LIKE`, and `pkg.sh` all grep-present; 141 lines (> 30 min).

---
*Phase: 18-detection-branching-foundation*
*Completed: 2026-06-28*
