# Phase 18: Detection + Branching Foundation - Context

**Gathered:** 2026-06-28
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

AgentLinux's installer recognizes AlmaLinux 9 and routes every package-manager,
locale, NodeSource, sudoers, and brownfield-detection operation through a single
`AGENTLINUX_DISTRO_FAMILY` abstraction (`lib/distro_detect.sh` + new `lib/pkg.sh`),
so a fresh install runs end-to-end on EL9 instead of dying at the Ubuntu-only gate
or on a hardcoded `apt-get`. Requirements: EL-01, EL-02, EL-03, EL-04, EL-05, EL-07.

In scope: distro detection/gate generalization, a `pkg.sh` package-manager
abstraction (apt vs dnf), NodeSource RPM repo path, `/etc/locale.conf` locale path,
EL9 sudoers drop-in via the visudo-gated path, and rpm/file-probe brownfield Node
classification. Out of scope: Docker substrate (Phase 19), bats-green sweep
(Phase 20), catalog verification (Phase 21), QEMU release gate (Phase 22).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — this is a pure
infrastructure/refactor phase (distro abstraction, no user-facing behavior).
Use the ROADMAP phase goal, the five success criteria, REQUIREMENTS.md
(EL-01..EL-07), the existing v0.3.5 research/synthesis, prior ADRs
(ADR-007 QEMU-required, ADR-012 sudoers drop-in), and established installer
conventions to guide decisions. Technical unknowns (NodeSource rpm version
string for DET-02/REUSE-02 classification) are resolved during plan-phase
research per the STATE.md concerns.

</decisions>

<code_context>
## Existing Code Insights

Codebase context (existing `lib/distro_detect.sh`, provisioner steps, the
v0.3.4 brownfield detection/reuse layer) will be gathered during plan-phase
research and pattern-mapping.

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the ROADMAP success criteria — infrastructure
phase. Key constraints carried from STATE.md concerns:
- Confirm the `nodesource` substring in `rpm -q --qf '%{VERSION}-%{RELEASE}' nodejs`
  output on `almalinux:9` early (DET-02 / REUSE-02 classification depends on it).
- AppStream `nodejs` module must be defused, not the older AppStream stream.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase, scope is fixed by the ROADMAP.

</deferred>
