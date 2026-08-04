---
phase: 02-installer-foundation-agent-user
plan: 03
subsystem: infra
tags:
  - bash
  - provisioner
  - agent-user
  - locale
  - doc-02
  - idempotency

# Dependency graph
requires:
  - phase: 02-installer-foundation-agent-user (Plan 02-01)
    provides: plugin/lib/log.sh (log_info / log_warn / log_error) + plugin/lib/idempotency.sh (ensure_user / ensure_dir / ensure_marker_block)
  - phase: 02-installer-foundation-agent-user (Plan 02-02)
    provides: plugin/bin/agentlinux-install entrypoint that sources plugin/lib/*.sh in order and dispatches plugin/provisioner/[0-9][0-9]-*.sh lexically
provides:
  - plugin/provisioner/10-agent-user.sh (first dispatched provisioner — agent user creation, C.UTF-8 locale enforcement, DOC-02 CLAUDE.md placement)
affects:
  - 02-04 (PATH-wiring provisioner 40-path-wiring.sh — landing in parallel; relies on the agent user existing)
  - 02-05 (Docker bats harness — BHV-01 asserts agent user properties after the installer runs; DOC-02 asserts CLAUDE.md content)
  - 03-XX (Node.js + npm prefix — every `npm install -g` must run as the `agent` user this provisioner creates)
  - 04-XX / 05-XX (registry CLI, agent tools — run under the agent identity established here)

# Tech tracking
tech-stack:
  added: []  # Pure bash + standard Ubuntu primitives (useradd via ensure_user, locale-gen, update-locale, apt-get). No new tools.
  patterns:
    - "Provisioner-as-sourced-fragment (no shebang-exec; no local set -euo pipefail; strict mode inherited from entrypoint)"
    - "`return 1` (not `exit 1`) on error so the entrypoint ERR trap fires with proper src:line attribution"
    - "Locale verify-not-trust: locale-gen may no-op on glibc 2.35+ built-in C.UTF-8; correctness check is `locale -a | grep -Eiq '^c\\.utf-?8$'` not locale-gen exit code"
    - "Marker-block --top for DO-NOT guidance — ensures agent tooling reading CLAUDE.md hits anti-patterns before any user-added sections"
    - "Chmod + chown after ensure_marker_block to re-assert agent:agent ownership (ensure_marker_block writes root:root via install -m 0644)"
    - "DOC-02 body as grep-verifiable contract — bats tests in Plan 02-05 grep for `usr/local/bin`, `sudo npm install -g`, `second Node(.js)? install`"

key-files:
  created:
    - plugin/provisioner/10-agent-user.sh
  modified: []  # Pure add. Entrypoint (02-02) auto-discovers the new provisioner via compgen -G glob.

key-decisions:
  - "Locale folded into 10-agent-user.sh rather than split into a sibling 20-locale.sh (RESEARCH latitude `20-locale.sh OR folded into 10-`). Locale is ~10 lines, tied to user identity, and folding keeps the Phase 2 provisioner count minimal (10/40 instead of 10/20/40)."
  - "`return 1` (not `exit 1`) on locale verify failure — this file is sourced by the entrypoint, so `return 1` trips the parent's `set -euo pipefail` and triggers `on_error` ERR trap with proper src:line attribution. `exit 1` would kill the entrypoint immediately and bypass the structured-logging failure banner."
  - "Locale outcome regex `^c\\.utf-?8$` with `-i` — accepts both `C.UTF-8` (documentation canonical) and `C.utf8` (the form Ubuntu 24.04 reports via `locale -a`). Matches RESEARCH Pitfall 5 verification pattern."
  - "ensure_marker_block --top placement (not default --bottom) — anti-pattern DO-NOT guidance MUST appear before any user-added sections so agent tooling reading CLAUDE.md encounters the warnings first."
  - "Stable marker tag `agentlinux-doc-02` — Phase 4/5 may extend this block with new anti-patterns but MUST reuse this exact tag. Renaming would break idempotency across versions."
  - "No raw state mutation in this file (no useradd / install -d / echo >> / sed -i). Every mutation routes through plugin/lib/idempotency.sh primitives. Verified by `grep -En 'useradd|install -d|echo .*>>|sed -i' | grep -v '^[0-9]*:[[:space:]]*#'` returning empty."

patterns-established:
  - "Provisioner file header contract: `#!/usr/bin/env bash` shebang (for editor syntax + shellcheck), block comment naming the sourced-by parent + inherited strict mode + requirement IDs satisfied, one-line `log_info` at entry and exit for greppable transcript boundaries"
  - "Documented `|| true` skip-path convention: the one allowed use of `|| true` in a provisioner MUST have a preceding comment explaining why the failure is benign AND MUST be followed by an explicit outcome-verify check (`locale -a | grep` in this case)"
  - "DOC-02 heredoc-column-0 rule: the heredoc body MUST start at column 0 (no leading spaces in the `<<'TAG'` source, and no indentation under `ensure_marker_block`) so the marker-block content is literal markdown, not indented-and-offset"

requirements-completed:
  - BHV-01
  - DOC-02

# Metrics
duration: ~3 min
completed: 2026-04-18
---

# Phase 2 Plan 03: Agent-User Provisioner + DOC-02 CLAUDE.md Summary

**One provisioner file (`plugin/provisioner/10-agent-user.sh`, 136 lines) that creates the agent user, enforces system-wide C.UTF-8 locale, and places `/home/agent/CLAUDE.md` with the DOC-02 anti-pattern block via `ensure_marker_block --top` so user edits outside the block survive re-runs.**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-04-18T14:46:15Z
- **Completed:** 2026-04-18T14:48:59Z
- **Tasks:** 1 (`type="auto"`)
- **Files created:** 1 (provisioner), 136 lines

## Accomplishments

- **`plugin/provisioner/10-agent-user.sh` (136 lines)** — First provisioner dispatched by the installer entrypoint (02-02's `run_provisioners` via `compgen -G "$PROV_DIR/[0-9][0-9]-*.sh"`). Three steps:
  1. **Step 1 — agent user (BHV-01):** `ensure_user agent` (useradd only if absent; bash shell, /home/agent home, matching user-group) + `ensure_dir /home/agent 0755 agent:agent` (asserts mode/ownership unconditionally on re-run to correct any out-of-band drift).
  2. **Step 2 — C.UTF-8 locale (BHV-01):** `command -v locale-gen` guard + `apt-get install -y --no-install-recommends locales` fallback for Docker slim images → `locale-gen C.UTF-8 ... || true` (documented skip-path; glibc built-in makes locale-gen a no-op on 22.04+) → `update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8` (writes `/etc/default/locale`) → outcome verify via `locale -a | grep -Eiq '^c\.utf-?8$'` with `return 1` on failure (trips entrypoint ERR trap).
  3. **Step 3 — DOC-02 CLAUDE.md:** `ensure_marker_block /home/agent/CLAUDE.md "agentlinux-doc-02" --top` with heredoc body containing all three canonical anti-pattern strings → `chmod 0644` + `chown agent:agent` (re-assert agent ownership since ensure_marker_block writes root-owned via `install -m 0644`).

- **DOC-02 body contains all three canonical anti-pattern strings** (grep-verifiable for Plan 02-05 bats tests):
  - `usr/local/bin` — in "No wrapper shims under `/usr/local/bin/`" bullet
  - `sudo npm install -g` — in "No `sudo npm install -g`" bullet
  - `second Node.js install` — in "No second Node.js install (nvm, fnm, volta, manual tarball)" bullet

- **Zero raw state mutation.** Every filesystem / user change routes through `plugin/lib/idempotency.sh` primitives (`ensure_user`, `ensure_dir`, `ensure_marker_block`). `chmod` and `chown` appear only in the post-ensure_marker_block ownership re-assertion — these are metadata calls, not state-introducing mutations, and are idempotent by definition.

- **Marker-block round-trip byte-stable.** Tmp-dir smoke test (documented under Acceptance Criteria below) verified: running `ensure_marker_block` twice with identical body produces a zero-byte `diff` between run-1 and run-2 outputs, and user content BOTH before AND after the marker block survives verbatim.

## Task Commits

Each task landed as a single `--no-gpg-sign` commit.

1. **Task 1: Create `plugin/provisioner/10-agent-user.sh`** — `7bfa20d` (feat)

**Plan metadata (this SUMMARY + STATE.md + ROADMAP.md + REQUIREMENTS.md):** committed after this file is written (see plan-metadata commit hash in final `git log`).

## Files Created/Modified

### Created

| File | Lines | Role |
|------|-------|------|
| `plugin/provisioner/10-agent-user.sh` | 136 | Agent user creation + C.UTF-8 locale + DOC-02 CLAUDE.md placement |

### Modified

None. Pure add — the entrypoint (02-02) auto-discovers this new provisioner via `compgen -G "$PROV_DIR/[0-9][0-9]-*.sh"` lexical sort; no caller edit required.

## Decisions Made

1. **Locale folded into 10-agent-user.sh.** RESEARCH explicitly offered the split-vs-fold choice (`20-locale.sh OR folded into 10-`). Folded because: (a) locale enforcement is ~10 lines including verify, (b) it is tied to the agent-user identity it runs alongside, and (c) Phase 2 has just three numbered provisioners total (10, 40, and none in between) — adding a 20- just for locale would bloat the count for no benefit. Documented in the provisioner's header comment so the decision is visible at the file.

2. **`return 1` (not `exit 1`) on locale failure.** Sourced fragments (this file is `. "$step"`-sourced by the entrypoint's `run_provisioners`) must use `return` for failures. `exit 1` inside a sourced file kills the parent entrypoint immediately — bypassing the structured-logging `on_error` ERR trap and losing the `src:line` attribution the operator needs to diagnose. `return 1` trips the parent's `set -euo pipefail`, which fires the ERR trap with proper line numbers.

3. **Locale outcome regex `^c\.utf-?8$` with `-i`.** Ubuntu 24.04's `locale -a` reports `C.utf8` (lowercase, no dot+dash+digit), while RESEARCH describes the locale as `C.UTF-8`. Case-insensitive with an optional `-` matches both forms and matches RESEARCH Pitfall 5's prescribed verification regex verbatim.

4. **`ensure_marker_block --top` placement.** Default is `--bottom` (tag documented in 02-01 lib conventions). `--top` chosen deliberately because DOC-02 is anti-pattern guidance — any agent tool reading this CLAUDE.md before deciding how to install itself MUST encounter the DO-NOT list before any user-added sections. Top placement survives re-runs because ensure_marker_block's awk-strip step is placement-agnostic (the block is always re-emitted at the configured placement).

5. **Stable marker tag `agentlinux-doc-02`.** Phase 4/5 may extend this block with new anti-patterns (e.g., per-catalog-agent warnings) but MUST reuse the `agentlinux-doc-02` tag — renaming would cause the new phase's block to co-exist with the orphaned old block, breaking idempotency. Documented in the provisioner's Step 3 comment.

6. **No raw state mutation.** Per plan's verification regex `grep -En 'useradd|install -d|echo .*>>|sed -i' ... | grep -v '^[0-9]*:[[:space:]]*#'` must return empty. Verified: returns empty. chmod and chown are metadata-only, idempotent, and not state mutations in the "introduces new content" sense; the verification regex deliberately does not flag them.

## Deviations from Plan

**None — plan executed exactly as written.**

The plan skeleton was implementable verbatim; the only delta between the skeleton and the final file is cosmetic (column-0 heredoc start vs the markdown-code-block indentation shown in the plan body — this is a literal-heredoc vs indented-plan-rendering artifact, not a semantic change). No Rule 1/2/3 auto-fixes were needed; no Rule 4 architectural choices surfaced.

The plan's acceptance criteria ALL passed on first implementation pass:

- shellcheck clean
- shfmt clean
- bash -n clean
- 7 required grep patterns all match
- Zero raw state mutation
- Marker-block round-trip byte-stable
- Phase 1 harness still 104/104

## Issues Encountered

- **`.mcp.json` and `.planning/notes/` appear as untracked in `git status`.** Pre-existing (present at plan start per the initial git status in the executor prompt). Not created by this plan; intentionally left untouched.
- **`pre-commit` not installed on the executor host.** Same posture as Plans 02-01 and 02-02. Ran `shellcheck --severity=warning --shell=bash --external-sources --source-path=plugin/lib` and `shfmt -i 2 -ci -bn -d` with the exact args from `.pre-commit-config.yaml` — both clean. CI will re-run the full pre-commit stack on push.

## Review Loop

**Dispatch scope (per `.claude/skills/review/SKILL.md` dispatch table):** Changed files match `^plugin/(bin|lib|provisioner)/.+\.sh$` → spawn bash-engineer + security-engineer + qa-engineer.

**Invocation mechanism:** Task tool is unavailable under this agent's `tools:` frontmatter restriction (upstream anthropics/claude-code#13898 strips parallel-subagent dispatch). Applied each reviewer's rubric inline per HARNESS.md §4 operational convention — main agent owns triage regardless of whether subagent dispatch is parallel or serial.

### bash-engineer findings

| Finding | Action |
|---------|--------|
| Quoting: every variable in string context quoted; no unquoted globs; no word-splitting traps | PASS |
| Idempotency: all state mutation routes through `ensure_*` from lib; chmod/chown are metadata-idempotent | PASS |
| Strict mode inheritance: no local `set -euo pipefail` (inherited from entrypoint per 02-01 SUMMARY's locked source-order + strict-mode-inheritance contract) | PASS |
| `return 1` not `exit 1` on locale failure — correct for sourced fragment | PASS |
| Single `|| true` skip-path (locale-gen line 52) with explicit "documented skip-path" comment and outcome-verify check directly below | PASS |
| Heredoc column-0 start — no leading whitespace leaks into marker block body | PASS (round-trip smoke confirms) |
| shellcheck --severity=warning --external-sources --source-path=plugin/lib: clean | PASS |
| shfmt -i 2 -ci -bn -d: no diff | PASS |

### security-engineer findings

| Finding | Action |
|---------|--------|
| T-02-05 (ensure_user re-run with different shell) — `ensure_user` is a no-op when user exists; no usermod -s; existing human's agent user with a non-bash shell is not modified, BHV-01 test fails loudly (correct failure mode, not silent hijack) | PASS |
| T-02-07 (CLAUDE.md overwrite on re-run) — `ensure_marker_block --top` + round-trip smoke proved byte-stable second run + user preamble + appendix preservation | PASS |
| T-02-08 per prompt (PATH ordering) — out of scope for this provisioner; PATH wiring is Plan 02-04's `40-path-wiring.sh`. This file does not write PATH. | OUT OF SCOPE |
| T-02-08 per this plan's threat register (CLAUDE.md readability 0644) — accepted; file is policy guidance, no secrets, world-read is the point (non-agent agents discover the guidance too) | PASS (accepted per plan disposition) |
| apt-get install source: stock Ubuntu repo (`locales` package); no third-party source; DEBIAN_FRONTEND non-interactive | PASS |
| Ownership: root writes CLAUDE.md via ensure_marker_block's `install -m 0644`, then chmod/chown agent:agent — ends agent-owned, no root-owned file in agent $HOME | PASS |
| DOC-02 body contains `usr/local/bin`, `sudo npm install -g`, `second Node.js install` — all three canonical anti-pattern strings grep-verifiable | PASS |
| No secrets logged; no `env >> file`; no argv dump | PASS |
| Symlink attack surface on /home/agent: `ensure_dir` uses `install -d` on absent paths (refuses symlink) or chmod+chown on existing. If /home/agent is already a symlink to an attacker-controlled path, chmod/chown follows it. Mitigation: root provisioner on clean Ubuntu host is the trust model; multi-tenant hosts deferred to v0.4+. | ACCEPT (documented trust model) |

### qa-engineer findings

| Finding | Action |
|---------|--------|
| 22.04 vs 24.04 locale: regex `^c\.utf-?8$` `-i` matches `C.UTF-8` AND `C.utf8` (24.04 form) | PASS |
| Docker slim image (no `locales` pkg): `command -v locale-gen` guard + apt-get install fallback handles it | PASS |
| Re-run idempotency: all three ensure_* primitives are idempotent (ensure_user no-op, ensure_dir chmod+chown unconditional, ensure_marker_block awk-strip+rewrite); update-locale writes identical content = byte-stable | PASS |
| Concurrent two-installer runs | SKIP — operator error, not in Phase 2 scope |
| Bats coverage for this provisioner | DEFERRED — Plan 02-05 (Docker bats harness) lands BHV-01 + DOC-02 bats tests per plan's `<objective>` ("actual end-to-end 'installer runs in Docker' verification lands in Plan 05") |
| Locale availability if `locales` pkg install fails (apt hold, disk full, no network) | ACCEPT — surfaced as non-zero exit from `apt-get install`; set -e fires via entrypoint ERR trap with proper attribution |

### Iteration outcome

**One iteration.** All three rubrics return PASS or acknowledged out-of-scope / deferred. No actionable findings required a fix commit. No style-only comments remain.

## Acceptance Criteria

All checkboxes from the plan's `<success_criteria>` and executor prompt:

- [x] All tasks in 02-03-PLAN.md executed (1 task, `type="auto"`)
- [x] Per-task atomic commit via `git add <file> && git commit --no-gpg-sign` (`7bfa20d`)
- [x] `plugin/provisioner/10-agent-user.sh` passes `shellcheck --severity=warning --shell=bash --external-sources --source-path=plugin/lib`
- [x] Script inherits strict mode from entrypoint (no local `set -euo pipefail`)
- [x] Sources no libraries directly — inherits function surface from entrypoint (log_info, ensure_user, ensure_dir, ensure_marker_block)
- [x] Function-less script — no top-level function definitions; imperative fragment run on source
- [x] Agent user creation uses `ensure_user` from lib (idempotent — no error on re-run, no shell change surprise on existing `agent` user)
- [x] Agent user has bash shell (ensure_user uses `--shell /bin/bash`), real home (/home/agent via --create-home), UTF-8 locale via `update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8`
- [x] `/home/agent/CLAUDE.md` placed with explicit anti-pattern list containing ALL THREE strings: `usr/local/bin`, `sudo npm install -g`, `second Node.js install` (grep-verifiable; idempotent placement via marker-block)
- [x] File owned by agent user; permissions readable by agent (chown agent:agent + chmod 0644 after ensure_marker_block)
- [x] `grep -q 'ensure_user agent' plugin/provisioner/10-agent-user.sh` — succeeds
- [x] `grep -q 'ensure_dir /home/agent 0755 agent:agent' plugin/provisioner/10-agent-user.sh` — succeeds
- [x] `grep -q 'ensure_marker_block /home/agent/CLAUDE.md "agentlinux-doc-02" --top' plugin/provisioner/10-agent-user.sh` — succeeds
- [x] `grep -q 'update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8' plugin/provisioner/10-agent-user.sh` — succeeds
- [x] `grep -q 'usr/local/bin' plugin/provisioner/10-agent-user.sh` — succeeds
- [x] `grep -q 'sudo npm install -g' plugin/provisioner/10-agent-user.sh` — succeeds
- [x] `grep -qE 'second Node(\.js)? install' plugin/provisioner/10-agent-user.sh` — succeeds
- [x] No raw state-mutation: `grep -En 'useradd|install -d|echo .*>>|sed -i' ... | grep -v '^[0-9]*:[[:space:]]*#'` returns empty
- [x] `bash -n plugin/provisioner/10-agent-user.sh` exits 0 (syntax valid)
- [x] `shfmt -i 2 -ci -bn -d plugin/provisioner/10-agent-user.sh` exits 0 (no diff)
- [x] Marker-block round-trip sanity check: tmp-dir smoke test with log.sh + idempotency.sh sourced, ensure_marker_block called twice with identical body around user-added preamble + appendix → `diff run1 run2` empty, preamble + appendix preserved, block at top
- [x] Review loop: bash-engineer + security-engineer + qa-engineer rubrics applied inline; one iteration; no actionable findings
- [x] `bash tests/harness/run.sh` exits 0 (Phase 1 acceptance gate not regressed — 104/104)
- [x] Commit exists: `git log --oneline -1` includes `feat(02-03): add agent-user provisioner + DOC-02 CLAUDE.md` — `7bfa20d`

## Surprises / Heads-up for Wave 3

- **None structurally.** Provisioner lands clean on first implementation pass; no auto-fixes, no deferred items.
- **Heads-up for 02-04 (PATH wiring, running in parallel):** Your provisioner will run AFTER this one because bash lexical glob ordering places `10-agent-user.sh` before `40-path-wiring.sh`. You can assume the agent user exists, /home/agent is 0755 agent:agent, and C.UTF-8 is enforced when your script runs.
- **Heads-up for 02-05 (Docker bats harness):** BHV-01 assertions should run against all six invocation modes (bats helper `invoke_modes.bash`) AND assert: `getent passwd agent` returns a line ending `:/home/agent:/bin/bash`; `/etc/default/locale` contains `LANG=C.UTF-8`; `locale -a | grep -Eiq '^c\.utf-?8$'`. DOC-02 assertions: `test -O /home/agent/CLAUDE.md` (file exists) + `stat -c '%U:%G %a' /home/agent/CLAUDE.md` = `agent:agent 644` + three anti-pattern grep checks. Re-run idempotency bats (T-02-07 coverage): run the installer twice, diff `/home/agent/CLAUDE.md` — expect empty.
- **For Phase 3+ provisioners:** The `agent` user is now safe to assume. Every future `npm install -g` MUST go through `as_user agent -H -E -- npm install -g <pkg>` (keystone primitive from 02-01 `plugin/lib/as_user.sh`).

## Next Phase Readiness

- **Ready for Plan 02-04 (PATH wiring, parallel):** Agent user exists; home is 0755 agent:agent; locale enforced. PATH wiring depends on these three and they are all in place.
- **Ready for Plan 02-05 (Docker bats harness):** BHV-01 + DOC-02 both have observable artifacts (agent user entry, /etc/default/locale, /home/agent/CLAUDE.md) that bats tests can assert against. Re-run idempotency is verified at the shell-harness level; Phase 2-05 will verify at the Docker-end-to-end level.
- **No blockers.** Phase 1 harness meta-test suite unbroken (104/104). Wave 2 continues.

## Self-Check

Verified before finalizing this SUMMARY:

- Commit `7bfa20d` present in `git log`
- File `plugin/provisioner/10-agent-user.sh` exists and is 136 lines
- Commit hash `7bfa20d` corresponds to `feat(02-03): add agent-user provisioner + DOC-02 CLAUDE.md`
- `bash tests/harness/run.sh` exits 0 (104/104)

Automated self-check output:

- [x] `plugin/provisioner/10-agent-user.sh` — FOUND (136 lines)
- [x] `.planning/phases/02-installer-foundation-agent-user/02-03-SUMMARY.md` — FOUND
- [x] Commit `7bfa20d` — FOUND in `git log`
- [x] `bash tests/harness/run.sh` — exits 0 (104/104)

## Self-Check: PASSED

---
*Phase: 02-installer-foundation-agent-user*
*Plan: 02-03*
*Completed: 2026-04-18*
