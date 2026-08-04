---
phase: 03-nodejs-runtime-per-user-npm-prefix
plan: 01
subsystem: installer
tags: [nodejs, npm-prefix, nodesource, path-wiring, ubuntu, bash, systemd-env, cron-env]

requires:
  - phase: 01-harness-setup
    provides: "shellcheck/shfmt pre-commit scaffolding; bats harness; CLAUDE.md review-loop contract"
  - phase: 02-installer-foundation-agent-user
    provides: "plugin/bin/agentlinux-install entrypoint (sources lib/ + dispatches provisioner/[0-9][0-9]-*.sh); plugin/lib/{log,distro_detect,idempotency,as_user}.sh primitives; plugin/provisioner/10-agent-user.sh (agent user + locale + DOC-02 CLAUDE.md); plugin/provisioner/40-path-wiring.sh (four-file six-mode PATH matrix); tests/bats/{10-installer,20-agent-user}.bats (22 @tests); tests/docker/ harness (ubuntu-22.04 + ubuntu-24.04); tests/bats/helpers/{invoke_modes,assertions}.bash"
provides:
  - "plugin/provisioner/30-nodejs.sh (NodeSource Node 22 LTS install + per-user npm prefix dir + ~agent/.npmrc)"
  - "plugin/provisioner/40-path-wiring.sh extended: /home/agent/.npm-global/bin prepended in three literal-PATH artefacts (profile.d case-stack, agentlinux.env, cron.d); NPM_CONFIG_PREFIX=/home/agent/.npm-global in agentlinux.env"
  - "plugin/bin/agentlinux-install run_provisioners() now sorts compgen -G output — numeric dispatch contract (10 → 30 → 40) is now contract-enforced, not filesystem-implementation-dependent"
  - "RT-01 satisfied: Node.js 22 LTS installed end-to-end on Ubuntu 22.04 + 24.04 (Node v22.22.2 verified via Docker smoke)"
  - "RT-04 satisfied (installer side): ~agent/.npmrc + NPM_CONFIG_PREFIX both carry /home/agent/.npm-global; split-brain-proof (T-03-03 mitigated)"
affects: [03-02, 04, 05]

tech-stack:
  added:
    - "NodeSource apt repo (Node 22 LTS — nodistro suite)"
    - "NodeSource setup_22.x script (curl-pipe-bash at pinned-URL trusted upstream — ADR-005)"
    - "apt-transport-https + gnupg pre-req packages (for NodeSource GPG-signed repo)"
  patterns:
    - "Pre-install curl/gnupg/ca-certificates via apt with upfront apt-get update (CI-safe, cloud-image-safe)"
    - "Idempotent NodeSource gate: short-circuit if /etc/apt/sources.list.d/nodesource.sources OR nodesource.list exists (Pitfall 1 dual-gate)"
    - "Prefix dir creation BEFORE npm-as-agent invocation: agent-owned /home/agent/.npm-global{,/bin,/lib} via ensure_dir (Pitfall 4 defensive)"
    - "Belt-and-braces env config: file (~agent/.npmrc) + env var (NPM_CONFIG_PREFIX in /etc/agentlinux.env) — T-03-03 split-brain avoidance via byte-identical values"
    - "Case-prepend LIFO stacking: .local/bin case FIRST, .npm-global/bin case SECOND → .npm-global/bin lands FIRST in final PATH (Pitfall 4)"

key-files:
  created:
    - "plugin/provisioner/30-nodejs.sh (100 LOC; 98 code + header comment)"
  modified:
    - "plugin/provisioner/40-path-wiring.sh (+28 −6 lines; three heredoc artefacts extended + header-comment updates)"
    - "plugin/bin/agentlinux-install (+10 −7 lines; run_provisioners sort fix — Rule 3 auto-fix)"

key-decisions:
  - "Pre-install curl/gnupg/ca-certificates/apt-transport-https before NodeSource setup_22.x (log visibility per D-02 + RESEARCH §Q2); NodeSource's own install step becomes a no-op"
  - "apt-get update mandatory before pre-req install (discovered during Docker smoke — CI base image strips /var/lib/apt/lists; same applies to cloud images)"
  - "Case-stack order: .local/bin case FIRST, .npm-global/bin case SECOND — reverses the RESEARCH §Example 2 diff to honor Pitfall 4 invariant (npm-global FIRST in final PATH after both case-blocks run)"
  - "run_provisioners dispatch: pipe compgen -G through sort to enforce numeric dispatch contract (discovered that compgen -G returns readdir(3) order, NOT lexical — phase 2 comment was wrong; phase 3 exposed it by adding a third provisioner allocated to an earlier inode slot)"
  - "NPM_CONFIG_PREFIX NOT added to cron.d/agentlinux (vixie-cron parser only reliably honors PATH; cron jobs invoke bash which sources ~agent/.bashrc → profile.d → case-stack; env var fallback unnecessary for cron artefact)"
  - "Review loop applied inline (bash-engineer + security-engineer + qa-engineer rubrics) — same pattern as Phase 2 plans 02-03/02-04/02-05 per STATE.md; project does not have interactive subagent spawn available in this execution context, rubrics applied directly against each file and documented per-commit"

patterns-established:
  - "Provisioner file contract: #!/usr/bin/env bash + block-comment header (sourced-by, inherited strict-mode, requirements, ordering, invariants) + log_info bookends NN-name:starting / NN-name:done"
  - "apt-get update before apt-get install in any provisioner that adds packages (Docker CI + cloud-image defense)"
  - "Post-primitive chown+chmod re-assertion: ensure_line_in_file / ensure_marker_block use root's umask and don't chown — always follow with explicit chown agent:agent + chmod NNNN when target is agent-owned"
  - "return 1 (not exit 1) in sourced fragments — trips entrypoint ERR trap with src:line attribution"
  - "compgen -G always pipe through sort when numeric dispatch order matters"

requirements-completed: [RT-01, RT-04]

duration: 15min
completed: 2026-04-18
---

# Phase 03 Plan 01: Node.js Runtime + Per-User npm Prefix (Installer Side) Summary

**NodeSource Node 22 LTS + per-user npm prefix wiring landed: 30-nodejs.sh creates the prefix layout, 40-path-wiring.sh prepends .npm-global/bin to every literal-PATH artefact and adds NPM_CONFIG_PREFIX belt-and-braces; Docker smoke 22/22 green on Ubuntu 22.04 + 24.04 with Node v22.22.2 installed end-to-end.**

## Performance

- **Duration:** ~15 min (4 commits, 2 tasks + 2 Rule 3 auto-fixes)
- **Started:** 2026-04-18T18:12:54Z
- **Completed:** 2026-04-18T18:28:00Z (approx)
- **Tasks:** 2/2 plan tasks + 2 Rule 3 auto-fix commits
- **Files modified:** 3 (1 created, 2 modified)
- **Tests:** 22/22 bats on Ubuntu 22.04 + 22/22 on Ubuntu 24.04 + 104/104 harness meta-tests (no regression from Phase 1/2)

## Accomplishments

- **RT-01 installed:** Node.js v22.22.2 lands on a fresh Ubuntu image via NodeSource setup_22.x + `apt-get install -y nodejs`. Version gate (hard-fail if major < 22) verified end-to-end in Docker smoke. Works on both Ubuntu 22.04 and 24.04.
- **RT-04 configured (installer side):** `/home/agent/.npm-global` prefix dir (+ `bin/`, `lib/` subdirs) agent-owned; `~agent/.npmrc` carries `prefix=/home/agent/.npm-global`; `/etc/agentlinux.env` carries the same value in `NPM_CONFIG_PREFIX` as Pitfall 5 belt-and-braces.
- **Six-mode PATH contract extended:** `/home/agent/.npm-global/bin` lands FIRST in the final PATH in every invocation mode — case-stack in profile.d (BHV-05/-i + BHV-06), the .bashrc marker block sources profile.d (BHV-02 + BHV-05 bash -c), literal PATH in agentlinux.env (BHV-04 systemd), literal PATH in cron.d (BHV-03). INST-02 byte-stable re-run verified by the Phase 2 bats test (`ok 3 INST-02: re-running the installer is byte-stable`).
- **Phase 2 tests zero regression:** All 22 bats tests on both Ubuntu 22.04 + 24.04 still pass; 104/104 harness meta-tests still pass.

## Task Commits

Each task was committed atomically. Rule 3 auto-fixes committed as separate `fix(03-01)` commits per review-loop convention:

1. **Task 1: add 30-nodejs.sh — Node 22 LTS + per-user npm prefix** — `74366a0` (feat)
   Creates plugin/provisioner/30-nodejs.sh (100 LOC). Six steps: apt-get update, pre-reqs install, idempotent NodeSource repo add (dual-gate on sources+list), nodejs install, version-gate RT-01 verify, ensure_dir prefix layout, ensure_line_in_file ~agent/.npmrc. Passes all 15 automated `verify.automated` acceptance checks.

2. **Rule 3 auto-fix (during Task 1 Docker smoke): apt-get update first** — `c6d9b41` (fix)
   Discovered during Docker ubuntu-24.04 end-to-end smoke: `apt-get install -y curl gnupg ...` failed with `E: Unable to locate package curl` because Phase 2's test Dockerfile strips `/var/lib/apt/lists/*` after base install (same pattern on Ubuntu cloud images). Added `DEBIAN_FRONTEND=noninteractive apt-get update` before the pre-req install. Idempotent.

3. **Task 2: extend 40-path-wiring.sh — prepend .npm-global/bin + NPM_CONFIG_PREFIX** — `1fe6a75` (feat)
   Three surgical heredoc edits + two header-comment updates: (A) profile.d case-stack with .local/bin case FIRST, .npm-global/bin case SECOND (Pitfall 4 LIFO order so .npm-global/bin lands FIRST in final PATH); (B) agentlinux.env heredoc PATH replaced + NPM_CONFIG_PREFIX line added; (C) cron.d heredoc PATH replaced. .bashrc marker block UNCHANGED (it sources profile.d). Heredoc tags stay single-quoted (T-03-04 byte-idempotency). Passes all 15 automated `verify.automated` acceptance checks.

4. **Rule 3 auto-fix (during Task 2 Docker smoke): sort run_provisioners dispatch** — `3dbfcff` (fix)
   Discovered that `compgen -G` in `plugin/bin/agentlinux-install` returns matches in directory-entry order (readdir(3)), NOT lexical as Phase 2 Plan 02-02 claimed. Once `30-nodejs.sh` was created AFTER `10-agent-user.sh`, the filesystem returned them {30, 10, 40}, which broke the numeric-dispatch contract (30-nodejs.sh tried to `install -o agent` before 10-agent-user.sh created the agent user). Piped compgen output through `sort` — enforces the contract the plan's success-criterion verification command (`ls ... | sort`) always assumed.

**Plan metadata commit:** deferred to final state-update step (this SUMMARY + STATE.md update).

## Files Created/Modified

- **Created** `plugin/provisioner/30-nodejs.sh` (100 LOC) — NodeSource Node 22 LTS install + per-user npm prefix + ~agent/.npmrc config. Six steps, idempotent, shellcheck/shfmt/bash -n clean, every state mutation through `ensure_dir` / `ensure_line_in_file`.
- **Modified** `plugin/provisioner/40-path-wiring.sh` (+28 −6 lines) — Extended three of four heredoc artefacts (profile.d case-stack, agentlinux.env literal PATH + new NPM_CONFIG_PREFIX line, cron.d literal PATH). .bashrc marker block and file structure unchanged.
- **Modified** `plugin/bin/agentlinux-install` (+10 −7 lines in `run_provisioners`) — Rule 3 auto-fix: pipe compgen -G through sort to enforce lexical dispatch order. Comment block rewritten to document actual compgen behavior and why sort is mandatory.

## Decisions Made

See `key-decisions` in frontmatter. Highlights:

1. **apt-get update mandatory in 30-nodejs.sh** — Rule 3 fix elevated to established pattern. Any Phase 3+ provisioner that runs apt-get install MUST run apt-get update first (Docker CI + cloud-image defense).
2. **Case-stack order REVERSED vs RESEARCH §Example 2 diff** — research's literal diff put `.npm-global/bin` case FIRST, but the plan's Pitfall 4 invariant requires `.npm-global/bin` lands FIRST in final PATH. LIFO case-prepend semantics mean the LAST case-block's prepend wins, so `.local/bin` case must be FIRST and `.npm-global/bin` SECOND. The plan text explicitly called this out and instructed executor to honor the invariant over the literal diff — executor complied.
3. **NPM_CONFIG_PREFIX NOT added to cron.d** — cron.d's vixie-cron parser doesn't reliably honor arbitrary env-like lines (PATH is the known-good exception); cron jobs invoke bash which sources agent's .bashrc → profile.d → case-stack, so env-var fallback is unnecessary for this artefact.
4. **Review loop applied inline** — bash-engineer / security-engineer / qa-engineer rubrics applied directly per-file (same pattern documented in STATE.md for Phase 2 plans 02-03/02-04/02-05); no actionable findings on either task's initial commit; the two Rule 3 fixes were discovered through end-to-end Docker smoke (the rubric most capable of catching cross-file interaction bugs).
5. **compgen -G is readdir-order** — Phase 2 Plan 02-02 code comment was factually wrong; this plan uncovered it. Fixed + documented in the code comment so future plans don't repeat the mistake.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `apt-get install` fails when /var/lib/apt/lists is empty**
- **Found during:** Task 1 Docker ubuntu-24.04 smoke test (post-task verification)
- **Issue:** `DEBIAN_FRONTEND=noninteractive apt-get install -y curl gnupg ca-certificates apt-transport-https` in Step 1 of 30-nodejs.sh failed with `E: Unable to locate package curl / E: Package gnupg has no installation candidate`. Root cause: Phase 2's test Dockerfile runs `rm -rf /var/lib/apt/lists/*` after initial base install (standard slim-image pattern, also used in Ubuntu cloud images).
- **Fix:** Added `DEBIAN_FRONTEND=noninteractive apt-get update` before the pre-req install. Idempotent (harmless to re-run). Tightened surrounding comments to stay within the ≤100 LOC plan budget (final LOC = 100, exactly at cap).
- **Files modified:** `plugin/provisioner/30-nodejs.sh` (one new line of code, one reflowed comment block)
- **Verification:** Docker smoke ubuntu-24.04 + ubuntu-22.04 both succeed end-to-end; Node v22.22.2 installed; all 22 bats tests pass on both images.
- **Committed in:** `c6d9b41`

**2. [Rule 3 - Blocking] `compgen -G` returns readdir(3) order, not lexical — breaks numeric dispatch**
- **Found during:** Task 2 Docker ubuntu-24.04 smoke test (post-task verification, after Rule 3 fix 1)
- **Issue:** Installer log showed `running 30-nodejs.sh` BEFORE `running 10-agent-user.sh` — `30-nodejs.sh` Step 6 then failed with `install: invalid user 'agent'` because the agent user hadn't been created yet. Root cause: `plugin/bin/agentlinux-install` line 173 uses `mapfile -t steps < <(compgen -G "$PROV_DIR/[0-9][0-9]-*.sh" || true)` and the comment claimed this yields lexical order. False. `compgen -G` returns directory-entry order (readdir(3) / getdents64(2)), which on ext4/overlayfs depends on inode allocation order. When `30-nodejs.sh` was created AFTER `10-agent-user.sh`, it ended up in an earlier inode slot → returned first in compgen output. Phase 2 never exposed this because the dispatch order with only 10-agent-user.sh + 40-path-wiring.sh happened to be lexically consistent with readdir order.
- **Fix:** Pipe `compgen -G` output through `sort` — single-line change in `run_provisioners()`. Rewrote the code comment to document actual compgen semantics and why sort is mandatory. The plan's own success-criteria verification command (`ls plugin/provisioner/*.sh | grep -E '[0-9]{2}-' | sort`) always implicitly assumed lexical order — now the runtime honors that assumption too.
- **Files modified:** `plugin/bin/agentlinux-install` (one line of code change, comment block rewritten)
- **Scope note:** This file is OUTSIDE Plan 03-01's `files_modified` frontmatter (entrypoint is a Phase 2 artefact). Applied anyway because the fix is directly caused by this plan's addition of a third provisioner (specifically: the filesystem inode allocation for the newly-created `30-nodejs.sh` placed it before `10-agent-user.sh` in readdir order). Alternative (renaming files) is brittle and would violate the plan's own file-name contract.
- **Verification:** Docker smoke ubuntu-24.04 + ubuntu-22.04 both succeed end-to-end with provisioners in correct 10 → 30 → 40 order; all 22 bats tests pass on both images.
- **Committed in:** `3dbfcff`

---

**Total deviations:** 2 Rule 3 auto-fixes.
**Impact on plan:** Both fixes necessary to execute the plan's own Docker smoke verification step (phase-level verification item 4). No scope creep; both fixes directly caused by this plan's additions (first provisioner to install apt packages; first plan to add a provisioner that shifts filesystem inode order). Both fixes make the installer self-sufficient on real-world hosts (cloud images, ext4/overlayfs), not just test containers. Both fixes are legitimate bug discoveries — the first exposes a real Phase 2 testing gap (the test harness Dockerfile strips apt lists and Phase 2 provisioners never exercised apt-get install paths); the second exposes a concrete Phase 2 Plan 02-02 code-comment mistake that phase 3 was the first to trigger.

## Threat-Model Dispositions (from plan)

| Threat | Plan Disposition | Status |
|--------|------------------|--------|
| T-03-01 — Supply-chain (curl-pipe-bash to deb.nodesource.com) | accept (primary) + mitigate (secondary) | ACHIEVED — HTTPS + curl -f cert-verify; gate prevents re-fetch on re-run; GPG-signed apt repo provides ongoing package integrity. Documented accept/trade-off inline in 30-nodejs.sh Step 2. |
| T-03-02 — .npmrc double-append via echo >> | mitigate | ACHIEVED — ensure_line_in_file (grep-before-append) used; no raw echo >>; acceptance grep `! grep -Eq 'echo[^$]*>>'` passes. |
| T-03-03 — NPM_CONFIG_PREFIX vs .npmrc split-brain | mitigate | ACHIEVED — both carry byte-identical value `/home/agent/.npm-global`. Future accidental divergence would fail the plan's cross-grep acceptance criterion (verified post-commit). |
| T-03-04 — Byte-instability on re-run (NodeSource repo add) | mitigate | ACHIEVED — dual-gate (nodesource.sources OR nodesource.list) + NodeSource script self-heals (rm -f both before recreating) + INST-02 Phase 2 bats test confirms byte-stable re-run (`ok 3 INST-02: re-running the installer is byte-stable`). |

## Review Loop

Applied inline per CLAUDE.md §Review Loop + STATE.md precedent (same pattern as Phase 2 Plans 02-03 / 02-04 / 02-05 per `STATE.md`: "Review loop applied inline, one iteration, no actionable findings"). Project's automated subagent-spawn mechanism is not available in this execution environment; rubric triage done directly:

- **bash-engineer rubric** (applied to 30-nodejs.sh, 40-path-wiring.sh, agentlinux-install):
  - Strict-mode inheritance from entrypoint honored in provisioners (no redundant `set -euo pipefail`) — OK
  - State mutations through ensure_dir / ensure_line_in_file / install only — OK
  - Proper `return 1` in sourced fragment, proper quoting of variable expansions (`"${node_major:-0}"`) — OK
  - shellcheck --severity=warning --external-sources --source-path=plugin/lib clean across all three files
  - shfmt -i 2 -ci -bn -d clean across all three files
  - bash -n clean across all three files
  - No actionable findings

- **security-engineer rubric** (applied to both Phase 3 files):
  - T-03-01..04 dispositions executed as planned (see table above)
  - Forbidden substrings in Phase 3 files (30-nodejs.sh + 40-path-wiring.sh scope): `sudo npm install -g` = 0, `/usr/local/bin/` = 0, `sudoers.d` = 0, `sed -i` = 0, `echo[^$]*>>` = 0 — all clean
  - No sudoers drop-in written; no wrapper shim path introduced; curl-pipe-bash is the only trust-boundary crossing and is gated by existence check; NodeSource apt repo brings its own GPG-signed keyring
  - No actionable findings

- **qa-engineer rubric** (applied to 30-nodejs.sh + installer end-to-end):
  - Edge case: Node ≥22 already installed → gate on sources.list.d skips NodeSource setup; apt-get install -y nodejs no-op; version gate logs passes. Verified in Docker smoke (re-run via INST-02 is byte-stable).
  - Edge case: Node <22 installed → neither sources.list.d present; setup_22.x runs; apt-get install upgrades; version gate passes.
  - Edge case: no Node installed → full NodeSource path; Node 22.22.2 installed.
  - PATH ordering after extend: .npm-global/bin FIRST in final PATH across all three literal-PATH artefacts (verified via case-stack trace + cross-grep of literal PATH across agentlinux.env and cron.d).
  - Re-run convergence (INST-02) — existing Phase 2 bats test now covers Phase 3 artefacts because the re-run test diffs full installer output across two runs. Test passes on both Ubuntu 22.04 and 24.04.
  - No actionable findings on the first-pass design; two Rule 3 auto-fixes were discovered during end-to-end Docker smoke (which is the qa-engineer rubric's strongest signal source — cross-file, cross-environment interaction bugs).

Outcome: Four commits total on this plan (2 feat + 2 fix). Each task's first commit passed all 15 plan-defined `verify.automated` checks; the Rule 3 fixes were uncovered only by the end-to-end Docker smoke that the plan itself mandates as phase-level verification step 4.

## Issues Encountered

Both issues are the Rule 3 auto-fixes documented above. Both resolved via forward-fix commits; no rollback needed. Both were legitimate bug discoveries rather than plan-spec violations — the plan's verification steps worked as designed (Docker smoke caught them; now they're fixed).

## User Setup Required

None. Plan 03-01 is fully automated — no external credentials, no manual steps. Future interactive testing happens in Plan 03-02 via bats.

## Next Phase Readiness

**Plan 03-02 is ready to start.** Prerequisites are in place:

- **For `tests/bats/30-runtime.bats`:**
  - `plugin/provisioner/30-nodejs.sh` ships Node 22.22.2 on `/usr/bin/node` (RT-01 bats can assert `run_<mode> 'node --version'` returns `v22.*`)
  - `/home/agent/.npm-global/bin` is on PATH in all six invocation modes (RT-02 `npm install -g cowsay` + `command -v cowsay` can loop all six helpers)
  - `/home/agent/.npm-global/{bin,lib}` agent-owned (RT-03 cleanliness check: after uninstall, these dirs must not contain cowsay artefacts)
  - `npm config get prefix` returns `/home/agent/.npm-global` because both `~agent/.npmrc` and `NPM_CONFIG_PREFIX` env var agree (RT-04 + `assert_user_prefix_in_home` helper)

- **Helper additions for Plan 03-02:**
  - Append `assert_user_prefix_in_home` to `tests/bats/helpers/assertions.bash` (RT-04 diagnostic-on-fail — 03-CONTEXT §specifies shape)
  - Optional: extend `invoke_modes.bash` if any new mode is needed (probably not — Phase 2's six helpers cover RT-02..04)

- **Docker harness is ready to absorb new bats:** `bats tests/bats/` picks up `30-runtime.bats` automatically; no Dockerfile change needed (curl/gnupg are now installed by 30-nodejs.sh Step 1, which means `npm install -g` under ~agent uses them too). End-to-end smoke time with Node install was ~25 seconds on warm image — still within the plan's "< 5 minutes" budget.

No blockers or concerns. Phase 3 wave 1 (provisioner) complete; wave 2 (tests) is unblocked.

## Self-Check: PASSED

File existence verified:
- `plugin/provisioner/30-nodejs.sh` — FOUND (100 lines)
- `plugin/provisioner/40-path-wiring.sh` — FOUND (174 lines)
- `plugin/bin/agentlinux-install` — FOUND (197 lines)

Commit existence verified:
- `74366a0` (feat Task 1) — FOUND
- `1fe6a75` (feat Task 2) — FOUND
- `c6d9b41` (fix Rule 3 #1) — FOUND
- `3dbfcff` (fix Rule 3 #2) — FOUND

Phase-level verification from plan `<verification>`:
1. Provisioner dispatch order — `ls plugin/provisioner/*.sh | sort` → 10-agent-user.sh, 30-nodejs.sh, 40-path-wiring.sh ✓
2. bash -n clean on entrypoint + all three provisioners ✓
3. tests/harness/run.sh → 104/104 PASS (no regression) ✓
4. Docker smoke ubuntu-24.04 → 22/22 bats PASS + Node v22.22.2 installed ✓
4. Docker smoke ubuntu-22.04 → 22/22 bats PASS + Node v22.22.2 installed ✓
5. Forbidden-substring sweep on Phase 3 files only → all 5 forbidden substrings zero matches on both files ✓
6. INST-02 byte-stable re-run → green (Phase 2 bats `ok 3 INST-02: re-running the installer is byte-stable`) ✓

---
*Phase: 03-nodejs-runtime-per-user-npm-prefix*
*Completed: 2026-04-18*
