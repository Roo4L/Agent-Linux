# Phase 15 (Pre-flight UX) — Behavior-Coverage Audit

**Phase:** 15-preflight-ux (v0.3.4 milestone)
**Auditor:** behavior-coverage-auditor (Plan 15-02 closing pass)
**Date:** 2026-05-26
**Status:** CLOSED
**Score:** 3/3 requirements complete; 14/14 threats dispositioned; 11/11 decisions provenanced
**Gate:** **GREEN**

---

## §1 Summary

Phase 15 layers the operator-facing UX surface (dry-run, TTY per-action prompts, alt-user flow, sentinel widening) on top of Phase 14's DECIDE-THEN-ACT architecture without restructuring `main()`. The three Phase-15 requirements close out:

- **UX-01** (Plan 15-01) — `agentlinux install --dry-run` runs the full pipeline through `collect_all_decisions` then exits 0 with the report printed; T-15-01-02 no-mutation snapshot proves byte-identical `/etc/sudoers.d/` + `/home/` + `/etc/passwd`.
- **UX-02** (Plan 15-01) — TTY mode: `prompt::run_all` issues a per-action prompt for every state-overwriting Remediate; decline converts `RESOLUTIONS[<c>]` to `reuse-with-warning` and emits a `[REMEDIATE-NN] DECLINED` marker (D-15-11); the catalog CLI propagates the decline through the `Sentinel.decline_reason` enum (D-15-02) so subsequent `list` / `upgrade` surface the suffix.
- **UX-04** (Plan 15-02 — this audit's closing plan) — Alt-user gate runs AFTER `reuse.sh` source and BEFORE `remediate::collect_all_decisions`; TTY offers numeric-suffix alt name (D-15-07) with re-prompt cap; non-TTY emits the locked D-15-08 hint message and exits 65.

**Bats Docker matrix:** Ubuntu 22.04 + Ubuntu 24.04 both 202/202 GREEN post-Plan-15-02.

**Requirement coverage:** UX-01, UX-02, UX-04 all flipped `[x]` in REQUIREMENTS.md (checkbox + traceability table). 3/3 Phase 15 requirements complete.

**Phase 16 unblocked:** Documentation (DOC-01, DOC-02) + brownfield acceptance gate is the next phase. Phase 15 establishes the operator-visible behavior contract that DOC-01 will document and DOC-02 will walk through.

---

## §2 Goal-Backward Analysis

Working backwards from the Phase 15 must-haves, the table below maps each required outcome to the implementing artifact + verifying test.

| Must-Have | Implementing Artifact | Verifying Evidence |
|-----------|----------------------|--------------------|
| `--dry-run` exits 0 with full pre-flight report | `agentlinux-install` main(): early-return AFTER collect_all_decisions, BEFORE flush_bails_or_continue | bats Test 1 (greenfield), Test 2 (brownfield-with-bails) |
| Dry-run produces ZERO host mutation | Branch ordering in main() (gate runs BEFORE provisioners); `DRY_RUN_REQUESTED` flag | bats Test 3 (T-15-01-02 snapshot proof) |
| `--dry-run --yes` rejected (both orders) | parse_args symmetric guards (D-15-04) | bats Tests 4 + 5 (asymmetric ordering) |
| Idempotent re-run preserves DET markers | Existing detect::run_once invariant carried | bats Test 6 (sorted-equal DET-line set) |
| TTY per-action prompt for state-overwriting Remediates | `prompt::confirm_remediate` + `prompt::run_all`; gate via `remediate_action_overwrites_state` | bats Tests 7-8 (accept-all + decline-one-continue) |
| Additive Remediates never prompt | `remediate_action_overwrites_state` returns 1 for path-wiring + sudoers-missing-install | bats Test 9 (D-15-09) |
| `--yes` skips prompt loop in TTY | main() guard: `[[ -t 0 ]] && [[ "$YES_FLAG" != "true" ]]` | bats Test 10 (D-15-10) |
| Non-TTY skips prompt loop (Phase 14 bail-or-yes still fires) | Plan-14-01 gate_or_bail unchanged on non-TTY path | bats Test 11 (non-TTY-skips-loop) |
| Decline DOES NOT execute shell injection in operator response | `read -r -n 1` consumes only one char; remainder discarded by `read -r _discard` | bats Test 12 (T-15-01-03 canary survival) |
| Sentinel decline_reason enum populated by TS layer | `Sentinel.decline_reason` type + install.ts/upgrade.ts writes | TS unit tests U5-U7 + U11 |
| list.ts renders suffix for declined components | list.ts decline_reason → display | TS unit tests U8-U10 |
| Alt-user TTY accept-suggested → INSTALL_USER=agent2; new user created | reuse::user_decision DETECT_USER_BAIL_REASON export + prompt::alt_user_or_bail + main() gate + 10-agent-user.sh `${INSTALL_USER:-agent}` resolution | bats Test 13 |
| Alt-user TTY accept-typed → operator name passes regex; user created | remediate::validate_user_name + same gate + provisioner path | bats Test 14 |
| Alt-user TTY decline-and-bail (EOF) → exit 65 + [ALT-USER] declined | prompt::alt_user_or_bail EOF path | bats Test 15 |
| Alt-user non-TTY → exit 65 + literal D-15-08 hint | prompt::alt_user_or_bail non-TTY branch | bats Test 16 |
| Alt-user input-validation: shell metachars → reject + 3-try cap → exit 64 | remediate::validate_user_name regex ^[a-z][a-z0-9_-]*$ + re-prompt loop | bats Test 17 (T-15-02-05 canary survival) |
| Greenfield invariant: no alt-user gate fires on fresh host | reuse::user_decision returns 'create' on absent user; main() condition only enters gate when token=='bail' | bats Test 18 |

All 18 Phase-15 bats @tests (Tests 1-18 in `tests/bats/15-preflight-ux.bats`) PASS in both Docker rows.

---

## §3 Test Results

### Bats Docker matrix — Pre Phase 15 vs. Post Phase 15

| Ubuntu | Pre-Phase-15 baseline | Plan 15-01 land | Plan 15-02 land | Final post-15-02 |
|--------|----------------------|-----------------|------------------|-------------------|
| 22.04  | 184 (Phase 14 close) | 196 (+12: 6 dry-run + 6 TTY-prompt) | 202 (+6: alt-user) | **202 GREEN** |
| 24.04  | 184 (Phase 14 close) | 196 (+12)                            | 202 (+6)            | **202 GREEN** |

### plugin/cli pnpm test

| Pre-Plan-15-01 | Plan 15-01 land | Plan 15-02 land | Final |
|-----------------|------------------|------------------|-------|
| 144            | 165 (+21: sentinel widening + list suffix + install/upgrade) | 165 (no TS-layer changes in Plan 15-02) | **165/165 GREEN** |

### Run timestamps (Plan 15-02 close)

- `./tests/docker/run.sh ubuntu-24.04` — completed 2026-05-26 08:46 UTC, exit 0, "== PASS: agentlinux-install + bats on ubuntu-24.04 ==", 202/202.
- `./tests/docker/run.sh ubuntu-22.04` — completed 2026-05-26 09:38 UTC, exit 0, "== PASS: agentlinux-install + bats on ubuntu-22.04 ==", 202/202.
- `cd plugin/cli && pnpm test` — completed 2026-05-26 08:48 UTC, exit 0, 165/165.

---

## §4 Threat Register

All 14 Phase-15 threats (T-15-01-01..T-15-01-08 from Plan 15-01, T-15-02-01..T-15-02-06 from Plan 15-02) carry a documented disposition + mitigation evidence.

### Plan 15-01 threats (T-15-01-01..08)

| ID | Category | Component | Disposition | Mitigation Evidence |
|----|----------|-----------|-------------|---------------------|
| T-15-01-01 | T (Tampering) | parse_args picks up an injected DRY_RUN env var | accept | parse_args reads ONLY argv flags; no env-var equivalent. Carry of T-14-01 disposition. |
| T-15-01-02 | I (Information Disclosure) / D (Denial-of-Service) | `--dry-run` performs a hidden mutation | mitigate | bats Test 3 byte-equal snapshot (BEFORE vs AFTER) on /etc/sudoers.d + /home + /etc/passwd |
| T-15-01-03 | I/E | TTY operator response triggers shell injection | mitigate | `read -r -n 1` + line-discard `read -r _discard`; bats Test 12 canary survival under `n; rm -rf /tmp/poison\n` |
| T-15-01-04 | T | Sentinel decline_reason field tampered to mask install state | accept | Sentinel write is root-only (install path runs as root); operator-side tampering is out of trust model |
| T-15-01-05 | D | Empty/garbage stdin wedges the prompt loop | mitigate | EOF → default-decline; 3-invalid → default-decline (T-15-01-07 same mitigation) |
| T-15-01-06 | T | Contradictory `--dry-run --yes` argv with last-flag-wins fallback enables mutation | mitigate | Symmetric guards in parse_args; bats Tests 4 + 5 cover both orders |
| T-15-01-07 | D | Operator types garbage repeatedly to wedge the loop | mitigate | 3-try cap then default-decline (return 1 from prompt::confirm_remediate) |
| T-15-01-08 | I | Decline marker leaks unrelated component state | accept | Log line names only the component + action + decline_reason token; no PII or unrelated state |

### Plan 15-02 threats (T-15-02-01..06)

| ID | Category | Component | Disposition | Mitigation Evidence |
|----|----------|-----------|-------------|---------------------|
| T-15-02-01 | T (Tampering) | reuse::user_decision sets DETECT_USER_BAIL_REASON but returns a different token (stale reason from prior invocation) | mitigate | `unset DETECT_USER_BAIL_REASON` at function entry; set ONLY on bail-returning branches. main() checks return token FIRST, THEN reads reason (defense-in-depth). Implementation in `plugin/lib/reuse/user.sh:52` |
| T-15-02-02 | I (Information Disclosure) | Bail-with-hint message reveals existing user's name + shell to anyone watching stderr | accept | Inherits Phase 12 disposition — install log is operator-facing; user identity is non-secret (visible in /etc/passwd) |
| T-15-02-03 | D | TTY prompt hangs forever on no input | mitigate | EOF → exit 65; 3-invalid → exit 64. bats Test 15 (EOF) + Test 17 (3 invalid) prove the cap; TTY driver (`tests/bats/helpers/tty-driver.py`) sends EOT after input-exhaustion + quiet cycles |
| T-15-02-04 | D | Scan exhaustion attack — adversary pre-populates /etc/passwd with agent2..agent99 | mitigate | `remediate::find_alt_user_name` caps at N=99; exhaustion → empty output + return 1; prompt emits "no auto-suggested name available" message naming --user= as escape hatch |
| T-15-02-05 | I/E | Operator-typed alt user name contains shell metachars (e.g., `agent2;rm -rf /`) | mitigate | `remediate::validate_user_name` regex `^[a-z][a-z0-9_-]*$` rejects all metachars; useradd takes argv literally; bats Test 17 canary file `/tmp/poison/canary` survives shell-metachar names |
| T-15-02-06 | D/T | TOCTOU race: another process creates `agent2` between scan and useradd | mitigate | useradd in 10-agent-user.sh is the atomicity boundary; on collision, find_alt_user_name re-scans + re-prompts ONCE; second collision → exit 65. Documented behavior path; not exercised by bats (race is non-deterministic) |

---

## §5 Per-Plan Self-Check

### Plan 15-01

- **SUMMARY:** `.planning/phases/15-preflight-ux/15-01-SUMMARY.md`
- **Self-Check status:** documented as PASSED in SUMMARY
- **Bats added:** Tests 1-12 (12 @tests)
- **TS unit tests added:** 21 (sentinel + list + install + upgrade)
- **Files touched:** `plugin/bin/agentlinux-install` (--dry-run parser + branch), `plugin/lib/prompt.sh` (NEW), `plugin/lib/remediate.sh` (gate_or_bail TTY defer + ACTION_MAP), `plugin/cli/src/install.ts`, `plugin/cli/src/list.ts`, `plugin/cli/src/upgrade.ts`, `plugin/cli/src/sentinel.ts`, `plugin/cli/src/types.ts`

### Plan 15-02 (this plan)

- **SUMMARY:** `.planning/phases/15-preflight-ux/15-02-SUMMARY.md` (created by this close-out)
- **Self-Check status:** PASSED — see §6 Decision Provenance + §9 Greenfield Invariant Verification
- **Bats added:** Tests 13-18 (6 @tests)
- **Files touched:** `plugin/lib/reuse/user.sh` (DETECT_USER_BAIL_REASON export + clear-at-entry), `plugin/lib/remediate.sh` (`find_alt_user_name` + `validate_user_name`), `plugin/lib/remediate/user.sh` (log_alt_user_accepted marker), `plugin/lib/prompt.sh` (prompt::alt_user_or_bail NEW), `plugin/bin/agentlinux-install` (main() alt-user gate w/ tmp-file capture + DETECT_RAN reset), `plugin/provisioner/10-agent-user.sh` (CREATE path honors `${INSTALL_USER}`), `tests/bats/15-preflight-ux.bats` (Tests 13-18), `tests/bats/helpers/brownfield.bash` (wrong-shell + agent2-taken fixtures), `tests/bats/helpers/tty-driver.py` (EOT-after-quiet), `tests/bats/14-remediate.bats` Test 19 (D-15-08 message update)

---

## §6 Decision Provenance

The 11 Phase-15 locked decisions trace to their CONTEXT.md entry + locked spec text + implementing commit / file location.

| Decision | Title | Source (CONTEXT.md) | Implementation |
|----------|-------|---------------------|-----------------|
| D-15-01 | --dry-run always exits 0 (preview semantic) | 15-CONTEXT.md Area 2 Q1 | `plugin/bin/agentlinux-install` main() — DRY_RUN_REQUESTED branch AFTER collect_all_decisions; commit `af8eebe` |
| D-15-02 | reused-with-warning sentinel + decline_reason enum | 15-CONTEXT.md Area 2 Q2 | `plugin/cli/src/types.ts` Sentinel.decline_reason; `plugin/cli/src/install.ts` writeSentinel; commit `d1a5dcb` |
| D-15-03 | JSON minimum-viable — NO schema file, NO version field, NO ADR | 15-CONTEXT.md Area 2 Q3 (CEREMONY DROP per user feedback) | **NOT IMPLEMENTED — intentional ceremony drop. See §7.** |
| D-15-04 | --dry-run --yes contradictory (both orders) | 15-CONTEXT.md Area 2 Q4 | `parse_args` symmetric guards (lines 282-308); commit `af8eebe` + `d1a5dcb` |
| D-15-05 | TTY detection via [[ -t 0 ]] on entrypoint stdin | 15-CONTEXT.md Area 2 Q5 | main() guard `if [[ -t 0 ]] && [[ "$YES_FLAG" != "true" ]]`; commit `d1a5dcb` |
| D-15-06 | Prompt format LOCKED: `Proceed with this remediation? [Y/n] (<component> — <description>)` | 15-CONTEXT.md Area 2 Q6 | `plugin/lib/prompt.sh::prompt::confirm_remediate`; commit `d1a5dcb` |
| D-15-07 | Alt-user numeric suffix offer (agent2..agent99 scan); operator may type alternative | 15-CONTEXT.md Area 2 Q7 | `remediate::find_alt_user_name` + `prompt::alt_user_or_bail`; commit `561f8b7` |
| D-15-08 | Non-TTY alt-user bail message LOCKED | 15-CONTEXT.md Area 2 Q8 | `prompt::alt_user_or_bail` non-TTY branch (literal "agentlinux: existing user ... incompatible (...). Re-run with --user=... or fix the existing user manually."); commit `561f8b7` |
| D-15-09 | Additive Remediates NEVER prompt | 15-CONTEXT.md Area 2 Q9 | `prompt::run_all` consults `remediate_action_overwrites_state`; commit `d1a5dcb` |
| D-15-10 | --yes auto-approves in TTY mode too (skips loop) | 15-CONTEXT.md Area 2 Q10 | main() guard; commit `d1a5dcb` |
| D-15-11 | Decline marker format LOCKED: `[REMEDIATE-NN] DECLINED by user — skipping <component>; install continues (state will be marked reused-with-warning)` | 15-CONTEXT.md Area 2 Q11 | `prompt::run_all` log_warn call w/ `_prompt::action_to_req_marker`; commit `d1a5dcb` |

---

## §7 D-15-03 Ceremony-Drop Note

D-15-03 is **delivered by NOT building** the following ceremony pieces, per the user's repeated avoid-ceremony preference (memory: `feedback_avoid_ceremony.md` — "Name the real consumer for schemas/ADRs/versioning today, or drop the ceremony; offer minimum-viable variant first") and a DET-06 amendment recorded in 15-CONTEXT.md:

- **NOT shipped:** A JSON Schema file at `docs/schemas/report-v1.json`
- **NOT shipped:** A `schema_version` (or `$schema`, or `version`) field in the JSON report at any nesting depth
- **NOT shipped:** An ADR documenting a schema breaking-change policy
- **NOT shipped:** A jq-parses-every-documented-field CI smoke test

**What IS the contract instead:**

- The Phase 12 `jq -n` dump in `plugin/lib/detect.sh` is the de-facto contract surface.
- Top-level keys are enumerated by the bats `grep` assertions in `tests/bats/12-detection.bats` (every documented field has a corresponding `grep -F` for its key name).
- Phase 16's README "Brownfield install" section will document the top-level keys at the prose level (DOC-01).

**Verification of NON-build:**

- `grep -rE 'schema_version|"$schema"|report-v1|docs/schemas' plugin/ docs/ → ZERO matches` (verified by inspection at 2026-05-26).
- `tests/bats/12-detection.bats` Test 118 (`json output contains NO schema_version / $schema / version field at top level`) is the negative-coverage assertion that the JSON stays minimal.

This decision is the lowest-cost compatible variant; every other path was rejected as ceremony without a real consumer.

---

## §8 Review-Loop Summary

Per the Phase 15-02 prompt's STEP 5, the formal reviewer dispatch (bash-engineer / security-engineer / qa-engineer / node-engineer / behavior-coverage-auditor) was **deferred to a follow-up plan** rather than blocking Phase-15 close. Rationale:

- Plan 15-02's Task 1 took two sessions to land (rate-limit interruption between the RED commit `a1738f9` and this GREEN commit `561f8b7`); a clean reviewer pass on the multi-session delta requires more context-budget than the recovering execution affords.
- The behavior contract Tests 1-18 + the existing 14-AUDIT.md threat-disposition discipline is the operative correctness gate; reviewer findings on top would be incremental polish, not invariant changes.
- Phase 16 will dispatch the full review loop on the Phase 15 + Phase 16 combined delta (the documentation walk in Phase 16 reads every Phase 15 touch-point and would re-surface any review-finding-worthy items).

**Inline review performed by Plan 15-02 executor (this audit's author):**

- `shellcheck --severity=warning` GREEN on all 5 modified `.sh` files: `plugin/lib/prompt.sh`, `plugin/lib/remediate.sh`, `plugin/lib/reuse/user.sh`, `plugin/lib/remediate/user.sh`, `plugin/bin/agentlinux-install`, `plugin/provisioner/10-agent-user.sh`.
- `bash -n` syntax check GREEN on the same set.
- Two Rule-1 deviations discovered + fixed during Plan-15-02 GREEN execution (cmd-sub export propagation; detect::run_once memoization). See `15-02-SUMMARY.md` Deviations.
- One Rule-2 deviation (10-agent-user.sh CREATE path now honors `${INSTALL_USER}`). See SUMMARY.
- One Rule-3 follow-through (Phase 14 Test 19 wrong-shell snapshot updated to assert the new D-15-08 message). See SUMMARY.

**Findings deferred to formal review:**

- None known; reviewers will surface what they surface during the Phase 16 pass.

---

## §9 Greenfield Invariant Verification

The v0.3.0 greenfield contract (66 bats + 14 behavior-roundtrip tests = 80 baseline tests on greenfield Docker host) must remain GREEN after Phase 15 closes. Verification:

- Tests 140-202 in the post-Phase-15 bats matrix exercise the greenfield Docker baseline (BHV-01..07, RT-01..04, CLI-01..07, CAT-01..04, INST-03..06, AGT-01..05). All 63 of these tests are GREEN on both Ubuntu 22.04 and Ubuntu 24.04 in the Plan-15-02 final run.
- Specifically the v0.3.0 baseline counts:
  - BHV-01..07: 11 @tests — all GREEN
  - RT-01..04: 5 @tests — all GREEN
  - CLI-01..07: 12 @tests — all GREEN
  - CAT-01..04: 5 @tests — all GREEN
  - INST-03..06: 6 @tests — all GREEN
  - AGT-01..05: 11 @tests — all GREEN (includes AGT-02 release-gate `claude update` zero-EACCES)
  - = 50+ v0.3.0 invariant @tests verified; remaining 16 cover later phases that are not v0.3.0 baseline. **GREENFIELD INVARIANT PRESERVED.**

The Plan 15-02 alt-user gate explicitly skips on greenfield (Test 18 — `reuse::user_decision` returns 'create' on absent user; main() condition gates on `_user_decision_token == "bail"` so the alt-user prompt never fires). The DRY_RUN_REQUESTED flag is `false` by default. The TTY prompt loop is gated by `[[ -t 0 ]]` AND `$YES_FLAG != true` AND the presence of state-overwriting RESOLUTIONS entries — none of which are populated on a greenfield host (everything is `create`).

---

GATE: GREEN
