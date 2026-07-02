---
phase: 18-detection-branching-foundation
plan: 04
subsystem: infra
tags: [entrypoint, almalinux, el9, bash, apt, dnf, nodesource, purge, verb-layer]

# Dependency graph
requires:
  - phase: 18-detection-branching-foundation
    plan: 02
    provides: "plugin/lib/pkg.sh verbs — pkg_install, pkg_remove, pkg_autoremove, nodesource_repo_paths"
  - phase: 18-detection-branching-foundation
    plan: 03
    provides: "30-nodejs.sh idempotency gate already iterates nodesource_repo_paths — the lockstep source of truth this plan reuses for purge"
  - phase: 17 (v0.3.4 baseline)
    provides: "the entrypoint orchestration (sourcing block, ensure_jq, run_purge teardown)"
provides:
  - "bin/agentlinux-install sources pkg.sh in the lib-loading block (after distro_detect.sh, before idempotency.sh) so the verbs are available to ensure_jq, run_purge, and every provisioner/detect fragment"
  - "ensure_jq installs jq via pkg_install (no inline apt-get)"
  - "run_purge removes the family-correct NodeSource repo files by iterating nodesource_repo_paths, and removes nodejs via pkg_remove/pkg_autoremove"
  - "zero residual apt-get/dpkg in the entrypoint — every package mutation routes through pkg.sh (EL-02 entrypoint half complete)"
affects: [phase-19-docker, phase-20-behavior-green]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Entrypoint call sites are package-manager-neutral: ensure_jq + run_purge call pkg.sh verbs, never an inline apt-get (Anti-Pattern 2)"
    - "run_purge Step 4 iterates nodesource_repo_paths — the single source of truth shared with the 30-nodejs idempotency gate (plan 03) and the detect gate (plan 05) so install/purge cannot drift on either family"
    - "pkg.sh sourced before idempotency.sh is safe — it only DECLARES functions at source time; verbs resolve at call time after detect_distro sets AGENTLINUX_DISTRO_FAMILY"

key-files:
  created:
    - .planning/phases/18-detection-branching-foundation/18-04-SUMMARY.md
  modified:
    - plugin/bin/agentlinux-install

key-decisions:
  - "pkg.sh sourced immediately after distro_detect.sh and before idempotency.sh (per Research Pattern 2 / Assumption A3): sourcing order is safe because pkg.sh defines functions only — no verb is called until detect_distro runs at :435 and exports AGENTLINUX_DISTRO_FAMILY"
  - "run_purge Step 4 reuses nodesource_repo_paths via a `while IFS= read -r … done < <(nodesource_repo_paths)` loop rather than the prior three hardcoded apt rm -f lines, so --purge on EL9 cleans /etc/yum.repos.d/nodesource-nodejs.repo (+ nsolid) instead of leaving the repo behind — in lockstep with the install gate (T-18-14 install/purge symmetry)"
  - "apt-get literals in the --remove-nodejs help text, the run_purge header comment, and the Step-5 log line were reworded to family-neutral prose so the strict `grep -c apt-get = 0` gate reads 0 while the prose stays accurate (the commands themselves moved into pkg.sh) — mirrors the same comment-token rewording done in plan 03"

patterns-established:
  - "Pattern: entrypoint-as-verb-caller — the installer entrypoint never branches the package manager; ensure_jq + run_purge call pkg.sh verbs that own the one family fork (18-RESEARCH.md Pattern 2)"

requirements-completed: [EL-02]

# Metrics
duration: ~5min
completed: 2026-06-28
---

# Phase 18 Plan 04: Entrypoint pkg.sh Wiring (ensure_jq + run_purge) Summary

**plugin/bin/agentlinux-install now sources plugin/lib/pkg.sh in the lib-loading block (after distro_detect.sh, before idempotency.sh) and routes its two package-manager call sites through the verbs: `ensure_jq` installs jq via `pkg_install`, and `run_purge` cleans the family-correct NodeSource repo files by iterating `nodesource_repo_paths` and removes nodejs via `pkg_remove`/`pkg_autoremove` — completing the entrypoint half of EL-02 with zero residual apt-get/dpkg and a `--purge` that, on EL9, cleans the yum repo it created rather than the apt one. Ubuntu behavior is byte-for-byte preserved inside the verbs; the agent-user removal, sudoers drop-in removal, and log removal stay distro-agnostic and unchanged.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-28
- **Completed:** 2026-06-28
- **Tasks:** 2 (both `type=auto`)
- **Files modified:** 1 entrypoint (+ this summary)

## Accomplishments
- **Task 1 — source pkg.sh:** Inserted `. "$LIB_DIR/pkg.sh"` (with the matching `# shellcheck source=../lib/pkg.sh` directive and an explanatory comment) immediately after the `distro_detect.sh` source and before `idempotency.sh`. No other source line reordered. Sourcing order asserted via `awk` (distro_detect < pkg < idempotency).
- **Task 2 — ensure_jq:** Replaced the inline `apt-get update` + `apt-get install -y --no-install-recommends jq` pair with a single `pkg_install jq`, keeping the `command -v jq` guard and the `log_warn`.
- **Task 2 — run_purge Step 4:** Replaced the three hardcoded `rm -f /etc/apt/...` NodeSource repo lines with a `while IFS= read -r repo_file; do rm -f "$repo_file"; done < <(nodesource_repo_paths)` loop, so EL9's `/etc/yum.repos.d/nodesource-nodejs.repo` (+ `nodesource-nsolid.repo`) is cleaned on purge and Ubuntu's deb822/legacy sources + preferences pin are still removed — all from the one source of truth.
- **Task 2 — run_purge Step 5:** Replaced `apt-get purge -y nodejs` / `apt-get autoremove -y` with `pkg_remove nodejs || log_warn "purge nodejs failed"` and `pkg_autoremove || true`.
- **Zero residual package commands:** `grep -rn 'apt-get\|dpkg' plugin/bin/agentlinux-install` returns nothing; reworded the `apt-get` mentions in the `--remove-nodejs` help text, the `run_purge` header comment, and the Step-5 log line to family-neutral prose.
- **Distro-agnostic teardown intact:** `rm -f /etc/sudoers.d/agentlinux`, the agent-user removal (pkill/userdel), and the install-log removal are byte-identical.

## Task Commits

Each task committed atomically:

1. **Task 1: source pkg.sh in the entrypoint lib-loading block** — `96a8b26` (feat)
2. **Task 2: ensure_jq + run_purge → pkg verbs** — `8a2d659` (feat)

## Files Created/Modified
- `plugin/bin/agentlinux-install` (modified) — sources pkg.sh at the correct order point; ensure_jq + run_purge route through pkg verbs; zero residual apt-get/dpkg.
- `.planning/phases/18-detection-branching-foundation/18-04-SUMMARY.md` (created) — this summary.

## Decisions Made
- **pkg.sh source position:** immediately after `distro_detect.sh`, before `idempotency.sh` (Research Pattern 2 / Assumption A3). Safe because pkg.sh only DECLARES functions at source time — no verb is invoked until `detect_distro` runs at `:435` and exports `AGENTLINUX_DISTRO_FAMILY`. Documented inline so the order is not "fixed up" by a later editor.
- **Purge reuses `nodesource_repo_paths`:** the Step-4 loop iterates the same verb the 30-nodejs idempotency gate (plan 03) and the detect gate (plan 05) use, guaranteeing install/purge symmetry on both families (mitigates T-18-14). Each path is a static in-code literal per family — no globbing, no user input — so the `rm -f` loop introduces no new tampering surface (mitigates T-18-13).
- **Comment/help-text token rewording:** the strict `grep -c apt-get = 0` acceptance gate required rewording the three remaining `apt-get` prose references (help text, header comment, log line). The reworded strings are semantically identical and the commands themselves already moved into pkg.sh — a documentation-only adjustment mirroring plan 03's approach.

## Deviations from Plan
None — plan executed exactly as written (both `type=auto` tasks, each committed atomically). One implementation note (not a scope change): satisfying the `grep -c apt-get = 0` gate required rewording three comment/help/log references to `apt-get` that the plan called out only for the two code call sites. The reworded prose is family-neutral and accurate; the package-manager commands themselves were already removed.

## Threat Model Disposition
- **T-18-13 (Tampering — repo-path loop deleting wrong files):** mitigated. Paths come only from `nodesource_repo_paths` (static per-family literals), each an explicit `rm -f "$repo_file"` with no wildcard expansion.
- **T-18-14 (Repudiation — purge leaving EL9 repo behind):** mitigated. Routing purge through the same source of truth as the install gate guarantees install/purge symmetry on both families.
- **T-18-15 (Injection — verb args):** accepted. Args are fixed literals (`jq`, `nodejs`); no untrusted string reaches a verb.

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- The entrypoint now runs entirely on the verb layer for package work; combined with plans 02/03, the only remaining plan-18 site is `lib/detect/nodejs.sh` + `lib/detect/user.sh` (plan 05 — rhel `nodesource` substring arm + dnf sudo probe, preserving the `can_sudo_apt` field name).
- **Carried (Phase 19):** the rhel arms remain unit-proven on the Ubuntu dev host via PATH stubs only. Real EL9 behavior — `pkg_install jq` landing jq via dnf, and `--purge` removing `/etc/yum.repos.d/nodesource-nodejs.repo` + `dnf remove/autoremove nodejs` — must be confirmed on the `almalinux:9` Docker substrate.

## Self-Check: PASSED

- Files: `plugin/bin/agentlinux-install`, `18-04-SUMMARY.md` — present.
- Commits `96a8b26`, `8a2d659` — both in git history.
- `shellcheck --severity=warning --shell=bash --external-sources plugin/bin/agentlinux-install` → exit 0; `grep -rn 'apt-get\|dpkg' plugin/bin/agentlinux-install` → no matches; sourcing order (distro_detect < pkg < idempotency) asserted; `nodesource_repo_paths` referenced by both 30-nodejs.sh and the entrypoint (install/purge symmetry); `bats tests/bats/18-pkg-dispatch.bats` → 13/13 green.

---
*Phase: 18-detection-branching-foundation*
*Completed: 2026-06-28*
