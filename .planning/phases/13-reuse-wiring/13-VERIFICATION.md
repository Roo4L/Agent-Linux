---
phase: 13
slug: reuse-wiring
verified: 2026-05-20
status: passed
score: 3/3
---

# Phase 13 — Reuse Wiring — Verification

## Summary

Phase 13 verified. All 3 REUSE requirements (REUSE-01, REUSE-02, REUSE-03) marked Complete in REQUIREMENTS.md (checkbox bullets `[x]` AND traceability table rows). Docker matrix green on Ubuntu 22.04 + 24.04: 128/128 bats @tests, 0 failures. CLI unit-test suite green (node:test). Brownfield E2E smoke fires all three REUSE markers, writes `status: "reused"` sentinel, and renders the `(reused — managed by agentlinux upgrade/remove)` disclosure suffix in `list`.

Goal-backward: the phase goal — "provisioner / recipe runner short-circuits instead of clobbering when detection reports compatible state" — is verified by direct evidence on the brownfield fixture (zero `useradd` / `apt install nodejs` / `npm install -g claude-code` invocations + presence of `[REUSE-01]`, `[REUSE-02]`, `[REUSE-03]` markers). The greenfield invariant is intact (the v0.3.0 baseline @tests stay green; Plan 13-01 fall-through paths run unchanged when REUSE returns `create`).

## Goal-Backward Analysis

| # | Must-have | Evidence | Status |
|---|-----------|----------|--------|
| 1 | REUSE-01: pre-existing compatible `agent` user causes `useradd` skip | `plugin/provisioner/10-agent-user.sh` case-branch dispatches on `reuse::user_decision`; bats @tests in `tests/bats/13-reuse.bats` cover REUSE branch + 3 fall-through tokens; brownfield smoke asserts ZERO `useradd ` in install log | ✓ |
| 2 | NOPASSWD-for-apt user-amended bar | `detect::user_can_sudo_apt` reader uses absolute `/usr/bin/apt-get` (T-13-02 mitigation); @test exercises pass + fail paths | ✓ |
| 3 | REUSE-02: pre-existing Node 22 install w/ writable prefix causes apt-install skip | `plugin/provisioner/30-nodejs.sh` case-branch; brownfield smoke asserts ZERO `apt-get install -y --no-install-recommends nodejs` in log | ✓ |
| 4 | REUSE-03: healthy + in-window + path-match catalog agent → sentinel-only write | `plugin/lib/reuse/agents.sh` decision function; `plugin/cli/src/commands/install.ts` tryReuse() short-circuit; sentinel `~agent/.agentlinux/state/claude-code.json` with `status: "reused"` in brownfield smoke | ✓ |
| 5 | AGGRESSIVE ownership: list shows `(reused — managed by agentlinux upgrade/remove)`; upgrade flips status reused→installed; remove deletes binary identically | `plugin/cli/src/commands/{list,upgrade,remove}.ts` + node:test unit coverage; brownfield smoke greps for exact disclosure wording | ✓ |
| 6 | catalog.json `compatibility_window` semver-range field | `claude-code: >=2.0.0 <3.0.0`, `gsd: >=1.37.0 <2.0.0`, `playwright-cli: >=0.1.0 <1.0.0`; schema.json + validate-catalog.mjs updated | ✓ |
| 7 | T-13-01..04 (Plan 01) + T-13-05..08 (Plan 02) threats addressed | Plan threat_model blocks document each with mitigation + verification; renumbered per Warning W-1 fix | ✓ |
| 8 | Per-component decisions, no mode flags | grep returns 0 for `--reuse-strict` / `--reuse-best-effort` / `--no-reuse` across the codebase | ✓ |
| 9 | Brownfield smoke uses setup-script in existing Dockerfile (not new Dockerfile) | `tests/bats/helpers/brownfield.bash::setup_brownfield_host`; no `tests/docker/Dockerfile.brownfield-*` exists | ✓ |
| 10 | Phase 12 read-only invariant intact | Detection layer still passes its no-op @test; Phase 13's mutations are in provisioners (Create branch only) and CLI sentinel writes (post-detection) | ✓ |

## Test Results

- Docker matrix `ubuntu-24.04`: **128/128 PASS** (Pass 2 + Pass 3 idempotency)
- Docker matrix `ubuntu-22.04`: **128/128 PASS**
- node:test (plugin/cli/): **GREEN** (all sentinel-reused / install-shortcut / list-suffix / upgrade-flip / remove-identical unit tests pass)
- Brownfield E2E smoke: GREEN — asserts ZERO `useradd`/`apt install nodejs`/`npm install -g claude-code` + REUSE-01/02/03 markers + sentinel file present
- Greenfield baseline: 97 Phase 12 @tests + 31 new Phase 13 @tests = 128; v0.3.0 baseline of 66 @tests preserved within the 97

## Human Verification Needed

None. All 3 REUSE requirements have bats @test + node:test coverage + brownfield E2E smoke. Phase 13 audit doc at `.planning/phases/13-reuse-wiring/13-AUDIT.md` consolidates per-task evidence per TST-07 phase-close convention.

## Gaps

None. Plan 13-01 deferred 5 minor items (W-3 sudo secure_path defense-in-depth assertion, W-4 PLAN-ID cite column in traceability, W-6 log_debug on reuse.sh source, I-1 bash/TS canonical-path map byte-identity test, I-2 AGENTLINUX_DETECT_CACHE for upgrade/remove if needed later) as inline TODOs in the plan files. None are blocking for v0.3.4 milestone close — they are quality-of-life refinements for future iteration.

## Recommendation

**Proceed to Phase 14** (Remediate + Consent Flag + Exit Codes). The dispatch shape (`case "$(reuse::*_decision ...)" in reuse|create|remediate|bail`) is established and locked. Phase 14 replaces the `remediate|bail) return 1 ;;` stub branches with real handlers without changing the dispatch contract — exactly the contract documented in Phase 13's CONTEXT.md "Phase 13 → Phase 14 contract" section.
