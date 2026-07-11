---
phase: 3
slug: nodejs-runtime-per-user-npm-prefix
verified_date: 2026-04-18
status: passed
must_haves_verified: 14/14
phase_requirements_covered: 4/4
tst07_gate: GREEN
---

# Phase 3: Node.js Runtime + Per-User npm Prefix — Verification Report

**Phase Goal (ROADMAP.md §Phase 3):** After this phase the agent user has a working Node.js LTS + writable `npm install -g` path under its own home — keystone ownership proof before agents land in Phase 5.

**Verified:** 2026-04-18
**Status:** passed (0 gaps; 0 human-verification items; all runnable behaviors exercised end-to-end on the Docker matrix)
**Mode:** initial verification (no prior VERIFICATION.md)

Phase 3 is scoped to two plans (03-01 installer-side + 03-02 tests/INST-02 extension) that together deliver 4 requirement IDs (RT-01..04). Both plans are marked `✓ 2026-04-18` in ROADMAP.md and STATE.md.

---

## 1. Goal Achievement Summary (Roadmap Success Criteria)

ROADMAP §Phase 3 enumerates five Success Criteria; each is verified below against the codebase plus the live Docker-matrix bats run executed during this verification (Ubuntu 22.04 + 24.04, 27/27 PASS on both).

| SC # | Success Criterion | Status | Evidence |
|------|-------------------|--------|----------|
| 1 | `node --version` returns LTS version in interactive shell AND all non-interactive invocation modes (RT-01) | ✅ VERIFIED | `plugin/provisioner/30-nodejs.sh` installs Node.js 22 LTS via NodeSource + hard-fail major-version gate; `tests/bats/30-runtime.bats` @test `RT-01: agent user sees node v22 LTS in every invocation mode` loops all six `INVOKE_MODES` (interactive, ssh, cron, systemd_user, sudo_u, sudo_u_i) with `SKIP_SYSTEMD_UNAVAILABLE` sentinel-safe skip; greps `^v22\.` against observed output. Live run this verification: `ok 23 RT-01: ...` on Ubuntu 22.04 AND Ubuntu 24.04; installer-log line `Node.js v22.22.2 installed (RT-01 — v22 LTS)`. |
| 2 | Agent user can `npm install -g cowsay` — binary on PATH across all modes, no sudo, no EACCES, no shim (RT-02) | ✅ VERIFIED | `plugin/provisioner/40-path-wiring.sh` prepends `/home/agent/.npm-global/bin` FIRST in profile.d case-stack + `/etc/agentlinux.env` literal PATH + `/etc/cron.d/agentlinux` literal PATH; NPM_CONFIG_PREFIX belt-and-braces in agentlinux.env. `tests/bats/30-runtime.bats` has TWO @tests covering RT-02: (a) `RT-02: cowsay binary resolves to /home/agent/.npm-global/bin in every mode` loops six modes asserting `command -v cowsay` resolves under agent-owned prefix + `cowsay hi` runs; (b) `RT-02: no EACCES during cowsay re-install (INST-05 under npm pressure)` proves no-EACCES on re-install via `assert_no_eacces`. cowsay pinned @1.6.0. Live run: `ok 25 RT-02: ...` + `ok 26 RT-02: ...` on both images. |
| 3 | Agent user can `npm uninstall -g cowsay` cleanly — binary disappears, no leftover files (RT-03) | ✅ VERIFIED | `tests/bats/30-runtime.bats` @test `RT-03: npm uninstall -g cowsay leaves no trace` asserts ALL THREE paths absent: `/home/agent/.npm-global/bin/cowsay`, `/home/agent/.npm-global/bin/cowthink` (Pitfall 9 — cowsay@1.6.0 ships two bin entries), and `/home/agent/.npm-global/lib/node_modules/cowsay`; then loops all six INVOKE_MODES asserting `command -v cowsay` returns NOT-FOUND (no `/cowsay` on PATH). Strongest form of cleanliness contract. Live run: `ok 27 RT-03: ...` on both images. |
| 4 | `npm config get prefix` returns path under agent home — never `/usr`, `/usr/local`, any root-owned (RT-04) | ✅ VERIFIED | `plugin/provisioner/30-nodejs.sh` writes `~agent/.npmrc` with literal `prefix=/home/agent/.npm-global` via `ensure_line_in_file` (grep-before-append — zero diff on re-run); `plugin/provisioner/40-path-wiring.sh` ships matching `NPM_CONFIG_PREFIX=/home/agent/.npm-global` in `/etc/agentlinux.env` (T-03-03 byte-identical split-brain avoidance). `tests/bats/30-runtime.bats` @test `RT-04: npm config get prefix is under /home/agent in every invocation mode` loops six modes calling `assert_user_prefix_in_home` (new helper — case-matches `/home/agent/*` with trailing slash; TST-04 4-line diagnostic on fail). Live run: `ok 24 RT-04: ...` on both images. |
| 5 | Docker bats matrix extended to cover RT-01..04 (one test per requirement minimum), stays green on PR | ✅ VERIFIED | `tests/bats/30-runtime.bats` (NEW, 173 LOC) ships 5 @tests covering RT-01..04 (1 + 2 + 1 + 1 — one RT-02 reinforcement above the minimum). `tests/bats/10-installer.bats` INST-02 @test extended with `/home/agent/.npmrc` + `/etc/apt/sources.list.d/nodesource.sources` (symmetric pre/post `find`). Docker matrix grew from 22 (Phase 2) to 27 @tests on both Ubuntu 22.04 + 24.04. `.github/workflows/test.yml` `bats-docker` matrix job picks up the new file automatically. Live run: `1..27` with 27/27 ok on both images. |

**All 5 Success Criteria observed GREEN end-to-end on the full Docker matrix during this verification.**

---

## 2. Must-Haves Matrix

Combined from plans 03-01 (7 truths) and 03-02 (7 truths). All 14 truths verified.

### Plan 03-01 Must-Have Truths

| #   | Truth | Status | Evidence |
|-----|-------|--------|----------|
| 1   | `node --version` returns v22.x after install | ✅ VERIFIED | Docker matrix both images: installer log shows `Node.js v22.22.2 installed (RT-01 — v22 LTS)`; bats RT-01 @test greens. |
| 2   | `/home/agent/.npm-global` exists agent:agent 0755 with empty `bin/` + `lib/` | ✅ VERIFIED | `plugin/provisioner/30-nodejs.sh` lines 79–81: three `ensure_dir` calls with `0755 agent:agent`. Installer log: `created directory /home/agent/.npm-global (0755 agent:agent)` + bin + lib. |
| 3   | `/home/agent/.npmrc` agent:agent 0644 with exactly one `prefix=/home/agent/.npm-global` line | ✅ VERIFIED | `plugin/provisioner/30-nodejs.sh` lines 88–97: `install -m 0644 -o agent -g agent /dev/null`, `ensure_line_in_file`, explicit `chown agent:agent` + `chmod 0644` re-assertion post-primitive. |
| 4   | Literal PATH line `/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin` in BOTH `/etc/agentlinux.env` AND `/etc/cron.d/agentlinux` | ✅ VERIFIED | `grep -cF 'PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin' plugin/provisioner/40-path-wiring.sh` = 2 (one per heredoc). Heredoc tags remain single-quoted (`<<'ENVFILE'`, `<<'CRON'`) → byte-idempotent re-runs. |
| 5   | `NPM_CONFIG_PREFIX=/home/agent/.npm-global` line in `/etc/agentlinux.env` | ✅ VERIFIED | `grep -cF 'NPM_CONFIG_PREFIX=/home/agent/.npm-global' plugin/provisioner/40-path-wiring.sh` = 1 (inside ENVFILE heredoc body). Value byte-identical to `~agent/.npmrc` prefix line — T-03-03 mitigation. |
| 6   | Re-run is byte-stable across `/home/agent/.npmrc`, `/etc/apt/sources.list.d/nodesource.sources`, `/etc/agentlinux.env`, `/etc/cron.d/agentlinux`, `/etc/profile.d/agentlinux.sh` | ✅ VERIFIED | Bats `INST-02: re-running the installer is byte-stable (idempotency)` extended with the two Phase 3 paths; symmetric pre/post `find … sha256sum`. Live run: `ok 3 INST-02: ...` on both images. |
| 7   | Installer transcript contains no `EACCES`/`permission denied` after Phase 3 additions | ✅ VERIFIED | Bats `INST-05: installer log contains no EACCES or 'permission denied' lines`. Live run: `ok 4 INST-05: ...` on both images. |

### Plan 03-02 Must-Have Truths

| #   | Truth | Status | Evidence |
|-----|-------|--------|----------|
| 8   | `./tests/docker/run.sh ubuntu-{22,24}.04` both exit 0 with Phase 2's 22 + Phase 3's RT @tests + INST-02 extended green | ✅ VERIFIED | Live run this verification: `== PASS: agentlinux-install + bats on ubuntu-22.04 ==` AND `== PASS: agentlinux-install + bats on ubuntu-24.04 ==`; `1..27` on both. |
| 9   | `tests/bats/30-runtime.bats` defines ≥4 ID-prefixed @tests — one per RT requirement (TST-07 gate) | ✅ VERIFIED | `grep -c '^@test' tests/bats/30-runtime.bats` = 5 (four primaries + one reinforcement). Per-req counts: RT-01: 1, RT-02: 2, RT-03: 1, RT-04: 1. |
| 10  | RT-02 test installs `cowsay@1.6.0` once via `as_user`-routed call + loops six INVOKE_MODES asserting `/home/agent/.npm-global/bin/cowsay` + `cowsay hi` | ✅ VERIFIED | `setup_file()` (line 37–43) runs `sudo -u agent -H bash --login -c 'npm install -g cowsay@1.6.0'`. RT-02 primary @test (line 93–110) loops `${INVOKE_MODES[@]}`, calls `assert_path_has "RT-02 (${mode})" "/home/agent/.npm-global/bin/cowsay"` + invokes `cowsay hi` + asserts `hi` in output. |
| 11  | RT-03 asserts byte-clean filesystem after uninstall: NONE of bin/cowsay, bin/cowthink, lib/node_modules/cowsay exist | ✅ VERIFIED | Lines 142–151: `for target in /home/agent/.npm-global/bin/cowsay /home/agent/.npm-global/bin/cowthink /home/agent/.npm-global/lib/node_modules/cowsay; do [[ -e $target ]] && __fail …`. Pitfall 9 two-bin coverage present. |
| 12  | `assert_user_prefix_in_home` helper fires TST-04-shaped `__fail` diagnostic when prefix ∉ `/home/agent/*` | ✅ VERIFIED | `tests/bats/helpers/assertions.bash` lines 115–131: function defined; pass path `case` matches `/home/agent/*` (trailing slash — prevents `/home/agent-staging` false positive); fail path calls `__fail "$req_id" <expected> <observed> <log-hint>` (4 args — TST-04 shape). Used in 30-runtime.bats line 85. |
| 13  | Extended INST-02 sha256 set includes `/home/agent/.npmrc` AND `/etc/apt/sources.list.d/nodesource.sources` | ✅ VERIFIED | `tests/bats/10-installer.bats` lines 44–56 (pre-snapshot) and 61–69 (post-snapshot) both list the two new paths; legacy `nodesource.list` NOT added per Pitfall 1. `grep -cF '/home/agent/.npmrc'` = 3 (1 comment + 2 find calls), `grep -cF '/etc/apt/sources.list.d/nodesource.sources'` = 3 (1 comment + 2 find calls). |
| 14  | Installer transcript grep returns 0 matches for `EACCES\|permission denied` even after 30-nodejs.sh apt-install transaction | ✅ VERIFIED | Bats `INST-05` @test green on both images in live run (`ok 4`). assert_no_eacces scans the full `/var/log/agentlinux-install.log` after the full installer run. |

**Score: 14/14 must-haves verified. No stubs. No orphaned artifacts. No unwired links.**

---

## 3. Required Artifacts

All five artifacts declared in plan frontmatters exist, are substantive, and are wired through the installer dispatch or bats matrix.

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `plugin/provisioner/30-nodejs.sh` | NEW — NodeSource Node 22 + per-user npm prefix | ✅ VERIFIED | 100 LOC; `#!/usr/bin/env bash` shebang; six executable steps; `log_info "30-nodejs: starting"` / `done` bookends; `ensure_line_in_file 'prefix=/home/agent/.npm-global' /home/agent/.npmrc` + `ensure_dir /home/agent/.npm-global 0755 agent:agent` present; `DEBIAN_FRONTEND=noninteractive` used twice (Pitfall 6); dual-gate on both `nodesource.sources` + `nodesource.list` (Pitfall 1); no `sudo npm install -g`; no `sed -i`; no raw `echo >>`; no `/usr/local/bin/`. Sourced by `plugin/bin/agentlinux-install` `run_provisioners` (numeric dispatch 10 → 30 → 40 enforced via `sort` after Plan 03-01 Rule 3 fix). Shellcheck clean. Shfmt clean. bash -n clean. |
| `plugin/provisioner/40-path-wiring.sh` | EXTENDED — prepend `.npm-global/bin` + `NPM_CONFIG_PREFIX` | ✅ VERIFIED | 174 LOC (+28/−6 from Phase 2); two `case ":${PATH}:"` blocks in profile.d (Artefact 1) with .local/bin FIRST and .npm-global/bin SECOND (LIFO → npm-global/bin lands FIRST in final PATH — Pitfall 4); literal `PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:...` appears twice (agentlinux.env + cron.d — cross-grep byte-identical, T-03-03); `NPM_CONFIG_PREFIX=/home/agent/.npm-global` appears exactly once (agentlinux.env only, per design — cron.d's vixie-cron parser doesn't honor arbitrary env lines). All four heredoc tags single-quoted (`<<'PROFILE'`, `<<'BASHRC'`, `<<'ENVFILE'`, `<<'CRON'`) → byte-idempotent. `.bashrc` marker block unchanged. Header comment "Requirements satisfied" lists RT-02 and RT-04. |
| `tests/bats/helpers/assertions.bash` | APPEND `assert_user_prefix_in_home` | ✅ VERIFIED | 131 lines (+37 from Phase 2, 0 deletions). New function appended at bottom (lines 115–131); pass path matches `/home/agent/*`; fail path calls `__fail` with 4 args. Phase 2 helpers (`__fail`, `__diag`, `assert_no_eacces`, `assert_path_has`, `assert_exit_zero`) byte-identical. No `set -euo pipefail` (bats-sourced library convention). Shellcheck clean. |
| `tests/bats/30-runtime.bats` | NEW — RT-01..04 @tests | ✅ VERIFIED | 173 lines; `#!/usr/bin/env bats`; loads both `helpers/invoke_modes` + `helpers/assertions` (2×); defines `setup_file` + `teardown_file`; 5 @tests (`RT-01:` ×1, `RT-02:` ×2, `RT-03:` ×1, `RT-04:` ×1); loops `${INVOKE_MODES[@]}` 4 times; `SKIP_SYSTEMD_UNAVAILABLE` sentinel present 4 times; uses `assert_user_prefix_in_home`, `assert_exit_zero`, `assert_no_eacces`, `assert_path_has`, `__fail`; checks BOTH cowsay AND cowthink; no `set -euo pipefail`; no bare `sudo npm install -g` (all npm calls routed through `sudo -u agent -H bash --login -c` wrapper — matches working `run_sudo_u` helper shape per STATE.md 02-05 Phase 2 deviation). |
| `tests/bats/10-installer.bats` | EDIT — INST-02 set extended | ✅ VERIFIED | 111 lines (+8 from Phase 2, 0 deletions). INST-02 @test extended symmetrically: both pre and post `find` calls now list 7 paths (Phase 2's 5 + `/home/agent/.npmrc` + `/etc/apt/sources.list.d/nodesource.sources`). Legacy `nodesource.list` NOT added. One comment documents Phase 3 rationale. Live run: `ok 3 INST-02: ...` on both images. |

**Bonus artifact modification (in-scope deviation, documented):**

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `tests/bats/helpers/invoke_modes.bash` | (Phase 2 artifact, not in Plan 03-02 `files_modified`) | ✅ VERIFIED (auto-fix) | Two Rule 1 auto-fixes applied in `c4c9fbf`: (a) `run_cron` PATH header prepended `/home/agent/.npm-global/bin` FIRST to mirror installer's real cron.d after Plan 03-01's PATH extension; (b) `run_systemd_user` passes `--quiet` to `systemd-run` to suppress its "Running as unit… Finished with result…" banner that otherwise polluted `$output` for prefix-match assertions. Both fixes required to execute this plan's own Docker-matrix verification. Documented in 03-02-SUMMARY §Deviations and STATE.md "New decisions from Plan 03-02 execution". |
| `plugin/bin/agentlinux-install` | (Phase 2 artifact, not in Plan 03-01 `files_modified`) | ✅ VERIFIED (auto-fix) | One Rule 3 auto-fix in `3dbfcff`: pipe `compgen -G` through `sort` in `run_provisioners()` to enforce numeric dispatch contract (10 → 30 → 40). Phase 2's comment claiming `compgen -G` returned lexical order was incorrect — it returns `readdir(3)` order, which placed 30-nodejs.sh before 10-agent-user.sh once the new file was created. Fix directly caused by this phase's addition of a third provisioner; necessary for installer to run in-order on ext4/overlayfs. |

---

## 4. Requirements Coverage (RT-01..04 × @test)

| Req ID | Description (REQUIREMENTS.md) | Source Plan(s) | @test(s) in 30-runtime.bats | Status |
|--------|-------------------------------|----------------|------------------------------|--------|
| **RT-01** | Agent user has Node.js LTS. `node --version` returns LTS both interactively + non-interactively. | 03-01 (installer), 03-02 (tests) | `RT-01: agent user sees node v22 LTS in every invocation mode` | ✅ SATISFIED — NodeSource Node 22 LTS installed via 30-nodejs.sh with hard-fail major-version gate; six-mode bats loop greps `^v22\.`. Docker 22.04 + 24.04 both green. |
| **RT-02** | Agent user can `npm install -g <pkg>` — binary on PATH in every mode, no sudo, no EACCES, no shim. | 03-01 (PATH wiring), 03-02 (tests) | (a) `RT-02: cowsay binary resolves to /home/agent/.npm-global/bin in every mode`; (b) `RT-02: no EACCES during cowsay re-install (INST-05 under npm pressure)` | ✅ SATISFIED — 40-path-wiring.sh prepends `.npm-global/bin` FIRST across profile.d + agentlinux.env + cron.d; two RT-02 @tests cover six-mode resolution + no-EACCES under re-install pressure. Second @test satisfies VALIDATION task 03-02-05. |
| **RT-03** | Agent user can `npm uninstall -g <pkg>` cleanly. No leftover files, binary gone from PATH. | 03-02 (tests) | `RT-03: npm uninstall -g cowsay leaves no trace` | ✅ SATISFIED — three-path filesystem cleanliness check (cowsay, cowthink, lib/node_modules/cowsay — Pitfall 9 two-bin coverage) + six-mode `command -v cowsay` PATH-absence loop. Strongest form of cleanliness contract. |
| **RT-04** | `npm config get prefix` returns path under agent home; never `/usr`, `/usr/local`, any root-owned. | 03-01 (~agent/.npmrc + NPM_CONFIG_PREFIX), 03-02 (tests + helper) | `RT-04: npm config get prefix is under /home/agent in every invocation mode` | ✅ SATISFIED — belt-and-braces (~agent/.npmrc + NPM_CONFIG_PREFIX env var with byte-identical value); new `assert_user_prefix_in_home` helper enforces `/home/agent/*` prefix with TST-04 diagnostic on fail; six-mode loop. T-03-07 mitigated. |

**Coverage: 4/4 RT requirements satisfied with observable bats proof.** REQUIREMENTS.md table (lines 178–181) shows all four marked `✓ Complete` after Plan 03-02 landed. No orphans: `.planning/REQUIREMENTS.md` line 209 confirms Phase 3's scope is exactly `RT-01..RT-04`; all four are declared in plan frontmatter `requirements:` fields and all four have ID-prefixed @tests. No requirement IDs are mapped to Phase 3 in REQUIREMENTS.md without a supporting plan.

---

## 5. Threat Coverage (T-03-01..T-03-08)

| Threat ID | Category | Disposition | Status |
|-----------|----------|-------------|--------|
| **T-03-01** | Supply-chain — curl-pipe-bash to deb.nodesource.com | accept (primary) + mitigate (secondary) | ✅ HANDLED — HTTPS + `curl -f` cert-verify; idempotent gate prevents re-fetch-and-execute on re-run; GPG-signed apt repo provides ongoing package integrity; script-body SHA-256 NOT verified (accepted trade-off per ADR-005, documented inline in 30-nodejs.sh Step 2 comment). |
| **T-03-02** | Tampering — `.npmrc` double-append via echo >> | mitigate | ✅ HANDLED — `ensure_line_in_file` (grep-before-append) used; acceptance grep `! grep -Eq 'echo[^$]*>>'` passes; re-runs produce zero diff (verified by extended INST-02 test). |
| **T-03-03** | Config split-brain — NPM_CONFIG_PREFIX vs .npmrc divergence | mitigate | ✅ HANDLED — both values byte-identical (`/home/agent/.npm-global`). Cross-grep cacross `40-path-wiring.sh` (ENVFILE heredoc) + generated `~agent/.npmrc` confirm same literal. Any future accidental divergence caught by Plan 03-01 cross-grep acceptance criterion. |
| **T-03-04** | Byte-instability on re-run — NodeSource repo add | mitigate | ✅ HANDLED — dual-gate check on both `nodesource.sources` (modern) AND `nodesource.list` (legacy) short-circuits re-run; NodeSource setup script itself self-heals (rm -f before create); extended INST-02 sha256 test now guards `~agent/.npmrc` + `/etc/apt/sources.list.d/nodesource.sources` — green on both images. |
| **T-03-05** | PATH shadow — /usr/local/bin/cowsay shim | mitigate | ✅ HANDLED — RT-02 @test uses `assert_path_has` to pin cowsay resolution to `/home/agent/.npm-global/bin/cowsay`; any shim regression would fail across all six INVOKE_MODES. Plan 03-01's PATH ordering (`.npm-global/bin` FIRST in final PATH) prevents the shim from winning. |
| **T-03-06** | Uninstall residue — cowsay/cowthink remnants | mitigate | ✅ HANDLED — RT-03 asserts all THREE paths absent (bin/cowsay, bin/cowthink, lib/node_modules/cowsay) + six-mode `command -v cowsay` PATH absence. Pitfall 9 two-bin coverage. |
| **T-03-07** | Information disclosure / Config confusion — prefix returns /usr | mitigate | ✅ HANDLED — `assert_user_prefix_in_home` fires TST-04 diagnostic if prefix ∉ `/home/agent/*`; six-mode loop with per-mode req-id identifies which mode regressed. Belt-and-braces NPM_CONFIG_PREFIX covers `.npmrc` bypass scenarios. |
| **T-03-08** | Env stripping — cron/systemd HOME unset → .npmrc unreadable | mitigate | ✅ HANDLED — `run_systemd_user` passes `--setenv=HOME=/home/agent` + `EnvironmentFile=/etc/agentlinux.env`; vixie-cron exports HOME from passwd entry; six-mode loop catches any regression. Belt-and-braces NPM_CONFIG_PREFIX env var makes prefix resolvable even if $HOME/.npmrc is bypassed. |

**8/8 threats dispositioned as planned. All mitigations either directly exercised by bats (T-03-05..08) or guaranteed by structural invariants verified via grep (T-03-01..04).**

---

## 6. Invariant Checks

All invariants from the verification instructions verified empirically:

| # | Invariant | Command / Check | Result |
|---|-----------|-----------------|--------|
| 1 | No `sudo npm install -g` in Phase 3 plugin/ source | `grep -c 'sudo npm install -g' plugin/provisioner/30-nodejs.sh plugin/provisioner/40-path-wiring.sh` | 0 / 0 ✅ (hits elsewhere in plugin/ are inside DOC-02 anti-pattern warning comments / as_user.sh comment — intentional) |
| 2 | No `/usr/local/bin/` shims created by Phase 3 | `grep -c '/usr/local/bin/' plugin/provisioner/30-nodejs.sh plugin/provisioner/40-path-wiring.sh tests/bats/30-runtime.bats` | 0 / 0 / 0 ✅ (only reference in plugin/ is the DOC-02 CLAUDE.md anti-pattern warning inside `10-agent-user.sh` heredoc — intentional) |
| 3 | No raw `sudo -u` outside `as_user.sh` in plugin/ source | `grep '^\s*sudo -u' plugin/` (executable lines only) | Only `plugin/lib/as_user.sh` (lines 38, 52) ✅ |
| 4 | shellcheck clean on 30-nodejs.sh + 40-path-wiring.sh | `shellcheck --severity=warning --shell=bash --external-sources --source-path=plugin/lib …` | exit 0 ✅ |
| 5 | shfmt clean on 30-nodejs.sh + 40-path-wiring.sh | `shfmt -i 2 -ci -bn -d …` | exit 0, no diff ✅ |
| 6 | `bash tests/harness/run.sh` exits 0 | harness meta-tests | 104/104 PASS ✅ (no regression from Phase 1/2) |
| 7 | `assert_user_prefix_in_home` helper present in assertions.bash | `grep '^assert_user_prefix_in_home' tests/bats/helpers/assertions.bash` | 1 match at line 115 ✅ with TST-04-shaped `__fail` |
| 8 | RT-03 byte-clean check covers cowsay + cowthink + lib/node_modules/cowsay | `grep '/home/agent/.npm-global/bin/cow\|lib/node_modules/cowsay' tests/bats/30-runtime.bats` | all three paths present in the RT-03 for-loop (lines 142–144) ✅ |
| 9 | Heredoc tags in 40-path-wiring.sh still single-quoted | `grep -cF "<<'PROFILE'" / "<<'BASHRC'" / "<<'ENVFILE'" / "<<'CRON'"` | 1 / 1 / 1 / 1 ✅ |
| 10 | PATH literal in ENVFILE heredoc byte-identical to CRON heredoc literal | `grep -cF 'PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin' 40-path-wiring.sh` | 2 ✅ (T-03-03 byte-identity confirmed) |
| 11 | All 8 Phase 3 commit hashes exist in git | `git cat-file -t` for each of 74366a0, 1fe6a75, c6d9b41, 3dbfcff, 03fda88, c4c9fbf, fc78911, 2d6fdb9 | all resolve to `commit` ✅ |

---

## 7. Behavioral Spot-Checks (Step 7b)

Ran full Docker matrix on both Ubuntu images during this verification (live, not cached):

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Installer runs clean on fresh Ubuntu 22.04 | `./tests/docker/run.sh ubuntu-22.04` | banner `agentlinux-install complete`; `1..27` with 27/27 ok | ✅ PASS |
| Installer runs clean on fresh Ubuntu 24.04 | `./tests/docker/run.sh ubuntu-24.04` | banner `agentlinux-install complete`; `1..27` with 27/27 ok; installer log shows `Node.js v22.22.2 installed (RT-01 — v22 LTS)` | ✅ PASS |
| Harness meta-tests | `bash tests/harness/run.sh` | 104/104 PASS (0 not-ok) | ✅ PASS |
| shellcheck on Phase 3 provisioners | `shellcheck --severity=warning --external-sources --source-path=plugin/lib plugin/provisioner/30-nodejs.sh plugin/provisioner/40-path-wiring.sh` | exit 0 | ✅ PASS |
| shfmt on Phase 3 provisioners | `shfmt -i 2 -ci -bn -d plugin/provisioner/30-nodejs.sh plugin/provisioner/40-path-wiring.sh` | exit 0, no diff | ✅ PASS |
| bash -n on Phase 3 provisioners | `bash -n plugin/provisioner/30-nodejs.sh plugin/provisioner/40-path-wiring.sh` | exit 0 | ✅ PASS |

All spot-checks completed in under 2 minutes each. Every runnable behavior in Phase 3 scope exercised end-to-end.

---

## 8. TST-07 Gate (behavior-coverage-auditor)

| Requirement | ID-prefixed @test count | File | Coverage |
|-------------|-------------------------|------|----------|
| RT-01 | 1 | `tests/bats/30-runtime.bats` | Six-mode `node --version` loop, `^v22\.` grep |
| RT-02 | 2 | `tests/bats/30-runtime.bats` | (a) Six-mode cowsay resolution + execution; (b) no-EACCES under re-install pressure |
| RT-03 | 1 | `tests/bats/30-runtime.bats` | Byte-clean filesystem (3 paths) + six-mode PATH absence |
| RT-04 | 1 | `tests/bats/30-runtime.bats` | Six-mode `npm config get prefix` + `assert_user_prefix_in_home` |

**Every RT-XX requirement has ≥1 ID-prefixed @test. INST-02 extended to cover Phase 3 artefacts. TST-07 phase-close gate: GREEN.**

---

## 9. Anti-Patterns Scanned

Scan covered every file modified or created in Phase 3:

| File | TODO/FIXME/PLACEHOLDER | Hardcoded empty | Console-log-only | Stub returns | Severity |
|------|:--:|:--:|:--:|:--:|:--:|
| `plugin/provisioner/30-nodejs.sh` | 0 | 0 | 0 | 0 | — none — |
| `plugin/provisioner/40-path-wiring.sh` | 0 | 0 | 0 | 0 | — none — |
| `plugin/bin/agentlinux-install` (Rule 3 fix) | 0 | 0 | 0 | 0 | — none — |
| `tests/bats/30-runtime.bats` | 0 | 0 | 0 | 0 | — none — |
| `tests/bats/helpers/assertions.bash` | 0 | 0 | 0 | 0 | — none — |
| `tests/bats/helpers/invoke_modes.bash` (Rule 1 fix) | 0 | 0 | 0 | 0 | — none — |
| `tests/bats/10-installer.bats` (INST-02 extension) | 0 | 0 | 0 | 0 | — none — |

No stubs. No placeholders. No `return null/[]/{}` patterns. Every file committed under Phase 3 implements the contract its plan declared.

Note: the `tests/bats/30-runtime.bats` file uses a deliberate `|| echo NOT-FOUND` in the RT-03 six-mode PATH-absence loop — this is a test-intentional shape (keeps sudo/ssh/cron wrapper exit code 0 so the output-check carries the signal), not a stub. Similarly, `setup_file` and `teardown_file` use `|| true` as best-effort hygiene — documented in comments.

---

## 10. Human Verification Required

**None.** Every Phase 3 behavior is observable in a pure Docker harness without any external service, visual rendering, or real-time user input. The Docker matrix run during this verification covers:

- `node --version` invocation in all six modes (programmatic)
- `npm install -g cowsay` + `command -v cowsay` + `cowsay hi` execution (programmatic)
- `npm uninstall -g cowsay` + filesystem state check (programmatic)
- `npm config get prefix` in all six modes (programmatic)
- Installer transcript no-EACCES grep (programmatic)
- Re-run byte-stability via sha256 diff (programmatic)

Phase 3 is infrastructure — no UI, no external service dependencies. No items queued for human testing.

---

## 11. Gaps Summary

**No gaps found.** All 14 must-have truths are verified, all 5 Roadmap Success Criteria pass, all 4 RT requirement IDs have ID-prefixed @tests, all 8 Phase 3 threats are dispositioned as planned, and the Docker matrix is GREEN on both Ubuntu 22.04 and 24.04 with 27/27 bats passing end-to-end.

The two in-scope auto-fixes that expanded beyond each plan's declared `files_modified` (Plan 03-01 `3dbfcff` touching `plugin/bin/agentlinux-install`; Plan 03-02 `c4c9fbf` touching `tests/bats/helpers/invoke_modes.bash`) are both documented forward-fixes directly caused by this phase's own additions, necessary to satisfy the plans' own phase-level verification steps. Both fixes are behavior-preserving improvements (numeric dispatch contract enforcement; helper-accuracy extension) that strengthen downstream phases and were triaged inline per the review-loop convention. Neither introduces risk or incomplete work.

---

## 12. Verdict

**Phase 3 acceptance gate: GREEN.**

- Status: **passed**
- Must-haves verified: **14/14**
- Phase requirements covered: **4/4** (RT-01, RT-02, RT-03, RT-04)
- Threat coverage: **8/8** (T-03-01..08 all handled)
- TST-07 gate: **GREEN**
- Docker matrix: **27/27 on Ubuntu 22.04 + 24.04** (live run during verification)
- Harness meta-tests: **104/104** (no regression)
- Anti-pattern scan: **0 findings**
- Human verification items: **0**

The agent user on a fresh Ubuntu 22.04 or 24.04 system now has:
1. A working Node.js 22 LTS runtime (`/usr/bin/node`) visible in every invocation mode.
2. A writable `npm install -g` prefix under its own home (`/home/agent/.npm-global/bin` on PATH FIRST).
3. Working `npm install -g <pkg>` / `npm uninstall -g <pkg>` with no sudo, no EACCES, no shim, no leftover files.
4. `npm config get prefix` guaranteed to return a path under `/home/agent/` in every invocation mode.

The keystone ownership proof (ADR-004 + ADR-005) is **complete**. Phase 4 (Registry CLI + Catalog + Uninstall) is unblocked.

---

*Verified: 2026-04-18*
*Verifier: Claude (gsd-verifier)*

## VERIFICATION COMPLETE
