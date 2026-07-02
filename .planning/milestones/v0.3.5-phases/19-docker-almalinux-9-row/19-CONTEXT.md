# Phase 19: Docker AlmaLinux 9 Row - Context

**Gathered:** 2026-06-28
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

A fast-feedback `almalinux:9` Docker substrate that runs the bats suite, so the
Phase 18 branch can be validated on a real EL9 environment in the ~90s Docker
loop (not the ~5min QEMU loop). Phase 19 is Phase 18's acceptance gate.
Requirement: HARN-01.

In scope: a new `tests/docker/Dockerfile.almalinux-9` (`FROM almalinux:9`, EL9
package set incl. `bats` via EPEL or vendored, systemd-in-Docker recipe,
hermetic CLI build stage preserved exactly as the Ubuntu rows); adding
`almalinux-9` to `tests/docker/run.sh`; adding an `almalinux-9` matrix arm to
`.github/workflows/test.yml` and `release.yml` gate-2 (generalize the matrix
dimension `ubuntu`→`target`, `fail-fast: false`). Out of scope: making the full
behavior contract green on EL9 (that is Phase 20 / PAR-01) — Phase 19 only has
to stand up the substrate and reach a green install + a runnable bats invocation;
catalog verify (Phase 21); QEMU row + release-gate wiring (Phase 22 / HARN-02 /
REL-01).

This phase is also where the carried STATE.md concern is resolved: confirm the
`nodesource` substring in `rpm -q --qf '%{VERSION}-%{RELEASE}' nodejs` on a live
`almalinux:9` (DET-02 / REUSE-02 classifier from Phase 18, Open Q1).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure
phase (Docker substrate + CI matrix wiring; no user-facing behavior). Mirror the
existing Ubuntu Docker rows (`tests/docker/Dockerfile.ubuntu-24.04`, `run.sh`,
the systemd-in-Docker `--privileged --cgroupns=host` recipe per ADR-007 /
02-RESEARCH) and the existing CI matrix structure. Use the ROADMAP success
criteria, HARN-01, ADR-007 (Docker fast-path + QEMU release-gate), and the
Phase 18 `AGENTLINUX_DISTRO_FAMILY` abstraction to guide decisions. Technical
unknowns (bats availability on EL9 — EPEL vs vendored; systemd-in-Docker quirks
on almalinux:9; the exact NodeSource rpm release string) are resolved during
plan-phase research and on-box smoke.

</decisions>

<code_context>
## Existing Code Insights

The Ubuntu Docker harness already exists and is the analog to mirror:
- `tests/docker/run.sh` — single CI entrypoint; builds the matching
  systemd-capable image, boots it, runs `agentlinux-install` inside, runs bats
  inside, propagates the bats exit code. Currently switches on
  `ubuntu-22.04|24.04|26.04`.
- `tests/docker/Dockerfile.ubuntu-{22,24,26}.04` — per-version images with a
  hermetic CLI build stage + systemd-in-Docker recipe.
- `.github/workflows/test.yml` + `release.yml` — matrix currently
  `[ubuntu-22.04, ubuntu-24.04, ubuntu-26.04]`.
Full reuse/pattern mapping happens during plan-phase.

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the ROADMAP success criteria. Key constraints:
- `bats` is NOT in AlmaLinux base repos — source via EPEL or vendor it.
- Do NOT `dnf install curl` (EL9 `curl-minimal` conflict, per Phase 18 research).
- Keep the hermetic CLI build stage byte-equivalent to the Ubuntu rows.
- `fail-fast: false` so a red Alma arm still reports the Ubuntu arms.
- Phase 19 validates the Phase 18 branch — expect to surface (and feed back)
  any EL9 install bug the unit-level Phase 18 work could not catch on the dev host.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase, scope fixed by the ROADMAP (HARN-01). Full
behavior-contract green is Phase 20; QEMU + release gate is Phase 22.

</deferred>
