---
phase: 18-detection-branching-foundation
plan: 05
subsystem: infra
tags: [detection, brownfield, almalinux, el9, bash, rpm, nodesource, appstream, dnf, can_sudo_apt, contract-preservation]

# Dependency graph
requires:
  - phase: 18-detection-branching-foundation
    plan: 02
    provides: "plugin/lib/pkg.sh::nodesource_repo_paths — the single source of truth for the family's NodeSource repo-file paths (the rhel detect gate routes its repo-presence probe through it)"
  - phase: 17 (v0.3.4 baseline)
    provides: "the DET-02 nodejs multi-source probe + DET-01 user probe (the debian arms this plan keeps byte-for-byte) and the can_sudo_apt JSON contract asserted by render.sh + the bats suite"
provides:
  - "plugin/lib/detect/nodejs.sh — rhel arm classifying a pre-existing EL9 Node by its REAL source: NodeSource-RPM (rpm RELEASE has the `nodesource` substring AND a nodesource_repo_paths file present) vs AppStream-module (distinct distro_rpm class) vs absent"
  - "plugin/lib/detect/user.sh — sudo-capability probe binary branched to /usr/bin/dnf --version on rhel while the can_sudo_apt variable/export/JSON-field/accessor names stay unchanged (DET-01 contract surface)"
  - "tests/bats/18-detect-el9.bats — EL-07 dev-host PATH-stub fixtures (stubbed rpm/dnf/sudo, repo presence via an in-test nodesource_repo_paths override, real jq) covering all three classification cases + the read-only invariant + field-name preservation"
affects: [phase-19-docker, phase-20-behavior-green]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Brownfield classification branches on AGENTLINUX_DISTRO_FAMILY: the debian dual-gate (dpkg-query + apt sources) is kept byte-for-byte; the rhel arm uses rpm -q + the lockstep nodesource_repo_paths verb"
    - "Read-only detection invariant on the rhel arm: rpm -q + file tests only, never a write-path dnf subcommand (would touch /var/cache/dnf and break 15-detection byte-equality — Pitfall 5)"
    - "Contract-preservation trap encoded: generalize the probe BINARY, freeze the can_sudo_apt field name (Pitfall 7)"
    - "AppStream module is a DISTINCT source class (distro_rpm, parallels distro_apt) so a non-NodeSource Node is never miscounted as NodeSource"

key-files:
  created:
    - tests/bats/18-detect-el9.bats
    - .planning/phases/18-detection-branching-foundation/18-05-SUMMARY.md
  modified:
    - plugin/lib/detect/nodejs.sh
    - plugin/lib/detect/user.sh

key-decisions:
  - "AppStream-module Node classified as `distro_rpm` (parallels the debian `distro_apt` class) rather than the plan's example `distro_dnf`: the `distro_dnf ` token contains the `dnf ` substring the read-only acceptance grep (`grep -c 'dnf ' = 0`) forbids, so the rpm-mirroring name is both contract-clean and more descriptive"
  - "Repo-file presence in the rhel NodeSource gate is probed through `nodesource_repo_paths` (a `while IFS= read -r … done < <(nodesource_repo_paths)` loop), NOT a hardcoded /etc/yum.repos.d path — keeping the detect gate, the 30-nodejs idempotency gate, and the agentlinux-install purge cleanup in lockstep"
  - "The classifier keys on the `nodesource` substring (not the deb-specific `-1nodesource`) for robustness across the nodistro repo layout; the EXACT %{RELEASE} string remains live-verified on almalinux:9 in Phase 19 (Open Q1)"
  - "EL-07 fixtures run on the Ubuntu dev host via a PATH-stub harness (stub rpm/dnf/sudo, override nodesource_repo_paths to a temp path, real jq) — no Docker, no root; mirrors the 18-pkg-dispatch.bats approach"

patterns-established:
  - "Pattern: brownfield-detection-by-family — the distro-package arm of every detect fragment branches on AGENTLINUX_DISTRO_FAMILY; debian arm preserved byte-for-byte, rhel arm classifies via rpm + the lockstep repo-paths verb, both read-only"

requirements-completed: [EL-07]

# Metrics
duration: ~9min
completed: 2026-06-28
---

# Phase 18 Plan 05: Brownfield EL9 Detection Arm (EL-07) Summary

**The brownfield detection layer now has an EL9 arm at parity with the Ubuntu detection arm: `plugin/lib/detect/nodejs.sh` family-branches its distro-package classifier so a pre-existing AlmaLinux 9 Node is classified by its REAL source — NodeSource-RPM (rpm RELEASE carries the `nodesource` substring AND a `nodesource_repo_paths` file is present) vs AppStream-module (a distinct `distro_rpm` class) vs absent — using read-only `rpm -q` + file probes routed through the lockstep `nodesource_repo_paths` verb (never a hardcoded yum.repos.d path, never a write-path `dnf`), and `plugin/lib/detect/user.sh` branches its sudo-capability probe binary to `/usr/bin/dnf --version` on rhel while the `can_sudo_apt` variable, `DETECT_USER_CAN_SUDO_APT` export, JSON field, and `detect::user_can_sudo_apt()` accessor stay byte-identical — the DET-01 contract render.sh + the bats suite assert. The debian arms of both fragments are unchanged. EL-07 is unit-proven by `tests/bats/18-detect-el9.bats` on the dev host; the exact rpm `%{RELEASE}` string is carried to live confirmation on the Phase 19 `almalinux:9` Docker arm (Open Q1).**

## Performance

- **Duration:** ~9 min
- **Tasks:** 3 (TDD: RED fixtures → nodejs GREEN → user GREEN)
- **Files modified:** 2 (+ 1 new bats fixture, + this summary)

## Accomplishments
- **Task 1 (RED):** Shipped `tests/bats/18-detect-el9.bats` — six EL-07 fixtures driven by a PATH-stub harness: a configurable `rpm` stub emits the `%{VERSION}-%{RELEASE}` line (NodeSource-RPM vs AppStream-module vs absent), a `dnf` stub that must never be reached, a logging `sudo` stub, an in-test override of `nodesource_repo_paths` pointed at a temp repo path the @test creates/removes, and real `jq` building + parsing the fragment. RED was genuine: the dev host's own NodeSource Node leaked through the (then-unguarded) debian dpkg arm, and the user probe still hit `/usr/bin/apt-get`.
- **Task 2 (nodejs GREEN):** Family-branched the distro-package arm of `detect::nodejs_probe`. The debian dual-gate (dpkg-query Version + apt sources) is preserved byte-for-byte inside the `*)` arm; the new `rhel)` arm runs `rpm -q --qf '%{VERSION}-%{RELEASE}\n' nodejs`, probes repo-file presence through `nodesource_repo_paths`, and emits `nodesource` when the release carries the `nodesource` substring AND a repo file is present, else `distro_rpm` (the distinct AppStream-module class) when rpm reports nodejs without the marker, else nothing. Read-only — `rpm -q` + file tests only; `grep -c 'dnf ' = 0`.
- **Task 3 (user GREEN):** Branched the sudo-capability probe binary in `detect::user_probe` — `rhel) probe=/usr/bin/dnf probe_arg=--version` / `*) probe=/usr/bin/apt-get probe_arg=--help` — preserving the absolute-path anchoring security control for the dnf probe and leaving the `can_sudo_apt` variable, the `DETECT_USER_CAN_SUDO_APT` export, the JSON field, and `detect::user_can_sudo_apt()` byte-identical.
- All six EL-07 @tests green; `shellcheck --severity=warning` clean on both fragments; `18-pkg-dispatch.bats` still 13/13 (no regression).

## Task Commits

Each task committed atomically (TDD RED→GREEN→GREEN):

1. **Task 1: EL-07 detection fixtures (RED)** — `85ac760` (test)
2. **Task 2: detect/nodejs.sh rhel NodeSource-RPM + AppStream arms (GREEN)** — `5cc15d8` (feat)
3. **Task 3: detect/user.sh sudo-probe binary branch (GREEN)** — `5aea84b` (feat)

## Files Created/Modified
- `tests/bats/18-detect-el9.bats` (created) — six EL-07 PATH-stub fixtures (classification × 3, read-only invariant, probe-binary branch, field-name preservation).
- `plugin/lib/detect/nodejs.sh` (modified) — family-branched distro-package arm; rhel NodeSource-RPM + AppStream `distro_rpm` arms via `rpm -q` + `nodesource_repo_paths`; debian arm byte-for-byte; header docstring updated with the rhel sources.
- `plugin/lib/detect/user.sh` (modified) — sudo-probe binary branches to `/usr/bin/dnf --version` on rhel; `can_sudo_apt` contract surface unchanged; inline comment updated to note the family branch.
- `.planning/phases/18-detection-branching-foundation/18-05-SUMMARY.md` (created) — this summary.

## Decisions Made
- **AppStream class is `distro_rpm`, not the plan's example `distro_dnf`.** The `distro_dnf ` literal contains the `dnf ` substring forbidden by the read-only acceptance grep (`grep -c 'dnf ' = 0`). `distro_rpm` mirrors the existing debian `distro_apt` class name, is contract-clean, and is more descriptive of the rpm source. The bats fixture was updated to assert `distro_rpm` in lockstep (coupled to the impl in the Task 2 commit).
- **Repo presence via `nodesource_repo_paths`, never a hardcoded path.** The rhel gate iterates the lockstep verb so the detect gate, the 30-nodejs idempotency gate (plan 03), and the agentlinux-install purge cleanup (plan 04) read the same source of truth; `grep '/etc/yum.repos.d/nodesource-nodejs.repo' detect/nodejs.sh` returns nothing (the path lives only in pkg.sh).
- **Key on the `nodesource` substring** (not `-1nodesource`) for robustness across the nodistro repo layout; exact `%{RELEASE}` deferred to the Phase 19 Docker arm (Open Q1).

## Deviations from Plan
None — plan executed exactly as written (TDD RED→GREEN, three tasks committed atomically). One naming substitution that is not a scope change: the AppStream source class is `distro_rpm` rather than the plan's parenthetical example `distro_dnf`, because `distro_dnf ` would violate the plan's own `grep -c 'dnf ' = 0` read-only acceptance gate; the plan explicitly left the class name to "the contract the bats fixture asserts," and the fixture asserts `distro_rpm`.

## Threat Model Disposition
- **T-18-16 (Elevation — sudo-probe binary):** mitigated. The rhel probe is anchored to the absolute path `/usr/bin/dnf` (not a bare `dnf`), preserving the user.sh PATH-shadow security rationale.
- **T-18-17 (Tampering — detection writing dnf cache):** mitigated. The rhel arm uses `rpm -q` + file tests only; `grep -c 'dnf ' detect/nodejs.sh = 0`; the read-only @test asserts no write-path dnf subcommand fires.
- **T-18-18 (Spoofing — NodeSource misclassification):** mitigated. Dual gate (`nodesource` substring in the rpm release AND a repo file present); AppStream is the distinct `distro_rpm` class. Exact release string live-verified on almalinux:9 (Phase 19) before locking.
- **T-18-19 (Tampering — renaming can_sudo_apt):** mitigated. Variable/export/JSON-field/accessor names frozen; only the probe binary branches; acceptance asserts `can_sudo_pkg` is absent.

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- Plan 18-05 is the last plan-18 detection site. Combined with plans 02/03/04, the EL9 port's detection + verb layer is code-complete and unit-proven on the dev host.
- **Carried (Phase 19, Open Q1):** the `nodesource` substring in `rpm -q --qf '%{VERSION}-%{RELEASE}' nodejs` is unverified live — confirm on the `almalinux:9` Docker arm (`dnf install -y nodejs` then the `rpm -q` query) before locking the DET-02 classifier. The rhel arms here are unit-proven via PATH stubs only.

## Self-Check: PASSED

- Files: `tests/bats/18-detect-el9.bats`, `plugin/lib/detect/nodejs.sh`, `plugin/lib/detect/user.sh`, `18-05-SUMMARY.md` — all present.
- Commits `85ac760`, `5cc15d8`, `5aea84b` — all in git history.
- `bats tests/bats/18-detect-el9.bats` → 6/6 green; `shellcheck --severity=warning plugin/lib/detect/{nodejs,user}.sh` → exit 0; `grep -c 'dnf ' plugin/lib/detect/nodejs.sh` → 0; `can_sudo_apt` present + `can_sudo_pkg` absent in user.sh; `18-pkg-dispatch.bats` → 13/13 (no regression).

---
*Phase: 18-detection-branching-foundation*
*Completed: 2026-06-28*
