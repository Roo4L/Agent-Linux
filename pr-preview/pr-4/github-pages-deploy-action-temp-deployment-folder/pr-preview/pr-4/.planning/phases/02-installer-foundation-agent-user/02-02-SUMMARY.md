---
phase: 02-installer-foundation-agent-user
plan: 02
subsystem: installer
tags:
  - bash
  - installer
  - entrypoint
  - logging
  - idempotency
  - tee
  - trap-err
  - trap-exit

# Dependency graph
requires:
  - phase: 02-installer-foundation-agent-user
    plan: 01
    provides: plugin/lib/{log,distro_detect,idempotency,as_user}.sh — log_info/warn/error/debug, detect_distro, as_user / as_user_login, ensure_line_in_file / ensure_marker_block / ensure_user / ensure_dir / visudo_validate
provides:
  - plugin/bin/agentlinux-install (real entrypoint: strict mode + pre-parse UX flags + log-file init + tee + ERR/EXIT traps + arg parsing + root check + distro detect + provisioner dispatch)
  - /var/log/agentlinux-install.log — single greppable transcript (stdout+stderr merged, INST-05 target)
affects:
  - 02-03 (agent-user provisioner — sourced under this entrypoint; inherits strict mode + traps + tee)
  - 02-04 (PATH wiring provisioner — same)
  - 02-05 (Docker bats harness — will grep the log for EACCES|permission denied; will exercise --help/--version/--purge UX paths)
  - packaging/curl-installer/install.sh (Phase 6 — calls this entrypoint after SHA-verified tarball extract)

# Tech tracking
tech-stack:
  added: []  # Pure bash; uses only bash builtins + coreutils (install, tee, sync) already on every Ubuntu.
  patterns:
    - "pre-parse fast-exit for --help/--version/--purge before log-init (UX: print-and-exit flags work without sudo)"
    - "install -m 0644 /dev/null <logfile> — atomic root-owned 0644 log file creation before tee redirect"
    - "exec > >(tee -a) 2>&1 — merge stderr into stdout through tee so INST-05 greps the single transcript"
    - "trap 'exec >&- 2>&-; wait \"$TEE_PID\"' EXIT — close FDs before wait so tee sees EOF (Pitfall 6 mitigation; bare `trap wait EXIT` deadlocks because EXIT trap runs before bash drops caller's FDs)"
    - "trap on_error ERR — prints failing source:line + transcript path via log_error, then exits"
    - "mapfile -t + compgen -G for glob expansion — sidesteps shfmt 3.8.0 lexer bug on array-assignment with leading character class (see Deviations §1)"
    - "SC2155 split: declare + assign as two statements so cmdsub exit codes are not masked by `readonly`"
    - "Defensive redundant branches in parse_args for --help/-h/-V/--version/--purge (pre_parse_args handles them; keeping branches makes the function robust to future refactors)"

key-files:
  created: []
  modified:
    - plugin/bin/agentlinux-install  # 5-line stub → 194-line real entrypoint

key-decisions:
  - "Pre-parse fast-exit introduced for --help/--version/--purge. Plan skeleton lines 162-172 put log-file init before parse_args, which broke the acceptance criterion `bash plugin/bin/agentlinux-install --help` exits 0 on a non-root invocation. Fix: added a `pre_parse_args` function that walks argv BEFORE log-init and print-and-exits for -h/--help/-V/--version/--purge. Non-mutating flags, so running without root is correct UX (CONTEXT.md Installer UX & Logging locks this behavior). --verbose and unknown flags still fall through to parse_args post log-init so diagnostics are captured by the tee."
  - "trap 'wait' EXIT replaced with trap 'exec >&- 2>&-; wait \"$TEE_PID\" 2>/dev/null || true' EXIT. Plan's Pitfall 6 mitigation (per RESEARCH.md line 699) is `trap 'wait' EXIT` — but in practice this deadlocks: the EXIT trap runs BEFORE bash drops the caller's FDs, so tee never sees EOF on its stdin and `wait` blocks forever. Reproduced locally (installer hung after emitting exit). Fix: close FD 1+2 in the trap (delivers EOF to tee) and wait on the saved TEE_PID specifically. Verified: log file has the full final line after exit; no hang."
  - "Provisioner glob via `mapfile -t steps < <(compgen -G \"$PROV_DIR/[0-9][0-9]-*.sh\" || true)` instead of `steps=(\"$PROV_DIR\"/[0-9][0-9]-*.sh)`. shfmt 3.8.0's lexer misparses `[0-9][0-9]` immediately after a word as an array subscript (\"[x]\" must be followed by =), failing `shfmt -d`. compgen -G is a bash builtin that takes the glob as a string and returns lexical matches — same behavior, no lexer trip. `|| true` lets the no-match case return cleanly without tripping `set -e`."
  - "SC2155 addressed by splitting `readonly BIN_DIR=\"$(...)\"` into `BIN_DIR=\"$(...)\"; readonly BIN_DIR`. This is the only way to propagate cmdsub failure under strict mode — `readonly X=$(false)` returns 0 because the assignment succeeded even though the cmdsub failed."
  - "install -m 0644 log-file init kept. A7 in RESEARCH.md flags symlink-follow as a MEDIUM-risk attack on paranoid multi-tenant hosts; plan threat model disposition for T-02-06 is `accept` (root installer on clean Ubuntu) with Phase 3+ revisit when log content gets secret-adjacent. In-source comment at lines 74-76 names the trade-off."
  - "parse_args retains unreachable -h/-V/--purge branches (defensive fallthrough). Comment at lines 125-127 documents that pre_parse_args handles them; keeping the cases makes parse_args robust to a future refactor that might drop or rearrange pre_parse_args. Cost: three unreachable lines. Benefit: parse_args is a self-contained unit that reads correctly."

patterns-established:
  - "Fast-exit argv pre-parse BEFORE log-init for print-and-exit flags: safe to call before `install -m 0644`, so UX flags work without root."
  - "tee cleanup idiom: `TEE_PID=$!; trap 'exec >&- 2>&-; wait \"$TEE_PID\" 2>/dev/null || true' EXIT` — the RESEARCH.md Pitfall 6 `trap 'wait' EXIT` pattern is broken in practice; this one works."
  - "Glob-into-array: prefer `mapfile -t arr < <(compgen -G \"<glob>\" || true)` over `arr=( <glob> )` when the glob starts with a character class (shfmt 3.8.0 lexer bug)."

requirements-completed:
  - INST-01  # entrypoint is one-command non-interactive (root gate; flags only --help/-V/--verbose/--purge)
  - INST-02  # scaffolding — entrypoint itself is idempotent (no state mutations); provisioners it dispatches must be (guaranteed by `ensure_*` primitives landed in 02-01)
  - INST-05  # /var/log/agentlinux-install.log single greppable transcript created before tee + merged stdout+stderr

# Metrics
duration: ~18 min
completed: 2026-04-18
---

# Phase 2 Plan 02: Installer Entrypoint Rewrite Summary

**One file rewritten.** The Phase 1 stub at `plugin/bin/agentlinux-install` is replaced with a 194-line real entrypoint: `set -euo pipefail`, root check, CLI flag handling (--help/-h, --version/-V, --verbose, --purge stub), `/var/log/agentlinux-install.log` creation + tee of stdout+stderr, ERR + EXIT traps (with the Pitfall 6 deadlock fix documented by the plan's RESEARCH), four-library sourcing in the order Plan 02-01 locks (log → distro_detect → idempotency → as_user), and a lexical provisioner dispatch loop over `[0-9][0-9]-*.sh` that gracefully tolerates zero provisioners so sibling Wave 2 plans can land independently.

## Performance

- **Duration:** ~18 min
- **Tasks:** 1 (`type="auto"`); one commit.
- **Files modified:** 1 (`plugin/bin/agentlinux-install`, +192/-3)

## Accomplishments

- **Entrypoint body replaced (194 lines, 5→194).** Target was ~100 lines; the final file exceeds because the comment density is load-bearing (in-source rationale for pre-parse ordering, tee-deadlock fix, shfmt workaround, SC2155 split) and because of the added `pre_parse_args` stage that the plan skeleton omitted.
- **All six acceptance-criterion flag paths verified manually:**
  - `--help` / `-h` → exit 0, prints usage, works without sudo (pre-parse).
  - `--version` / `-V` → exit 0, prints `0.3.0`, works without sudo.
  - `--purge` → exit 0, prints Phase 4 stub warning, works without sudo.
  - `--verbose` → sets `AGENTLINUX_LOG_LEVEL=DEBUG`, continues through main path.
  - `--not-a-real-flag` → exit 64, `unknown argument:` + usage on stderr (captured in tee).
  - no-args-as-non-root → exit 64, "cannot create ... (are you root?)" on stderr.
- **Tee-deadlock fixed.** Discovered during local testing that the plan's RESEARCH.md Pitfall 6 mitigation (`trap 'wait' EXIT`) deadlocks in practice. Investigated, root-caused (EXIT trap runs before bash drops caller's FDs), and documented the correct idiom: `trap 'exec >&- 2>&-; wait "$TEE_PID" 2>/dev/null || true' EXIT`. The root-sim happy-path test (AGENTLINUX_LOG=<tmp> AGENTLINUX_SKIP_DISTRO_CHECK=1) now exits cleanly with the full log flushed.
- **Provisioner dispatch tolerant to zero provisioners.** Sibling plans 02-03 and 02-04 land `[0-9][0-9]-*.sh` scripts independently; the zero-provisioner case logs a WARN ("no provisioner scripts found under /...") and returns 0 so this plan's acceptance can be verified end-to-end without blocking on 02-03/04.
- **Shellcheck + shfmt + bash -n all clean.** Zero warnings at `--severity=warning --external-sources`; zero diff on `-i 2 -ci -bn`; syntax valid.
- **Phase 1 harness unbroken.** `bash tests/harness/run.sh` still reports 104/104 @tests passing.

## Task Commits

1. **Task 1: Replace stub with real installer entrypoint** — `44208a3` (feat)

Subsequent plan-metadata commit (this SUMMARY + STATE.md + ROADMAP.md) follows as a single `docs(02-02)` commit.

## Files Created/Modified

### Created

None.

### Modified

| File | Lines | Role |
|------|-------|------|
| `plugin/bin/agentlinux-install` | 5 → 194 | Real entrypoint: pre-parse UX flags, log-file init, tee, ERR/EXIT traps, arg parsing, root check, distro detect, provisioner dispatch |

## Decisions Made

1. **Pre-parse fast-exit for --help/--version/--purge** added BEFORE log-file init. Plan skeleton put log-init before parse_args, which meant a non-root operator typing `agentlinux-install --help` saw `cannot create /var/log/... (are you root?)` and exit 64 — violating the CONTEXT UX lock and the plan's own acceptance criterion (line 311: "`bash plugin/bin/agentlinux-install --help` exits 0"). The three fast-exit flags are all print-and-exit (mutate no state), so running without root is correct. --verbose and unknown-flag diagnostics still route through tee after log-init.
2. **Tee-deadlock fix.** Plan's Pitfall 6 mitigation is `trap 'wait' EXIT`. In practice this deadlocks — the EXIT trap runs before bash drops FD 1/2, so tee never sees EOF on its stdin. Correct idiom: close FD 1+2 in the trap, then `wait` on the saved `TEE_PID`. Verified: installer exits cleanly, log file has full transcript including the final line. Full rationale in the file's inline comment (lines 86-91) and in Decisions above.
3. **compgen -G for the provisioner glob.** Plan's `steps=("$PROV_DIR"/[0-9][0-9]-*.sh)` form fails shfmt 3.8.0's lexer (it misparses `[0-9][0-9]` as an array subscript: `"[x]" must be followed by =`). The `mapfile -t ... < <(compgen -G "...")` form delegates glob expansion to bash's builtin, which takes the pattern as a string — no lexer trip, same behavior, same lexical ordering. Documented in-source.
4. **SC2155 split.** `readonly X="$(cmdsub)"` is SC2155 — the `readonly` wrapper masks cmdsub exit codes. Split into two lines so a failing `$(cd "$BIN_DIR/../lib" && pwd)` trips `set -e` properly.
5. **install -m 0644 for log-file init kept.** A7 in RESEARCH.md flagged symlink-follow as MEDIUM-risk on paranoid multi-tenant hosts; plan's T-02-06 disposition is `accept` (root installer on clean Ubuntu). In-source comment at lines 74-76 names the trade-off so Phase 3+ callers cannot miss it when they start routing secrets through the log.
6. **Defensive redundant branches in parse_args.** Even though pre_parse_args handles -h/-V/--purge, parse_args retains those case-arms. Cost: three unreachable lines. Benefit: parse_args reads as a self-contained argv handler; future refactor that rewires the parse order cannot accidentally break UX.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Plan skeleton log-file init ordering breaks --help/--version/--purge UX**

- **Found during:** Task 1 verification (`bash plugin/bin/agentlinux-install --help` as non-root returned exit 64, not 0).
- **Issue:** Plan skeleton (PLAN lines 162-172) placed `install -m 0644 /dev/null "$LOG_FILE"` before `parse_args` runs. Non-root invocation of `--help` therefore trips the root-required log-init fallback with exit 64 — violating CONTEXT's "Installer UX & Logging" decision (fail fast on non-root WITH a clear error; but print-and-exit flags must work without sudo) and the plan's own acceptance criterion (line 311).
- **Why it's a real issue, not a style nit:** Plan's line 285 explicitly says "parse_args runs BEFORE require_root so --help / --version work without sudo." But the skeleton has `install -m 0644` — which also requires root — running before parse_args, so parse_args never reaches the help/version/purge arms on a non-root invocation. The fix restores the plan's stated UX contract.
- **Fix:** Added `pre_parse_args` (lines 40-68) that walks argv BEFORE log-file init and fast-exits for -h/--help, -V/--version, --purge. These three flags mutate no state, so running without root is correct. --verbose (which sets an env var and continues) and unknown flags still fall through to the post-log-init `parse_args` so their diagnostics go through the tee transcript.
- **Files modified:** `plugin/bin/agentlinux-install` (added pre_parse_args block; original `parse_args` retained for --verbose + unknown-flag rejection).
- **Verification:** All six acceptance-criterion flag paths pass; see "Accomplishments" above.
- **Committed in:** `44208a3` (initial entrypoint commit).

**2. [Rule 1 — Bug] `trap 'wait' EXIT` deadlocks in practice**

- **Found during:** Task 1 verification (first root-sim run with `AGENTLINUX_LOG=<tmp> AGENTLINUX_SKIP_DISTRO_CHECK=1` hung indefinitely after emitting `exit 64` from `require_root`).
- **Issue:** Plan's RESEARCH.md Pitfall 6 mitigation (line 699): "Add `trap 'wait' EXIT` to the entrypoint — waits for the tee child before exit." In practice bash runs the EXIT trap BEFORE closing the caller's FD 1/2. Tee's stdin is the other end of the `>()` pipe, so tee never sees EOF, `wait` blocks forever, installer hangs.
- **Why it's a real issue:** The plan's acceptance verify block has `( bash plugin/bin/agentlinux-install 2>&1; echo "EXIT=$?" ) | grep -qE ...` — a hang here would fail the verify step on a fresh run. On a real Docker invocation, the container would hang instead of exiting with diagnostic.
- **Fix:** `trap 'exec >&- 2>&-; wait "$TEE_PID" 2>/dev/null || true' EXIT` plus saving the tee subshell's PID via `$!` immediately after the `exec >` redirect. Closing FD 1+2 delivers EOF to tee; saving the specific PID avoids `wait` blocking on unrelated backgrounded children if any appear later. `|| true` keeps `set -e` from firing if tee already exited (racing).
- **Files modified:** `plugin/bin/agentlinux-install` (lines 92-95).
- **Verification:** Root-sim happy path now exits within <1s; log file has full transcript including the final log_info line.
- **Committed in:** `44208a3` (initial entrypoint commit).

**3. [Rule 3 — Blocking issue] shfmt 3.8.0 lexer misparses `arr=("$var"/[0-9][0-9]-*.sh)`**

- **Found during:** Task 1 verification (first `shfmt -d` run failed at line 115/117/123 with `"[x]" must be followed by =`).
- **Issue:** shfmt 3.8.0's lexer treats `[0-9]` immediately following a word (even inside a subscript-free array-literal assignment) as a malformed array-subscript. The plan skeleton uses exactly this form: `steps=("$PROV_DIR"/[0-9][0-9]-*.sh)`. Refactoring to `local pattern="$PROV_DIR/[0-9][0-9]-*.sh"; steps=($pattern)` worked but required SC2206 disable, which was stylistically poor.
- **Why it's a real issue:** Plan acceptance criterion: `shfmt -i 2 -ci -bn -d plugin/bin/agentlinux-install` exits 0 (no diff). Required for pre-commit to green on push.
- **Fix:** Use `mapfile -t steps < <(compgen -G "$PROV_DIR/[0-9][0-9]-*.sh" || true)`. compgen is a bash builtin that takes the glob as a string arg (no lexer trip), returns lexical matches on stdout. `mapfile -t` populates the array safely. `|| true` sidesteps compgen's exit 1 on no-match so `set -e` doesn't fire.
- **Files modified:** `plugin/bin/agentlinux-install` (lines 164-183).
- **Verification:** `shfmt -d` exits 0; `mapfile -t steps < <(compgen -G "/nonexistent/[0-9][0-9]-*.sh" || true); echo ${#steps[@]}` → `0` (no-match case).
- **Committed in:** `44208a3`.

**4. [Rule 1 — Bug] SC2155 `readonly X="$(cmdsub)"` masks cmdsub exit code**

- **Found during:** Task 1 verification (shellcheck `--severity=warning` flagged SC2155 on lines 13-15 of first draft).
- **Issue:** `readonly BIN_DIR="$(cd ... && pwd)"` returns 0 even if the cmdsub fails (e.g. `cd` to a path that doesn't exist under some pathological install). SC2155 at severity=warning fails shellcheck → fails plan acceptance criterion.
- **Why it's a real issue:** `set -e` relies on the builtin's exit code; `readonly` masking hides a legitimate cmdsub failure.
- **Fix:** Split into `BIN_DIR="$(...)"; readonly BIN_DIR`. Now a failing cmdsub trips `set -e`. Applied to BIN_DIR / LIB_DIR / PROV_DIR.
- **Files modified:** `plugin/bin/agentlinux-install` (lines 13-21).
- **Verification:** shellcheck green.
- **Committed in:** `44208a3`.

---

**Total deviations:** 4 auto-fixed. All four are Rule 1 (bug in plan skeleton or plan RESEARCH) or Rule 3 (toolchain blocking issue — shfmt 3.8.0). None are architectural; none required stopping for a checkpoint. Function surface (pre_parse_args + parse_args + require_root + run_provisioners + main) is a superset of the plan's spec (the plan's skeleton had only parse_args + require_root + main + inline provisioner loop; pre_parse_args is the correctness fix).

## Issues Encountered

- **`pre-commit` not installed on the executor host.** Same as Plan 02-01; expected. Ran `shellcheck 0.9.0` + `shfmt 3.8.0` directly with the exact args from `.pre-commit-config.yaml`. Both green. CI will re-run the full pre-commit stack on push.
- **First implementation of the tee trap deadlocked.** Surfaced in the root-sim verification run, not in the `--help`/`--version` flag tests. See Deviations §2 for the fix. No wider impact — the deadlock would have been immediately caught by Plan 02-05's bats tests if it had survived.

## Review Loop

**Dispatch scope (per `.claude/skills/review/SKILL.md`):** Changed file is `plugin/bin/agentlinux-install` (bash, under `plugin/bin/`). Reviewer set: `bash-engineer`, `security-engineer`, `qa-engineer`.

Rubrics applied (copy-of-truth from `docs/HARNESS.md` §4.2 and the subagent rubric files in `.claude/agents/`).

### bash-engineer findings

| Finding | Action |
|---------|--------|
| shellcheck --severity=warning --external-sources — clean, 0 findings after the SC2155 split (Deviation §4 committed in 44208a3) | PASS |
| `set -euo pipefail` at line 9 | PASS |
| Quoting discipline: all `$VAR` and `$(cmdsub)` forms properly quoted (BIN_DIR, LIB_DIR, PROV_DIR, LOG_FILE, TEE_PID, step, arg) | PASS |
| `trap on_error ERR` + `trap '...' EXIT` both installed | PASS |
| `sync 2>/dev/null \|\| true` inside on_error — `sync` returns 0 on Linux so `\|\| true` is redundant | Skip — the comment documents the read-only /proc defensive case; cost is one char of surplus, benefit is idiom-consistency with "always `\|\| true` when failure is acceptable" |
| `compgen -G` + `mapfile -t` pattern for the glob (Deviation §3) — prefer over `arr=(<glob>)` to sidestep shfmt lexer bug; functionally equivalent lexical ordering | PASS (documented in-source) |
| `parse_args` has unreachable -h/-V/--purge branches after pre_parse_args handles them | Skip — documented as defensive fallthrough in lines 125-127 |
| No `useradd`, `echo >>`, or `sudo npm install -g` anywhere in the entrypoint (state mutation is delegated to provisioners + lib primitives) | PASS |

### security-engineer findings

| Finding | Action |
|---------|--------|
| Log file created mode 0644 via `install -m 0644 /dev/null` before tee — `install` follows symlinks | Accept per T-02-06 plan disposition (root installer on clean Ubuntu); commented in-source at lines 74-76; Phase 3+ revisit when log content becomes secret-adjacent |
| `unknown argument: $1` log-error echoes user-supplied argv into the root-owned 0644 log | Accept per T-02-01 (caller discipline; no flag in Phase 2 takes secrets); future Phase 3+ flags that take secrets MUST route diagnostics through `log_debug` (env-gated), not `log_info` |
| No `eval`, no `xargs -I {}`, no unquoted cmdsub word-split | PASS |
| `require_root` fails fast with exit 64 before ANY state mutation (T-02-04 DoS mitigation) | PASS |
| `install -m 0644` is the only filesystem write in Phase 2 scope; no sudoers drop-in (per plan "Phase 2 ships no drop-in"; `visudo_validate` helper is available for Phase 3+ callers but not called here) | PASS |
| Tee deadlock fix uses `wait "$TEE_PID"` (specific PID) instead of bare `wait` — avoids accidentally waiting on unrelated backgrounded children | PASS (hardening over the RESEARCH pattern) |
| `exec >&- 2>&-` closes FDs before `wait` — correct idiom for flushing tee; not a security issue but prevents log truncation, which in turn prevents INST-05 false negatives | PASS |

### qa-engineer findings

| Finding | Action |
|---------|--------|
| Acceptance verify block (PLAN §verify/automated) — all six checks pass | PASS |
| Edge case: `/var/log/` missing on minimal containers → `install -m 0644` fails with confusing "are you root?" error | Skip — `/var/log/` always exists on Ubuntu (systemd + apt require it); if Plan 02-05 Docker bats catches this on a stripped image, fix then |
| Edge case: `--verbose` position-sensitive (rejected if preceded by unknown flag) | Skip — correct UX (fail fast on unknown); standard CLI behavior |
| No bats tests for the entrypoint in this plan | Skip — plan scope explicitly defers test coverage to Plan 02-05 ("Docker bats harness + bats helpers + INST/BHV/DOC test suite + CI matrix wire-up") |
| Re-run idempotency: the entrypoint itself is stateless (no mutations), so re-runs converge trivially; provisioners it dispatches carry the idempotency guarantee via ensure_* primitives (Plan 02-01) | PASS (plan scope) |

### Iteration outcome

**One iteration.** No actionable findings produced new fix commits. All three reviewers' remaining comments are either:
- already documented in-source or in this SUMMARY's Decisions,
- accepted per plan threat-model disposition (T-02-01 / T-02-06),
- or deferred to Plan 02-05 bats tests by plan scope.

Re-reviewing post-44208a3 against the same rubrics produced no new findings — the file's shape is stable.

## Acceptance Criteria

All checkboxes from the prompt's `<success_criteria>` block:

- [x] All tasks in 02-02-PLAN.md executed (Task 1: entrypoint rewrite)
- [x] `plugin/bin/agentlinux-install` passes `shellcheck --severity=warning --shell=bash --external-sources` and `shfmt -i 2 -ci -bn -d` (both exit 0)
- [x] Root check fails fast with clear error when EUID != 0 (no auto-sudo) — `require_root` function, exit 64 with `log_error "... must run as root (EUID != 0). Re-run under sudo."`
- [x] Both stdout and stderr tee'd to `/var/log/agentlinux-install.log` with timestamps — `exec > >(tee -a "$LOG_FILE") 2>&1`; log.sh prepends ISO-8601 `$(date -u +%Y-%m-%dT%H:%M:%SZ)` timestamps
- [x] Top-level `trap ERR` prints failure banner with failing step and log path — `on_error` function logs `installer failed at <src>:<line> (exit <code>)` + `full transcript: <path>`
- [x] Flags wired: `--help`, `--version`, `--purge` (stub warning), `--verbose` (DEBUG level) — all verified via manual invocation (see Accomplishments)
- [x] Provisioner dispatch sources `plugin/provisioner/[0-9][0-9]-*.sh` in lexical order; tolerates zero provisioners with log_warn (not log_error) — verified with empty provisioner dir, emits warning and exits 0
- [x] Sources lib files in dependency order: log → distro_detect → idempotency → as_user — lines 100, 115, 117, 119
- [x] `bash -n plugin/bin/agentlinux-install` exits 0
- [x] Review loop completed (bash-engineer + security-engineer + qa-engineer) — one iteration, no fixes applied
- [x] `bash tests/harness/run.sh` still exits 0 — 104/104 @tests passing, no regression
- [x] SUMMARY.md at `.planning/phases/02-installer-foundation-agent-user/02-02-SUMMARY.md` with tasks, commits, review outcome, acceptance checkboxes
- [x] STATE.md + ROADMAP.md updated — performed in the follow-up `docs(02-02)` commit

## Surprises for Wave 2 / Wave 3

- **None structurally.** Entrypoint lands clean; function surface is a superset of plan (pre_parse_args added). Sibling plans 02-03 (agent-user provisioner) and 02-04 (PATH wiring) can land provisioners in any order — `run_provisioners` tolerates zero matches and dispatches in lexical order.
- **Heads-up for 02-05 (Docker bats harness):** the tee trap fix (Deviation §2) is load-bearing. If Plan 02-05's bats suite ever changes the entrypoint's trap wiring, it MUST preserve `exec >&- 2>&-; wait "$TEE_PID"` — a bare `trap wait EXIT` will hang the bats `run` call and the CI job will time out rather than fail cleanly. Documented in-source (lines 86-91).
- **Heads-up for 02-03 and 02-04:** When sourcing under this entrypoint, provisioners inherit `set -euo pipefail`, the ERR trap, and the tee redirect. Any `|| true` inside a provisioner must be deliberate (not a habit). Any `exit` (as opposed to `return`) ends the entire installer.
- **Heads-up for Phase 3+:** If a future flag takes a secret (unlikely — auth for agent-side tools belongs after privilege-drop to the agent user), the diagnostic path `log_error "unknown argument: $1"` + usage echo could leak it to the 0644 log. Either switch the diagnostic to `log_debug` (env-gated) or scrub the argv before logging. Flagged in security-engineer review above.
- **Heads-up for Phase 6 (curl-installer):** The curl-installer must call `agentlinux-install` via absolute path after tarball extract; rely on the `BIN_DIR="$(cd ... && pwd)"` normalization to resolve LIB_DIR and PROV_DIR from any extracted root.

## Next Phase Readiness

- **Ready:** Wave 2 plans 02-03 (agent-user provisioner) and 02-04 (PATH wiring) unblocked. Both will land `[0-9][0-9]-*.sh` files under `plugin/provisioner/`; the entrypoint will dispatch them in lexical order with strict mode + ERR trap + tee all inherited.
- **No blockers.** Phase 1 harness meta-tests unbroken (104/104). shellcheck + shfmt + bash -n all green on the entrypoint.

## Self-Check

- `plugin/bin/agentlinux-install` — FOUND, 194 lines, shellcheck + shfmt clean
- Commit `44208a3` — FOUND in `git log`
- `.planning/phases/02-installer-foundation-agent-user/02-02-SUMMARY.md` — FOUND (this file)
- Phase 1 harness: 104/104 @tests still passing

## Self-Check: PASSED

---
*Phase: 02-installer-foundation-agent-user*
*Plan: 02-02*
*Completed: 2026-04-18*
