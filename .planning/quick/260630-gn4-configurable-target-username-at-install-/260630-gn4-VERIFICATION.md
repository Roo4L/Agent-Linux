---
phase: quick-260630-gn4
verified: 2026-06-30T14:15:00Z
status: passed
score: 7/7 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 6/7
  gaps_closed:
    - "Catalog ops (install/remove/upgrade/adopt --all) on a --user=claude install run as sudo -u claude …, NOT sudo -u agent … — dispatchRecipe dispatches recipes as the configured install user, so a system without an `agent` user does not fail (AC4)"
  gaps_remaining: []
  regressions: []
---

# Phase quick-260630-gn4: Configurable Target Username at Install Time — Verification Report

**Phase Goal:** Make the AgentLinux installer provision under an operator-chosen target user (--user / AGENTLINUX_USER / interactive prompt) instead of hardcoded `agent`, with hardened username validation, the resolved user threaded through every provisioner + sudoers + catalog CLI, closing the AL-59 alt-user hollow-install bug.

**Verified:** 2026-06-30T14:15:00Z
**Status:** passed
**Re-verification:** Yes — after gap closure on Truth 6 (AC4 / npm_ls.ts dispatch user)

---

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                                                                                                                                                                     | Status     | Evidence                                                                                                                                                                                                                                                                                |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | curl ... \| bash with no args (non-TTY) installs under `agent` — no behavior change for greenfield (AC1)                                                                                                                                 | VERIFIED   | `INSTALL_USER=agent` default (line 174); `USER_EXPLICITLY_SET=false` (line 175); prompt gated on `[[ -t 0 ]] && [[ "$USER_EXPLICITLY_SET" != true ]]` (line 477); non-interactive curl-pipe never reaches the prompt                                                                    |
| 2   | curl ... \| bash -s -- --user=claude installs every artifact under `claude`, creating or adopting (AC2)                                                                                                                                   | VERIFIED   | `--user=` flag sets `INSTALL_USER` + `USER_EXPLICITLY_SET=true` (lines 227, 236); all provisioners derive paths from `_AL_USER="${INSTALL_USER:-agent}"` / `_AL_HOME="/home/${_AL_USER}"`                                                                                               |
| 3   | AGENTLINUX_USER=claude (env, no flag) is honored identically to --user=claude in non-interactive runs (AC2)                                                                                                                               | VERIFIED   | main() resolves `AGENTLINUX_USER` env at lines 444-446, sets `USER_EXPLICITLY_SET=true`; validated via `remediate::validate_user_name` at line 450                                                                                                                                     |
| 4   | An interactive install prompts 'Install AgentLinux under which user? [agent]' and provisions under the typed name (AC3)                                                                                                                   | VERIFIED   | `prompt::choose_install_user` in plugin/lib/prompt.sh prints chosen name to stdout; re-prompts up to 3x on invalid; Enter accepts default; main() captures via `$(...)`; behavioral tests (PROMPT-OK, DEFAULT-OK) unchanged                                                             |
| 5   | After a --user=claude install, /etc/sudoers.d/agentlinux, /home/claude/.npm-global PATH wiring, CLI symlink+guard, and Node prefix reference `claude`; grep finds zero `\bagent\b` / /home/agent in install artifacts (AC4)             | VERIFIED   | All provisioners (20/30/40/50) use `_AL_USER`/`_AL_HOME`; sudoers built via `printf '%s ALL=(ALL) NOPASSWD: ALL' "$user"`; detect/sudoers.sh drift-check parameterized; grep on provisioners confirmed no `/home/agent` or `agent:agent` literals; `guardAgentUser` reads `resolveInstallUser()` |
| 6   | Catalog ops (install/remove/upgrade/adopt --all) on a --user=claude install run as `sudo -u claude …`, NOT `sudo -u agent …` — dispatchRecipe dispatches recipes as the configured install user (AC4)                                    | VERIFIED   | **Gap now closed.** `npm_ls.ts` imports `resolveInstallUser` (line 25); `queryGlobalNpm` calls `resolveInstallUser()` (line 75) and `dispatcher(user, …)` (line 76); `queryNpmViewLatest` calls `resolveInstallUser()` (line 115) and `dispatcher(user, …)` (line 116); `npmEnvFor(home)` builds PATH/HOME/NPM_CONFIG_PREFIX from `/home/${user}` (lines 35-43); only `/home/agent` mention is a backward-compat comment (line 34) — no functional hardcoding. `runner.ts dispatchRecipe` unchanged: `dispatcher(user, …)` at line 117. |
| 7   | Invalid usernames (root, reserved/system names, non-POSIX charset, existing UID<1000) are rejected with exit 64 before any host mutation (AC5)                                                                                           | VERIFIED   | `remediate::validate_user_name` rejects empty, root, Root, www-data, daemon, nobody, systemd-network, non-POSIX; `remediate::user_adoptable` refuses UID<1000; both called before `detect::run_once`; 23-install-user.bats now includes `AC5 existing system account (uid<1000) refused adoption` test |

**Score:** 7/7 truths verified

---

### Required Artifacts

| Artifact                             | Expected                                                              | Status   | Details                                                                                                          |
| ------------------------------------ | --------------------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------- |
| `plugin/lib/remediate.sh`            | validate_user_name hardened; user_adoptable added                     | VERIFIED | AGENTLINUX_RESERVED_USER_NAMES denylist; systemd-* prefix rejection; separate runtime user_adoptable             |
| `plugin/bin/agentlinux-install`      | --user > AGENTLINUX_USER > prompt > agent resolution                  | VERIFIED | INSTALL_USER=agent default; --user= flag; AGENTLINUX_USER env check; prompt on TTY-only; parse-time validation  |
| `plugin/lib/prompt.sh`               | prompt::choose_install_user                                           | VERIFIED | Prints chosen name to stdout; all prompts to stderr; re-prompts on invalid                                       |
| `plugin/provisioner/40-path-wiring.sh` | Four PATH/env artefacts parameterized on the resolved install user  | VERIFIED | All four artefacts use `_AL_USER`/`_AL_HOME`; agentlinux.env writes AGENTLINUX_USER + AGENTLINUX_AGENT_HOME      |
| `plugin/cli/src/guard/user.ts`       | CLI EUID guard reads configured install user                          | VERIFIED | Imports and calls `resolveInstallUser()` (lines 11, 17); no AGENT_USER constant                                  |
| `plugin/cli/src/runner.ts`           | dispatchRecipe uses resolveInstallUser; dispatcher(user, …)           | VERIFIED | `resolveInstallUser()` exported; `dispatchRecipe` resolves user and dispatches `dispatcher(user, …)` at line 117 |
| `plugin/cli/src/upgrade/npm_ls.ts`   | queryGlobalNpm and queryNpmViewLatest dispatch as resolveInstallUser  | VERIFIED | Fixed: both functions call `resolveInstallUser()` and `dispatcher(user, …)`; env built from `/home/${user}`     |
| `tests/bats/23-install-user.bats`    | INST-07 @tests covering AC1-AC5 + no-leftover-agent + dispatch        | VERIFIED | 9 @tests all prefixed `INST-07:`, covering AC1/AC2/AC3/AC4/AC5 + uid<1000 adoption-refusal + dispatch test      |

---

### Key Link Verification

| From                                         | To                                              | Via                                               | Status     | Details                                                                                                  |
| -------------------------------------------- | ----------------------------------------------- | ------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------- |
| `plugin/bin/agentlinux-install`              | `remediate::validate_user_name`                 | parse-time validation of --user/AGENTLINUX_USER   | WIRED      | Line 451: `remediate::validate_user_name "$INSTALL_USER"` called before require_root                     |
| `plugin/provisioner/40-path-wiring.sh`       | `/etc/agentlinux.env AGENTLINUX_USER=`          | write_file_atomic with resolved user              | WIRED      | Line 124 writes `AGENTLINUX_USER=${_AL_USER}` to agentlinux.env                                         |
| `plugin/cli/src/guard/user.ts`               | `/etc/agentlinux.env AGENTLINUX_USER`           | runtime read via resolveInstallUser()             | WIRED      | resolveInstallUser() in runner.ts reads AGENTLINUX_USER env then /etc/agentlinux.env; guard uses it      |
| `plugin/cli/src/runner.ts dispatchRecipe`    | `resolveInstallUser()` / AGENTLINUX_USER        | dispatcher(user, …)                               | WIRED      | Line 95: `const user = resolveInstallUser()` + line 117: `dispatcher(user, …)`                          |
| `plugin/provisioner/20-sudoers.sh`           | `plugin/lib/remediate/sudoers.sh`               | INSTALL_USER in NOPASSWD line                     | WIRED      | sudoers.sh line 41: `local user="${INSTALL_USER:-agent}"`; line 49: `printf '\n%s ALL=(ALL) NOPASSWD: ALL' "$user"` |
| `plugin/cli/src/upgrade/npm_ls.ts`           | `resolveInstallUser()` / configured user        | dispatcher(user, …) in queryGlobalNpm/queryNpmViewLatest | WIRED | **Fixed.** Both functions call `resolveInstallUser()` and `dispatcher(user, …)` with `npmEnvFor(\`/home/${user}\`)` |

---

### Data-Flow Trace (Level 4)

N/A — this phase produces installer shell scripts + TS CLI modules, not React/UI components rendering dynamic data. No data-flow trace required.

---

### Behavioral Spot-Checks

| Behavior                                                     | Command                                                      | Result                                                        | Status                               |
| ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------- | ------------------------------------ |
| AC5: validate_user_name accepts valid, rejects reserved/invalid | `bash -c '. plugin/lib/remediate.sh; ...'`                | VALIDATE-OK                                                   | PASS (unchanged from initial run)    |
| AC3: prompt::choose_install_user stdout contract             | `bash -c '... printf "claude\n" \| prompt::choose_install_user'` | PROMPT-OK + DEFAULT-OK                                   | PASS (unchanged from initial run)    |
| runner.ts: dispatchRecipe uses `dispatcher(user,…)`          | `grep -q 'dispatcher(user' src/runner.ts`                    | match confirmed (line 117)                                    | PASS                                 |
| npm_ls.ts queryGlobalNpm: no `dispatcher("agent",…)` or functional `/home/agent` | `grep -n 'dispatcher("agent"` npm_ls.ts` + `grep -n '/home/agent' npm_ls.ts` | Only comment on line 34; no functional hits | PASS — gap closed |
| npm_ls.ts: resolveInstallUser called in both functions       | `grep -n 'resolveInstallUser' npm_ls.ts`                     | Lines 25 (import), 62 (jsdoc), 75 (queryGlobalNpm), 115 (queryNpmViewLatest) | PASS |
| 23-install-user.bats: 9 INST-07 tests including dispatch + uid<1000 | `grep -cE '^@test "INST-07:' tests/bats/23-install-user.bats` | 9                                                      | PASS (new uid<1000 + dispatch tests) |

---

### Requirements Coverage

| Requirement | Source Plan       | Description                              | Status    | Evidence                                                                                                    |
| ----------- | ----------------- | ---------------------------------------- | --------- | ----------------------------------------------------------------------------------------------------------- |
| AL-50       | 260630-gn4-PLAN.md | Configurable target username            | SATISFIED | All AC1-AC5 verified; provisioners + sudoers + guard + dispatchRecipe + npm_ls.ts all use configured user |
| INST-07     | 260630-gn4-PLAN.md | Behavior tests for configurable user    | SATISFIED | 23-install-user.bats: 9 INST-07 tests covering AC1-AC5 + no-leftover-agent grep + dispatch behavior        |

---

### Anti-Patterns Found

None — the three blocker anti-patterns from the initial run (`dispatcher("agent", …)` on lines 68 and 108, `NPM_ENV` hardcoding `/home/agent`) have all been removed from `plugin/cli/src/upgrade/npm_ls.ts`. The only remaining `/home/agent` string in that file is a backward-compat comment on line 34 noting the byte-identity invariant for the default user.

---

### Human Verification Required

None — all must-haves are programmatically confirmed.

---

### Gaps Summary

No gaps. The single gap from the initial verification (Truth 6 / AC4 — `npm_ls.ts` hardcoded dispatch user) has been resolved:

- `plugin/cli/src/upgrade/npm_ls.ts` now imports `resolveInstallUser` from `runner.ts` and calls it in both `queryGlobalNpm` and `queryNpmViewLatest`. The `npmEnvFor(home)` helper builds `PATH`, `HOME`, and `NPM_CONFIG_PREFIX` from the resolved user's home directory, making the npm env fully dynamic. Both dispatcher calls pass `user` (not the literal `"agent"`).

- The `tests/bats/23-install-user.bats` suite has grown from 8 to 9 INST-07 tests, adding explicit coverage of uid<1000 adoption refusal (AC5) and the alt-user dispatch path (AC4).

All other must-haves (AC1 default user, AC2 --user/env threading, AC3 interactive prompt, AC4 provisioner/sudoers/guard/dispatchRecipe, AC5 validation) remain correctly implemented and unaffected by the fix.

---

_Verified: 2026-06-30T14:15:00Z_
_Verifier: Claude (gsd-verifier)_
