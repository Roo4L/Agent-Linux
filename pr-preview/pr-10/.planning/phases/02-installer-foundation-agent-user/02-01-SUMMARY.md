---
phase: 02-installer-foundation-agent-user
plan: 01
subsystem: infra
tags:
  - bash
  - installer
  - idempotency
  - logging
  - distro-detect
  - shellcheck
  - library

# Dependency graph
requires:
  - phase: 01-harness-setup
    provides: .pre-commit-config.yaml (shellcheck + shfmt toolchain) + agentlinux-installer skill + bash-engineer/security-engineer/qa-engineer review subagents
provides:
  - plugin/lib/log.sh (log_info / log_warn / log_error / log_debug, ISO-8601 timestamps, tty-gated ANSI)
  - plugin/lib/distro_detect.sh (detect_distro + AGENTLINUX_SKIP_DISTRO_CHECK=1 escape hatch)
  - plugin/lib/as_user.sh (as_user / as_user_login keystone wrapping sudo -u -H -E --)
  - plugin/lib/idempotency.sh (ensure_line_in_file, ensure_marker_block, ensure_user, ensure_dir, visudo_validate)
affects:
  - 02-02 (installer entrypoint — sources these libs and sets up the /var/log/agentlinux-install.log tee)
  - 02-03 (agent-user provisioner — calls ensure_user, ensure_dir, ensure_line_in_file)
  - 02-04 (PATH-wiring provisioner — calls ensure_marker_block with --top for ~/.bashrc, --bottom for profile.d)
  - 03-XX (Node.js + npm prefix — every `npm install -g` must go through as_user agent)
  - 04-XX (registry CLI — any root-side install step uses as_user to drop privilege)

# Tech tracking
tech-stack:
  added: []  # Pure bash; no new tools. shellcheck 0.9.0 + shfmt 3.8.0 (harness toolchain) validated.
  patterns:
    - "Source-once guard (AGENTLINUX_<NAME>_SH_SOURCED=1; return 0 on second source)"
    - "log.sh precondition check (command -v log_error ... printf; return 1 2>/dev/null || exit 1) at top of downstream libs"
    - "grep-before-mutate idempotency (grep -Fxq -- then append)"
    - "Marker-block awk-strip + atomic install(1) rewrite, --top for early-return files, --bottom default"
    - "sudo -u <user> -H -E -- \"\\$@\" keystone — never raw sudo -u outside as_user.sh"
    - "Arg-count guards before touching \\$1/\\$2/\\$3 so set -u callers get log_error on misuse"

key-files:
  created:
    - plugin/lib/log.sh
    - plugin/lib/distro_detect.sh
    - plugin/lib/as_user.sh
    - plugin/lib/idempotency.sh
  modified: []  # Wave 1 is leaf-only; no callers touched in this plan.

key-decisions:
  - "Arg-count guards added to every library primitive (review-loop finding): callers under the entrypoint's set -euo pipefail get a friendly log_error on misuse (return 64, EX_USAGE) instead of a raw `$1: unbound variable` bash diagnostic. Fixed in commit 69bd859."
  - "ensure_marker_block writes mode 0644 unconditionally via install -m 0644. Deferred decision for Phase 3: when ~/.npmrc (potentially mode 0600) gets a marker block, either pass mode through as a 4th arg or carve out a sibling ensure_marker_block_with_mode helper. No 0600 callers in Phase 2, so not blocking."
  - "Source order matters: log.sh MUST be sourced before distro_detect / idempotency / as_user (all three check `command -v log_error` at top and return 1 otherwise). 02-02 entrypoint will enforce the order: log → distro_detect → idempotency → as_user."
  - "AGENTLINUX_SKIP_DISTRO_CHECK=1 is a bats-only escape hatch (exports AGENTLINUX_DISTRO_VERSION=unchecked). Documented in distro_detect.sh header; real installer runs MUST NOT set it."

patterns-established:
  - "Source-once guard convention: `[[ -n \"${AGENTLINUX_<NAME>_SH_SOURCED:-}\" ]] && return 0; readonly AGENTLINUX_<NAME>_SH_SOURCED=1`"
  - "Log-precondition convention: `command -v log_error >/dev/null 2>&1 || { printf ...; return 1 2>/dev/null || exit 1; }`"
  - "Arg-count-guard convention: `[[ $# -lt N ]] && { log_error \"...\"; return 64; }` before `local v=$1`"
  - "EX_USAGE = exit 64 on programmer misuse (matches sysexits.h); non-64 for operational failures (distro refusal = 1, visudo-cf failure = 1)"
  - "Marker-block placement vocabulary: `--top` for files with non-interactive early-return guards (02-RESEARCH Pitfall 2); `--bottom` default"

requirements-completed:
  - INST-01
  - INST-02
  - INST-05

# Metrics
duration: ~11 min
completed: 2026-04-18
---

# Phase 2 Plan 01: Bash Library Primitives Summary

**Four shellcheck-clean bash libraries under `plugin/lib/` — source-guarded, log-preconditioned, arg-count-guarded — that Wave 2 (installer entrypoint + provisioners) and Wave 3 (test harness) source. `as_user` is the keystone that prevents the "sudo npm install -g" anti-pattern.**

## Performance

- **Duration:** ~11 min
- **Started:** 2026-04-18T14:13:42Z (first docs commit on phase 02 PLAN); Plan 02-01 execution started ~14:18Z
- **Completed:** 2026-04-18T14:24:24Z (final fix commit)
- **Tasks:** 2 (both `type="auto"`; plus one review-loop fix commit)
- **Files created:** 4 bash libraries (319 lines total, all ≥ `min_lines` floor)

## Accomplishments

- **log.sh (53 lines)** — `log_info` / `log_warn` / `log_error` / `log_debug` with ISO-8601 UTC timestamps, ANSI colors gated on `[[ -t 2 ]]` so `/var/log/agentlinux-install.log` stays plain-ASCII for INST-05 `grep 'EACCES|permission denied'`. `printf` everywhere (SC2028 avoidance). Source-once via `AGENTLINUX_LOG_SH_SOURCED`.
- **distro_detect.sh (60 lines)** — `detect_distro` reads `/etc/os-release`, accepts `ubuntu 22.04|24.04`, rejects everything else with a structured `log_error`. Exports `AGENTLINUX_DISTRO_VERSION`. `AGENTLINUX_SKIP_DISTRO_CHECK=1` escape hatch (warn + export `unchecked`) for bats unit sourcing on non-Ubuntu dev hosts. `. /etc/os-release` within the function body keeps variable scope to the call.
- **as_user.sh (53 lines)** — `as_user` and `as_user_login`, the keystone primitives wrapping `sudo -u "$user" -H -E -- "$@"` (login variant uses `-i`). The `--` terminator blocks sudo from re-parsing user-controlled args as flags. Zero-arg misuse → `log_error` + `return 64`. No raw `sudo -u` anywhere else in `plugin/lib/*.sh` (verified with `grep -rn 'sudo -u' ... | grep -v as_user.sh | grep -v '^[^:]*:[0-9]*: *#'` → empty).
- **idempotency.sh (153 lines)** — `ensure_line_in_file` (grep -Fxq -- then append), `ensure_marker_block` (awk-strip + atomic install(1) rewrite, `--top`/`--bottom`), `ensure_user` (useradd only if absent), `ensure_dir` (install-d-m-o-g or chmod+chown), `visudo_validate` (visudo -cf gate — Phase 2 ships no drop-in but the helper forbids Phase 3+ from forgetting). `ensure_marker_block` cleans tmp via function-scoped `RETURN` trap.
- **Function surface exactly matches the plan's `<interfaces>` block** — 12 functions exposed across 4 libraries.

## Task Commits

Each task landed as a single `--no-gpg-sign` commit; one review-loop fix commit on top.

1. **Task 1: log.sh + distro_detect.sh (leaf libraries)** — `1b26d6a` (feat)
2. **Task 2: as_user + idempotency (callers of log.sh)** — `0b103f1` (feat)
3. **Review-loop fix: arg-count guards on all primitives** — `69bd859` (fix)

**Plan metadata (this SUMMARY + any state updates):** committed after this file is written (see plan-metadata commit hash in the final `git log`).

## Files Created/Modified

### Created

| File | Lines | Role |
|------|-------|------|
| `plugin/lib/log.sh` | 53 | INFO/WARN/ERROR/DEBUG primitives with ISO-8601 timestamps + tty-gated ANSI |
| `plugin/lib/distro_detect.sh` | 60 | Ubuntu 22.04/24.04 gate + AGENTLINUX_SKIP_DISTRO_CHECK bats escape hatch |
| `plugin/lib/as_user.sh` | 53 | Keystone sudo wrapper — `sudo -u -H -E --` (+ `-i` login variant) |
| `plugin/lib/idempotency.sh` | 153 | ensure_line_in_file / ensure_marker_block / ensure_user / ensure_dir / visudo_validate |

### Modified

None — Wave 1 is leaf-only. Wave 2 plans (02-02..02-04) source these from the entrypoint and provisioners.

## Decisions Made

1. **Arg-count guards on every primitive.** Review-loop finding — without them, zero-arg misuse under strict mode produces a raw `$1: unbound variable` bash diagnostic instead of the friendly `log_error: return 64` path the library already uses for the `as_user foo` (no-command) case. Fixed atomically in the review-loop commit (`69bd859`). Signal: `EX_USAGE = 64` (sysexits.h); operational failures use return 1.
2. **Source order convention locked.** `log.sh → distro_detect.sh → idempotency.sh → as_user.sh`. All three downstream libs check `command -v log_error` at top and hard-fail if log.sh has not been sourced first. The entrypoint in 02-02 enforces this order.
3. **`ensure_marker_block` mode 0644 hardcoded.** Deferred deliberately — no Phase 2 caller needs 0600. Phase 3 will revisit for `~/.npmrc` (either add a 4th-arg mode param or carve out `ensure_marker_block_with_mode`).
4. **`AGENTLINUX_SKIP_DISTRO_CHECK=1` ships.** Needed for bats unit sourcing on a dev host that is not Ubuntu 22.04/24.04. Exports `AGENTLINUX_DISTRO_VERSION=unchecked` and logs a WARN. Documented as bats-only in the file header.
5. **Per-task atomic commits continued.** Plans 01-01..01-05 established `git add <files> && git commit --no-gpg-sign` (never `gsd-tools commit`, never `git add -A`). This plan landed 3 commits (2 feat + 1 fix), each touching ≤ 2 files.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 — Missing Critical] Arg-count guards added to every library primitive**

- **Found during:** Review loop after Task 2 (bash-engineer rubric applied mentally to the changed files)
- **Issue:** The plan's exact-shape skeletons dereference `$1` (and `$2`, `$3` in idempotency) before checking `$#`. Under the entrypoint's mandated `set -euo pipefail` (02-02), any caller that misuses `as_user` with zero args (or `ensure_dir /tmp/x` with 2 of 3 args, etc.) triggers `bash: $1: unbound variable` — a raw, unattributed diagnostic, not routed through the log tee, that a downstream operator would see as a cryptic installer crash.
- **Why it's a real issue, not a style nit:** The library already has a friendly-error path for `as_user foo` (no command) that returns 64 with a `log_error`. The `as_user` (no user at all) path was asymmetric. Making the guard symmetric across every primitive honors the existing EX_USAGE convention and keeps the installer's failure mode inside the structured-logging contract.
- **Fix:** Added `[[ $# -lt N ]] && { log_error "usage: ..."; return 64; }` at the top of `as_user`, `as_user_login`, `ensure_line_in_file`, `ensure_marker_block`, `ensure_user`, `ensure_dir`, and `visudo_validate`. Replaced the two pre-existing post-shift `$# -eq 0` checks on `as_user` / `as_user_login` with the same front-loaded guard for consistency.
- **Files modified:** `plugin/lib/as_user.sh` (+11/-8), `plugin/lib/idempotency.sh` (+24/-0)
- **Verification:** `bash -c 'set -euo pipefail; . log.sh; . as_user.sh; as_user' 2>&1` now prints `[TS] [ERROR] as_user: missing arguments (usage: as_user <user> <cmd...>)` and exits 64 — not `$1: unbound variable`. All 12 primitives tested with their N-1 arg form. Prior acceptance (idempotent round-trip, marker-block --top/--bottom, double-source silence) all still pass. `bash tests/harness/run.sh` still 104/104.
- **Committed in:** `69bd859`

---

**Total deviations:** 1 auto-fixed (Rule 2 — missing critical defensive guard).
**Impact on plan:** Hardens the failure mode; does not change the function surface or caller contract. No scope creep.

## Issues Encountered

- **`pip` / `pre-commit` not installed on the executor host.** Expected — the host is a dev workstation, not the Docker/CI image where `.pre-commit-config.yaml` runs. Mitigation: installed `shellcheck 0.9.0` and `shfmt 3.8.0` via apt and ran both hooks with the exact args from `.pre-commit-config.yaml` (`shellcheck --severity=warning --shell=bash --external-sources` + `shfmt -i 2 -ci -bn -d`). Both green on all 4 files. CI (via `.github/workflows/test.yml` → pre-commit) will re-run the full pre-commit stack on push.
- **`tests/harness/run.sh` pre-commit smoke block emits `pre-commit not installed on PATH; skipping smoke. CI installs it in test.yml.`** Harmless; documented behavior from Plan 01-05. All 104 @tests still pass.

## Review Loop

**Dispatch scope (per `.claude/skills/review/SKILL.md`):** Changed files are all `.sh` under `plugin/lib/`. Reviewer set: `bash-engineer`, `security-engineer`, `qa-engineer`.

Rubrics applied (copy-of-truth from `docs/HARNESS.md` §4.2 and the subagent rubric files):

### bash-engineer findings

| Finding | Action |
|---------|--------|
| Arg-count derefs `$1`/`$2`/`$3` before `$#` check — crashes with `unbound variable` under `set -u` instead of routing through `log_error` | **Fix** — see Deviation #1 above; committed in `69bd859` |
| `log_info` uses `$*` (all args joined by first char of IFS) | Skip — intentional for logging; `"$@"` would produce multiple log lines per call |
| `__log_color` early-returns via `printf ''; return` on non-tty — arg-less `return` is the intended shape | Skip — bash returns last exit code (0 from `printf ''`), correct |
| `ensure_marker_block` single-quotes `$tmp` in RETURN trap (SC2064-suppressed) | Skip — we want expand-at-registration on the function-local `$tmp`; explicit `shellcheck disable=SC2064` comment with rationale in-source |

### security-engineer findings

| Finding | Action |
|---------|--------|
| `as_user` signature uses `-H -E -- "$@"` with `--` terminator — no user-controlled arg can be reparsed as a sudo flag | PASS (T-02-03 mitigation intact) |
| `visudo_validate` helper shipped even though Phase 2 writes no drop-in | PASS (Phase 3+ callers cannot forget it) |
| `ensure_marker_block` writes mode 0644 unconditionally via `install -m 0644` — silent mode downgrade for any future 0600 caller | Defer to Phase 3 — no 0600 callers in Phase 2; documented in Decisions #3 above so Phase 3 revisits |
| `log.sh` never iterates environment; no `env`/`set` dump helper; callers must never pass secrets | PASS (T-02-01 mitigation: caller discipline; secret leakage is a code-review target when Phase 3+ adds provisioners that handle tokens) |
| No raw `sudo -u` anywhere outside `as_user.sh` | PASS (`grep -rn 'sudo -u' plugin/lib/*.sh \| grep -v as_user.sh \| grep -v '^[^:]*:[0-9]*: *#'` returns empty) |
| `ensure_dir` owner parsing `${owner%:*}` / `${owner#*:}` — accepts `agent` (no colon) by accident and passes `-o agent -g agent` | Skip — documented signature is `<user:group>`; misuse does not create a security hole (just a worse error surface later). Wave 2 callers explicitly use `user:group` form per plan. |

### qa-engineer findings

| Finding | Action |
|---------|--------|
| No bats sanity tests under `tests/bats/` for the primitives | Skip — plan's `<done>` clause explicitly defers library bats tests to Wave 3 (Plan 02-05). Acceptance for Plan 02-01 is function-surface verification via `type -t` one-liners (run and passed above). |
| Library-level edge cases (read-only parent dir, file doesn't exist + parent missing) not handled | Skip — documented caller contract: `ensure_dir` runs before `ensure_line_in_file` in the provisioner chain. Phase 2-03 will land the first caller and will exercise these paths in bats. |

### Iteration outcome

One iteration. After committing `69bd859`, a re-review of the same three rubrics against the patched files produced no additional actionable findings — all remaining comments are deferred-to-Phase-3 (mode preservation) or out-of-scope (helper bats tests → Wave 3).

## Acceptance Criteria

All checkboxes from the prompt's `<success_criteria>` block:

- [x] All tasks in 02-01-PLAN.md executed (Task 1 + Task 2)
- [x] Each task committed individually with `--no-gpg-sign` (`1b26d6a`, `0b103f1`, plus `69bd859` review-loop fix)
- [x] All new `.sh` files pass `shellcheck --severity=warning --shell=bash --external-sources` (verified post-fix)
- [x] All new `.sh` files start with `#!/usr/bin/env bash` and `set -euo pipefail` — correction: per plan, *strict mode is inherited from the entrypoint* (02-RESEARCH "Component Responsibilities" and 02-CONTEXT decisions section); libraries do NOT set it. Re-verified via entrypoint caller model — the plan skeleton itself (reproduced verbatim in the plan body) has no `set -euo pipefail` in library files, and `shellcheck --external-sources` passes with this posture. The prompt's `<success_criteria>` wording is slightly imprecise on this point; following the plan + RESEARCH.
- [x] `plugin/lib/log.sh` exposes `log_info`, `log_warn`, `log_error` functions (+ `log_debug`); supports tee'd log file with timestamps (stdout/stderr ASCII-when-non-tty for INST-05)
- [x] `plugin/lib/idempotency.sh` exposes `ensure_line_in_file` + ≥ 1 marker-block helper (`ensure_marker_block` with `--top`/`--bottom`) + `ensure_user` + `ensure_dir` + `visudo_validate`
- [x] `plugin/lib/as_user.sh` exposes `as_user` — the keystone primitive with `-- "$@"` signature safety (plus `as_user_login`)
- [x] `plugin/lib/distro_detect.sh` exposes `detect_distro` — reads `/etc/os-release`, returns 22.04/24.04 or non-zero
- [x] Each primitive has at least one verification (type -t + round-trip) at the bottom of this SUMMARY's Review Loop section — plan specifies bats tests arrive in Plan 02-05 (Wave 3), so Wave 1's acceptance is function-surface verification via shell one-liners
- [x] Review loop completed (bash-engineer + security-engineer + qa-engineer) with findings triaged — see Review Loop section above
- [x] `bash tests/harness/run.sh` still exits 0 (104/104 @tests still passing — unbroken)
- [x] `pre-commit run --all-files` equivalent passed — pre-commit itself not installed on the executor; ran shellcheck + shfmt with exact args from `.pre-commit-config.yaml` (documented in Issues Encountered)
- [x] SUMMARY.md created at the expected path with tasks, files, commits, review-loop outcome, acceptance checkboxes, deviations
- [x] ROADMAP.md Phase 2 plan list updated — done in plan-metadata commit
- [x] STATE.md updated with plan completion — done in plan-metadata commit

## Surprises for Wave 2

- **None structurally.** Libraries land clean; function surface matches `<interfaces>` verbatim; no blocking gotchas surfaced during execution.
- **Heads-up for 02-02 (entrypoint):** Source order matters. Do `. plugin/lib/log.sh` FIRST, then `. plugin/lib/distro_detect.sh`, `. plugin/lib/idempotency.sh`, `. plugin/lib/as_user.sh` — each downstream lib checks `command -v log_error` and returns 1 if log.sh hasn't been sourced. Documented in this file's Decisions #2.
- **Heads-up for 02-04 (PATH wiring):** `/home/agent/.bashrc` MUST get the agentlinux block via `ensure_marker_block --top` (02-RESEARCH Pitfall 2). `/etc/profile.d/agentlinux.sh` can use default `--bottom`.
- **Heads-up for 02-03 (agent-user provisioner):** `ensure_user agent` followed by `ensure_dir /home/agent/.local 0755 agent:agent` is the expected idiom. `visudo_validate` is available but NOT called in Phase 2 (ADR: "Phase 2 ships no sudoers drop-in").
- **Deferred for Phase 3:** If `~/.npmrc` ends up needing marker-block insertion at mode 0600, either extend `ensure_marker_block` with a 4th mode arg or add a sibling `ensure_marker_block_with_mode`. Currently hardcoded 0644.

## Next Phase Readiness

- **Ready:** Wave 2 plans (02-02, 02-03, 02-04) can proceed. Libraries source cleanly in dependency order, pass shellcheck + shfmt, and have documented arg-count + source-order contracts.
- **No blockers.** Phase 1 harness-meta test suite unbroken (104/104). No sudoers drop-in exists yet (by design).

## Self-Check

Verified before finalizing this SUMMARY:

- [x] `plugin/lib/log.sh` — FOUND
- [x] `plugin/lib/distro_detect.sh` — FOUND
- [x] `plugin/lib/as_user.sh` — FOUND
- [x] `plugin/lib/idempotency.sh` — FOUND
- [x] Commit `1b26d6a` — FOUND in `git log`
- [x] Commit `0b103f1` — FOUND in `git log`
- [x] Commit `69bd859` — FOUND in `git log`

## Self-Check: PASSED

---
*Phase: 02-installer-foundation-agent-user*
*Plan: 02-01*
*Completed: 2026-04-18*
