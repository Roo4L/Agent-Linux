---
phase: 15-preflight-ux
plan: 01
subsystem: infra
tags: [bash, typescript, dry-run, tty-prompt, sentinel, list-suffix, decide-then-act, preflight-ux, ux-01, ux-02, d-15-01, d-15-02, d-15-04, t-15-01-02, t-15-01-03, t-15-01-05, t-15-01-06]

# Dependency graph
requires:
  - phase: 14-remediate-consent-flag-exit-codes
    provides: DECIDE-THEN-ACT main() flow + RESOLUTIONS map + remediate::gate_or_bail + flush_bails_or_continue + 4-token dispatch contract + EX_USAGE/EX_DATAERR readonly constants
  - phase: 13-reuse-wiring
    provides: REUSE_AGENT_CANONICAL_PATHS map (consumed by prompt::run_all for per-agent prompts in canonical id-sorted order)
provides:
  - --dry-run flag on bash entrypoint (UX-01) + main() early-return branch positioned AFTER collect_all_decisions, BEFORE flush_bails_or_continue (D-15-01); always exits 0; bails surface IN report
  - --dry-run flag on TS CLI install subcommand (parallels bash entrypoint; computes tryReuse + tryRemediate decisions then exits without dispatchRecipe / writeSentinel)
  - Symmetric --dry-run + --yes contradictory-flags rejection in BOTH bash + TS halves (T-15-01-06 mitigation; D-15-04 lock)
  - plugin/lib/prompt.sh (NEW) — TTY per-action prompt loop (prompt::confirm_remediate + prompt::run_all) with re-prompt cap of 3 + default-decline on EOF (T-15-01-03 / T-15-01-07 mitigations)
  - ACTION_MAP global in remediate.sh — component → action-token, populated unconditionally by gate_or_bail; consumed by prompt.sh
  - DECLINED_COMPONENTS global in prompt.sh — component → decline-reason-token, populated on TTY decline; consumed by provisioner reuse-with-warning case-arms
  - remediate::gate_or_bail TTY-mode behavior: defers bail-registration when [[ -t 0 ]] && ! YES_FLAG && ! DRY_RUN_REQUESTED, leaving the prompt loop to own the consent path
  - Sentinel.status union widened to include "reused-with-warning" (D-15-02) + new optional decline_reason field restricted to a three-token enum (chown-declined | sudoers-drift-declined | reinstall-broken-declined)
  - list.ts text-suffix rendering for reused-with-warning (precedence: broken-after-remediate > reused-with-warning > reused); JSON output carries decline_reason verbatim
  - upgrade.ts treats reused-with-warning identically to reused (T-15-01-05 mitigation — never redispatches the declined remediation)
  - Three provisioner case-arms (10-agent-user.sh, 20-sudoers.sh, 30-nodejs.sh) honor reuse-with-warning by emitting [REUSE-WARN] and SKIPPING mutation
  - 30-nodejs.sh CREATE-path ensure_dir guard so a declined chown is not silently re-applied by the ensure_dir on /home/agent/.npm-global
  - tests/bats/helpers/tty-driver.py (NEW) — Python pty.fork-based driver for reliable TTY simulation (paced byte-by-byte writes after each child quiet cycle)
  - tests/bats/15-preflight-ux.bats with 12 @tests covering UX-01 (Tests 1-6) + UX-02 (Tests 7-12)
  - 11 new TS unit tests covering --dry-run early-return (U1-U4), Sentinel widening (U5-U7), list rendering precedence (U8-U10), upgrade T-15-01-05 (U11)
affects: [15-02-alt-user-and-phase-close, 16-release-docs]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "TTY simulation via Python pty.fork: tests/bats/helpers/tty-driver.py paces input byte-by-byte AFTER each child quiet cycle (the child is blocked on read); avoids the race where all input bytes are written before the child wires up stdin"
    - "Action-map population in gate_or_bail: ACTION_MAP[component]=action populated unconditionally (before consent checks); prompt loop reads it to know which action token to render in 'Proceed?' prompts and which decline_reason token to record"
    - "Provisioner reuse-with-warning case-arm: each state-overwriting provisioner adds a fourth case-arm that LOGS [REUSE-WARN] and SKIPS mutation; component left as-is so operator's decline is honored"
    - "TTY-mode bail deferral: remediate::gate_or_bail returns 0 (no bail) when [[ -t 0 ]] && ! YES_FLAG && ! DRY_RUN_REQUESTED, leaving prompt::run_all to own the per-action consent decision"
    - "Sentinel widening via optional fields: status union adds 'reused-with-warning'; decline_reason narrows to a three-element enum mirroring the prompt loop's action-to-decline_reason map — no string-typing escape hatch for spoofing (T-15-01-04)"
    - "list.ts suffix precedence: broken-after-remediate > reused-with-warning > reused — the most-important operator signal wins when multiple terminal states overlap"
    - "30-nodejs.sh CREATE-path guard: when RESOLUTIONS[npm-prefix]=reuse-with-warning, skip ensure_dir /home/agent/.npm-global so a declined chown is not silently re-applied"

key-files:
  created:
    - plugin/lib/prompt.sh
    - tests/bats/helpers/tty-driver.py
    - tests/bats/15-preflight-ux.bats
    - .planning/phases/15-preflight-ux/15-01-SUMMARY.md
  modified:
    - plugin/bin/agentlinux-install (DRY_RUN_REQUESTED global + --dry-run parse-arm + symmetric --dry-run/--yes contradiction guards in BOTH case-arms + main() dry-run branch + main() prompt-loop call between flush_bails_or_continue and run_provisioners + usage() help text)
    - plugin/lib/remediate.sh (ACTION_MAP global + gate_or_bail TTY-mode bail deferral + ACTION_MAP[component]=action population unconditionally)
    - plugin/provisioner/10-agent-user.sh (reuse-with-warning case-arm — defensive, user component currently doesn't surface a state-overwriting action that goes through prompt loop)
    - plugin/provisioner/20-sudoers.sh (reuse-with-warning case-arm)
    - plugin/provisioner/30-nodejs.sh (reuse-with-warning case-arm + CREATE-path ensure_dir guard)
    - plugin/cli/src/types.ts (Sentinel.status += 'reused-with-warning' + decline_reason optional field)
    - plugin/cli/src/index.ts (Commander --dry-run option on install subcommand)
    - plugin/cli/src/commands/install.ts (InstallOpts.dryRun + top-of-installCmd contradictory-combo guard + dry-run early-return path with text + JSON outputs)
    - plugin/cli/src/commands/list.ts (Row.sentinel_status widening + Row.decline_reason + reusedWithWarningSuffix renderer with precedence rule)
    - plugin/cli/src/commands/upgrade.ts (validateReusedBinary skips stat for reused-with-warning sentinels + pre-upgrade visibility log line)
    - plugin/cli/test/install.test.ts (U1-U4: --dry-run early-return + symmetric contradiction)
    - plugin/cli/test/list.test.ts (U8-U10: literal suffix + JSON decline_reason + precedence over plain reused)
    - plugin/cli/test/sentinel.test.ts (U5-U7: roundtrip for each of the three decline_reason tokens)
    - plugin/cli/test/upgrade.test.ts (U11: reused-with-warning treated identically to reused)

key-decisions:
  - "D-15-01: --dry-run always exits 0 — preview semantic, mirrors `terraform plan` / `apt --simulate` Unix conventions; bails surface IN the printed report, NOT via exit code"
  - "D-15-02: TTY decline writes sentinel status='reused-with-warning' + decline_reason∈{chown-declined, sudoers-drift-declined, reinstall-broken-declined}; widens Sentinel union; consistent with feedback_aggressive_ownership.md (AgentLinux adopts user-managed binaries — decline ≠ unmanaged, it just means user opted to keep current state)"
  - "D-15-04: --dry-run + --yes is contradictory in BOTH orders (exit 64 EX_USAGE) — argv must be unambiguous about whether mutation is allowed; mirrors T-14-02 --yes/--no-yes rejection pattern"
  - "D-15-05: TTY detection via [[ -t 0 ]] on bash entrypoint stdin — single source of truth; no per-call probing in prompt.sh"
  - "D-15-06: prompt format 'Proceed with this remediation? [Y/n] (<component> — <description>)' — capital Y = default-accept; description tells operator what they're approving"
  - "D-15-09: additive remediates NEVER prompt — prompt::run_all consults remediate_action_overwrites_state and skips additive tokens (path-wiring, sudoers-missing-install)"
  - "D-15-10: --yes auto-approves in TTY too; the prompt loop's entry guard at main() short-circuits on YES_FLAG=true"
  - "D-15-11: grep-stable [REMEDIATE-NN] DECLINED marker — '[REMEDIATE-NN] DECLINED by user — skipping <component>; install continues (state will be marked reused-with-warning)' — matches Phase 14 [REMEDIATE-NN] log convention"
  - "Python pty.fork driver for TTY simulation: `script -c | pipe-stdin` was observed to wedge in container envs (the input bytes never reached the inner pty slave); the new driver paces byte-by-byte writes after each child quiet cycle (PROMPT_QUIET_THRESHOLD = 2 select cycles of 0.5s each)"
  - "30-nodejs.sh CREATE-path ensure_dir guard: needed because reuse::nodejs_decision returns 'create' when DETECT_NODEJS_PREFIX_WRITABLE=false, which fires the CREATE-path ensure_dir on /home/agent/.npm-global and would silently chown the prefix back to agent — defeating the prompt loop's decline. The guard skips the ensure_dir when RESOLUTIONS[npm-prefix]=reuse-with-warning so the operator's decline is honored"
  - "List-suffix precedence: broken-after-remediate > reused-with-warning > reused — broken-after-remediate is the highest-urgency state (half-uninstalled, manual recovery required); reused-with-warning is operator-actionable (decline_reason names the fix they need to apply manually); plain reused is just informational about AgentLinux's ownership flip"

patterns-established:
  - "Decline-then-skip provisioner case-arm pattern: each state-overwriting provisioner adds a fourth case-arm `reuse-with-warning) log_warn '[REUSE-WARN] component=<id> decline_reason=<token> — skipped (...)' ;;` so the operator's decline is honored deterministically"
  - "ACTION_MAP population in gate_or_bail: by recording the action token BEFORE the consent check, the prompt loop has everything it needs without re-deriving the action token from RESOLUTIONS"
  - "Python pty-driver test helper: tests/bats/helpers/tty-driver.py is the reliable cross-environment TTY simulation primitive for any future bats @test that needs to drive an interactive prompt loop"
  - "Symmetric contradictory-flag guards: --dry-run + --yes follows the same T-14-02 pattern as --yes + --no-yes — guards live in BOTH case-arms so order-of-flags doesn't matter"
  - "Sentinel decline_reason narrowing: TS union type narrows to a three-element enum, never derived from user input — T-15-01-04 mitigation against decline_reason injection"

requirements-completed: [UX-01, UX-02]

# Metrics
duration: 4h 10m
completed: 2026-05-25
---

# Phase 15 Plan 01: Pre-flight UX (--dry-run + TTY per-action prompts + Sentinel widening) Summary

`--dry-run` flag on BOTH bash entrypoint + TS CLI install subcommand (with symmetric --yes contradiction rejection), TTY per-action prompt loop with decline-and-continue semantics, and Sentinel widening (`reused-with-warning` + `decline_reason`) — all extending the Phase 14 DECIDE-THEN-ACT pipeline without restructuring it.

## What Plan 15-01 lands

This wave makes the maintainer-VM operator experience first-class:

- **--dry-run preview** (UX-01): operator runs `agentlinux-install --dry-run` on a brownfield host. The full Phase 12-14 detect → decide pipeline runs and prints the report; the installer exits 0 without touching `/etc`, `/home`, or `/var/log` (verified byte-for-byte by Test 3's no-mutation snapshot). Symmetric on the CLI side via `agentlinux install <name> --dry-run`.
- **TTY per-action prompts** (UX-02): when stdin is a TTY, after the pre-flight report each state-overwriting Remediate action (REMEDIATE-01 chown, REMEDIATE-03 sudoers-drift, REMEDIATE-04 reinstall-broken) issues `Proceed with this remediation? [Y/n]`. Decline = skip THAT one remediation, mark the component `reused-with-warning` in the sentinel, continue with the rest. Additive actions (PATH wiring, missing-file sudoers install) run unconfirmed. `--yes` auto-approves every prompt in TTY mode too.
- **Sentinel widening** (D-15-02): the sentinel's status union grows a fourth value `reused-with-warning` plus an optional `decline_reason` that mirrors the prompt loop's three-element token map. `agentlinux list` renders these with a distinct suffix; `agentlinux upgrade` treats them identically to plain `reused` (T-15-01-05).

## Architectural integration

Plan 15-01 inserts two new gates into Phase 14's DECIDE-THEN-ACT main() flow WITHOUT restructuring the ordered pipeline:

```
parse_args                                # --dry-run / --yes / --no-yes; EX_USAGE on contradictions (D-15-04)
detect::run_once                          # read-only (Phase 12 — unchanged)
remediate::collect_all_decisions          # populate RESOLUTIONS + BAILED_COMPONENTS (Phase 14)
                                          # NEW: also populate ACTION_MAP[component]=action (Plan 15-01)

if DRY_RUN_REQUESTED:                     # NEW (D-15-01)
  detect::emit_report "$REPORT_FORMAT"
  exit 0                                  # always 0 — preview semantic

remediate::flush_bails_or_continue        # Phase 14; in TTY mode it's a no-op (gate_or_bail defers bails)

if [[ -t 0 ]] && [[ "$YES_FLAG" != true ]]:  # NEW (D-15-05, D-15-10)
  source plugin/lib/prompt.sh
  prompt::run_all                         # NEW (D-15-06): per-action prompt;
                                          # decline → RESOLUTIONS[component]=reuse-with-warning
                                          # + DECLINED_COMPONENTS[component]=<reason>
                                          # + [REMEDIATE-NN] DECLINED log marker (D-15-11)

run_provisioners                          # Phase 14 — provisioners now ALSO honor reuse-with-warning
                                          # (skip mutation; emit [REUSE-WARN] log line)
```

`remediate::gate_or_bail` was extended to:
1. Populate `ACTION_MAP[component]=action` unconditionally (the prompt loop needs the action-token regardless of consent outcome).
2. In TTY mode (and not `--yes`, not `--dry-run`), DEFER bail-registration — leave consent to the prompt loop. In dry-run we still register bails so they surface in the printed report (D-15-01 explicit).

## TS half

CLI `agentlinux install <name> --dry-run` parallels the bash entrypoint's behavior for per-agent installs (Plan 14-03's T-14-12 separates the two operator invocations). After loadCatalog + entry resolve + tryReuse + tryRemediate decisions are computed, the dry-run branch emits a `[DRY-RUN]` summary (text or JSON) and returns without calling `dispatchRecipe` or `writeSentinel`. Symmetric `--dry-run + --yes` rejection lives at the top of installCmd.

Sentinel widening flows through `types.ts → sentinel.ts → list.ts → upgrade.ts`:
- `Sentinel.status` union adds `"reused-with-warning"`; new optional `decline_reason` field narrows to a three-element enum.
- `list.ts` text output: `' (reused — declined remediation: <decline_reason>; manual fix needed)'` suffix appended to the INSTALLED column; precedence: `broken-after-remediate > reused-with-warning > reused`.
- `list.ts` JSON output: `sentinel_status` + `decline_reason` carried verbatim.
- `upgrade.ts` (T-15-01-05): `validateReusedBinary` returns true for `reused-with-warning` sentinels (no binary_path to validate; trust the sentinel); the reconcile loop's report-only default never redispatches the declined remediation; the pre-upgrade visibility log surfaces the decline_reason so the operator sees what's being preserved.

## Decline-reason token map (D-15-02 — owned by prompt.sh)

| action token             | decline_reason token         |
|--------------------------|------------------------------|
| npm-prefix-chown         | chown-declined               |
| npm-prefix-rebase        | chown-declined               |
| sudoers-drift-overwrite  | sudoers-drift-declined       |
| agent-reinstall          | reinstall-broken-declined    |

The same map is mirrored in `plugin/cli/src/types.ts`'s `decline_reason` narrowed union — TypeScript catches any drift at compile time.

## TTY simulation in tests/bats/

The initial implementation used `script -q -e -c "<cmd>" /dev/null` with `printf "Y\nY\n" | ...` to allocate a pty for the inner installer. This wedged in the Docker container env: the input bytes never reached the inner pty slave even though `[[ -t 0 ]]` was true inside the child. Root cause was a timing race — when all input bytes are written before the child has wired up its stdin descriptor, the bytes are lost.

The fix: a Python `pty.fork`-based driver at `tests/bats/helpers/tty-driver.py` that paces input byte-by-byte AFTER each child quiet cycle (`PROMPT_QUIET_THRESHOLD = 2` select cycles of 0.5s each). When the child blocks on read (quiet output), the driver writes the next byte. This is robust across container environments and is the new reliable TTY-simulation primitive for any future bats @test that needs to drive an interactive prompt loop.

## Test coverage

- **bats** (Ubuntu 22.04 + 24.04 matrix, both GREEN): 196/196 total. Plan 15-01 added 12 new @tests in `tests/bats/15-preflight-ux.bats`:
  - Tests 1-6 (UX-01): greenfield dry-run + brownfield dry-run exit-0 + T-15-01-02 no-mutation snapshot + both contradictory-flag orders + idempotency.
  - Tests 7-12 (UX-02): TTY accept-all + decline-one-continue-others + additive-never-prompts + --yes-skips-loop + non-TTY-skips-loop + T-15-01-03 input-sanitization (`n; rm -rf /tmp/poison\nY\n` does NOT execute the injected text — canary file survives).
- **TS** (node:test, `pnpm test`): 165/165 total. Plan 15-01 added 11 new tests:
  - U1-U4: installCmd dry-run early-return + symmetric `--dry-run + --yes` contradiction (exit 64).
  - U5-U7: Sentinel roundtrip for each of the three decline_reason tokens.
  - U8-U10: list.ts literal suffix + JSON decline_reason + precedence over plain reused.
  - U11: upgrade.ts T-15-01-05 — reused-with-warning preserved through report-only mode.

## Threat-model mitigation evidence

| Threat ID | Disposition | Evidence |
|-----------|-------------|----------|
| T-15-01-01 (TTY spoofing) | accept | D-15-05 contract: a script redirecting stdin from /dev/tty IS the TTY path; documented in --help. No mitigation needed — the contract IS the disposition. |
| T-15-01-02 (dry-run side-effect leakage) | mitigate | bats Test 3 (no-mutation snapshot): sha256sum of every file under /etc/sudoers.d /home /etc/passwd before+after `agentlinux-install --dry-run` on a brownfield REMEDIATE-01 + REMEDIATE-03 combo fixture; byte-identical diff -r asserted. |
| T-15-01-03 (prompt-loop input injection) | mitigate | `read -r -n 1` in prompt::confirm_remediate (no backslash escapes; single char; `;` and following text consumed by line-discard in re-prompt loop, never eval'd). bats Test 12 pipes `n; rm -rf /tmp/poison\nY\n`; the canary file /tmp/poison/canary survives. |
| T-15-01-04 (sentinel decline_reason injection) | mitigate | TS union type narrows decline_reason to a three-element enum; never derived from user input. Component names from hardcoded RESOLUTIONS keys; catalog ids validated by Phase 4 regex `^[a-z][a-z0-9_-]*$`. JSON.stringify on write (no shell interpolation). |
| T-15-01-05 (upgrade-vs-decline desync) | mitigate | upgrade.ts validateReusedBinary returns true for reused-with-warning sentinels; report-only default never redispatches. TS Test U11 asserts 0 dispatchRecipe calls. |
| T-15-01-06 (--dry-run + --yes silent winner) | mitigate | Symmetric guards in BOTH case-arms of parse_args (bash) AND top-of-installCmd guard (TS); bats Tests 4-5 + TS U4 assert exit 64 with the precise diagnostic in both orders. |
| T-15-01-07 (prompt-loop hang on stdin close) | accept | bash read returns non-zero on EOF; prompt::confirm_remediate defaults to decline. Re-prompt cap of 3 prevents infinite-loop on garbage input. Documented in prompt::confirm_remediate comments. |
| T-15-01-08 (sentinel persistence) | accept | Inherited from Phase 14 T-14-11. No PII in the sentinel — only component id, version, decline_reason token. |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] TTY simulation via `script -c | pipe-stdin` wedged in container env**
- **Found during:** Task 2 GREEN verification
- **Issue:** The plan suggested `printf "Y\n" | script -q -e -c "$INSTALLER" /dev/null` as the TTY-driver pattern. In Docker containers (host: util-linux 2.39 also affected — verified), the input bytes never reach the inner pty slave; bash blocks indefinitely on its first `read -r -n 1`. The test_prompt isolation reproductions worked on the bash host but not under bats `run` capture.
- **Fix:** Added `tests/bats/helpers/tty-driver.py` (~140 lines, Python `pty.fork`) that paces input byte-by-byte AFTER each child quiet cycle. Reliable across both host and container envs.
- **Files modified:** `tests/bats/helpers/tty-driver.py` (NEW), `tests/bats/15-preflight-ux.bats` (5 `script -c` references replaced with `python3 "$TTY_DRIVER"`).
- **Commit:** d1a5dcb

**2. [Rule 1 — Bug] CREATE-path ensure_dir silently re-chowned declined npm-prefix**
- **Found during:** Task 2 GREEN verification (Test 129 expected owner=root after decline; got owner=agent)
- **Issue:** `reuse::nodejs_decision` returns `create` when DETECT_NODEJS_PREFIX_WRITABLE=false (the npm-prefix being root-owned is itself a reason Node-install layer's prefix check fails). The CREATE-path in 30-nodejs.sh then runs `ensure_dir /home/agent/.npm-global 0755 agent:agent`, which chowns the parent to agent — defeating the prompt loop's decline. Phase 14's design conflates Node-install-layer prefix checks with the per-user npm-prefix layer; Plan 15-01's decline semantic depends on the per-user prefix being preserved.
- **Fix:** Added a guard in 30-nodejs.sh CREATE path: when `RESOLUTIONS[npm-prefix]=reuse-with-warning`, skip the three `ensure_dir` calls on `/home/agent/.npm-global` + bin/ + lib/. The 50-registry-cli.sh still does `ensure_dir /home/agent/.npm-global/bin 0755 agent:agent` (needed for the agentlinux symlink), so the bin/ sub-dir becomes agent-owned — an accepted compromise documented inline.
- **Files modified:** `plugin/provisioner/30-nodejs.sh`
- **Commit:** d1a5dcb

**3. [Rule 1 — Bug] `grep -F '--dry-run forbids --yes'` parsed `-F` as option, not start-of-pattern**
- **Found during:** Task 2 GREEN verification (Tests 125/126 failing with `grep: unrecognized option '--dry-run forbids --yes'`)
- **Issue:** GNU grep's `-qF` option-parsing stops at the first non-option arg unless `--` is passed. Without `--`, the pattern starting with `--` was interpreted as an unknown option.
- **Fix:** Added `--` between the option flags and the pattern.
- **Files modified:** `tests/bats/15-preflight-ux.bats`
- **Commit:** d1a5dcb

**4. [Rule 1 — Bug] usage() help text matched UX-05 grep guard `^[^#]*\bexit 64\b`**
- **Found during:** Task 2 GREEN verification (Phase 14 Test 65 — `UX-05: 'readonly EX_USAGE=64' and 'readonly EX_DATAERR=65' present in plugin/bin/agentlinux-install`)
- **Issue:** The Phase 14 test asserts no literal `exit 64` outside `exit "$EX_USAGE"` form. My new usage() help text included `(exit 64)` as plain documentation prose inside the heredoc — caught by the grep.
- **Fix:** Rephrased to `(rejected as usage error)`.
- **Files modified:** `plugin/bin/agentlinux-install`
- **Commit:** d1a5dcb

## Self-Check: PASSED

- [x] DRY_RUN_REQUESTED global declared + parse_args case arm + main() branch — verified by `grep -c "DRY_RUN_REQUESTED" plugin/bin/agentlinux-install` ≥ 4.
- [x] Symmetric --dry-run + --yes contradiction handling in BOTH case arms (T-15-01-06).
- [x] CLI install gains --dry-run option in commander + InstallOpts interface + installCmd contradict-check + early-return.
- [x] plugin/lib/prompt.sh exists with prompt::confirm_remediate + prompt::run_all + decline-reason map + DECLINED_COMPONENTS global.
- [x] plugin/lib/remediate.sh adds ACTION_MAP global + populates in gate_or_bail; TTY mode no longer registers bails (defers to prompt.sh).
- [x] plugin/bin/agentlinux-install main() sources prompt.sh + calls prompt::run_all between flush_bails_or_continue and run_provisioners.
- [x] All three relevant provisioners (10-agent-user, 20-sudoers, 30-nodejs) gain reuse-with-warning case-arm that LOGS [REUSE-WARN] and SKIPS mutation.
- [x] Sentinel.status union widened to include reused-with-warning (TS type).
- [x] Sentinel gains decline_reason optional field with three-token enum.
- [x] list.ts renders reused-with-warning suffix with interpolated decline_reason; precedence over plain reused.
- [x] upgrade.ts treats reused-with-warning identically to reused (T-15-01-05).
- [x] 12 bats @tests in tests/bats/15-preflight-ux.bats pass on Ubuntu 22.04 + 24.04 (196/196 total).
- [x] 11 TS unit tests across install.test.ts + sentinel.test.ts + list.test.ts + upgrade.test.ts pass (165/165 total).
- [x] T-15-01-02 verified: bats Test 3 byte-identical snapshot.
- [x] T-15-01-03 verified: bats Test 12 canary file /tmp/poison/canary survives shell-injection attempt.
- [x] T-15-01-05 verified: TS Test U11 upgrade does not redispatch declined remediation.
- [x] T-15-01-06 verified: bats Tests 4-5 + TS U4 both exit 64 with the symmetric diagnostic.
- [x] NO schema file / version field / ADR added (D-15-03 negative invariant) — no new files under docs/schemas or docs/decisions/.
- [x] Phase 14 contract preserved: T-14-01 grep still green; T-14-02 still green; DECIDE-THEN-ACT main() ordering unchanged.
- [x] Phase 13 + Phase 12 contracts preserved: detect::run_once unchanged; reuse:: dispatch unchanged.
- [x] All Plan 15-01 commits exist in git log: 95f6fd0, af8eebe, 20f8539, d1a5dcb.
