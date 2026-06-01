# Phase 13 (Reuse Wiring) — Behavior-Coverage Audit

**Phase:** 13-reuse-wiring (v0.3.4 milestone)
**Auditor:** behavior-coverage-auditor (Plan 13-02 closing pass)
**Date:** 2026-05-20
**Gate:** **GREEN**

## Phase Boundary

Phase 13 wires the Phase-12 `detect::` readers into provisioners and the catalog recipe runner so that compatible pre-existing state causes a clean short-circuit instead of a clobber. Concretely, REUSE-01 (existing agent user), REUSE-02 (existing Node 22 install), REUSE-03 (existing catalog agent) each get per-component decision-functions returning `{reuse, create, remediate, bail}` on stdout, with the dispatching `case` blocks landing at the top of `10-agent-user.sh` (REUSE-01), `30-nodejs.sh` (REUSE-02), and `plugin/cli/src/commands/install.ts` (REUSE-03). A brownfield E2E smoke @test proves the contract end-to-end on a pre-populated Docker container.

## REQ-ID Evidence Trail

Per the milestone's "Verification Convention" (REQUIREMENTS.md §Verification Convention — TST-07 phase-close pattern from v0.3.0), every Phase-13 requirement closes with ≥1 verifiable artifact (bats @test, audit-doc reference, or workflow-run citation). All three Phase-13 requirements (REUSE-01..03) carry at-least-one bats @test reference:

| Requirement | Owning Plan | Status | Bats @test references | Audit-doc reference |
|-------------|-------------|--------|------------------------|---------------------|
| REUSE-01 | 13-01 | Complete | `tests/bats/13-reuse.bats:104` "REUSE-01: reuse::user_decision returns 'reuse' on post-installer host (5 predicates pass)" + 5 sibling dispatch @tests + `:273` "re-running installer on post-installer host emits [REUSE-01] marker" + Plan 13-02 brownfield E2E smoke (`:516`) | `13-01-SUMMARY.md` (Plan 13-01 close-out) + `13-02-SUMMARY.md` (brownfield E2E evidence trail) |
| REUSE-02 | 13-01 | Complete | `tests/bats/13-reuse.bats:189` "REUSE-02: reuse::nodejs_decision returns 'reuse' when DETECT exports satisfy BOTH predicates" + 3 sibling matrix @tests + `:346` dispatch-shape check on 30-nodejs.sh | `13-01-SUMMARY.md` |
| REUSE-03 | 13-02 | Complete | `tests/bats/13-reuse.bats:404` "reuse::agent_decision returns 'create' when status=absent" + 4 sibling dispatch-matrix @tests + `:463` "compatibility_window on 3 non-test entries" + `:480` "schema declares compatibility_window field" + `:489` "reuse.sh sources reuse/agents.sh" + Plan 13-02 brownfield E2E smoke (`:516`, `:589`) + 15 unit tests in `plugin/cli/test/{sentinel,install,list,upgrade,remove}.test.ts` | `13-02-SUMMARY.md` (this plan's close-out) |

## Coverage by Layer

### Bash layer (plugin/lib/reuse/*.sh + provisioners)

- **reuse::user_decision** — 6 @tests covering all 4 dispatch tokens + 5-predicate matrix (Plan 13-01).
- **reuse::nodejs_decision** — 4 @tests covering reuse + create-on-no-write + create-on-count-0 + create-on-Node-20 (Plan 13-01).
- **reuse::agent_decision** — 5 @tests covering create-on-absent + reuse-on-healthy+path-match + remediate-on-path-mismatch + remediate-on-broken + create-on-unknown-id (Plan 13-02).
- **Provisioner short-circuits** — 2 dispatch-shape @tests (10-agent-user.sh case enumerates all 4 tokens; 30-nodejs.sh case enumerates reuse + create) (Plan 13-01).
- **Marker-line emission** — 2 marker-presence @tests asserting `[REUSE-01]` + `[REUSE-02]` literal-string greppability in the installer transcript (Plan 13-01).
- **Greenfield invariant** — bats @test count >= 119 (post-Plan-13-02 Task-1 baseline; final count 128) (Plan 13-01, raised in Plan 13-02).

### CLI layer (plugin/cli/src/commands/*.ts + state/sentinel.ts)

- **Widened Sentinel discriminator** — 1 unit test for the reused-shape roundtrip (sentinel.test.ts).
- **REUSE-03 pre-runner in install.ts** — 6 unit tests covering cache-absent + path-mismatch + version-OOW + --force bypass + --version bypass + existing-sentinel suppression (install.test.ts).
- **(reused — managed) suffix in list.ts** — 3 unit tests covering text-output suffix + JSON sentinel_status discriminator + installed-sentinels-don't-get-suffix (list.test.ts).
- **Reused → installed flip in upgrade.ts** — 3 unit tests covering REUSE-field clearing + T-13-07 stale-reused override + reused-flip log line (upgrade.test.ts).
- **T-13-07 in remove.ts** — 2 unit tests covering reused-identical-to-installed + stale-reused-skip-uninstall (remove.test.ts).

### Catalog / schema layer

- **compatibility_window field** — 2 @tests in 13-reuse.bats covering the 3-on-non-test-entries invariant + schema declaration (Plan 13-02).
- **Validate-catalog round-trip** — `node plugin/cli/scripts/validate-catalog.mjs` exits 0 (verified inline + in pre-commit).

### Brownfield E2E (the canonical smoke)

- **2 @tests** in 13-reuse.bats:
  - "REUSE-03 brownfield E2E: agentlinux-install on pre-populated host fires REUSE-01 + REUSE-03 + writes reused sentinel"
  - "REUSE-03 brownfield E2E: agentlinux list shows (reused — managed) suffix on the reused entry"
- **Coverage:** REUSE-01 firing on real brownfield host + REUSE-03 firing via CLI install + sentinel shape + AGGRESSIVE-ownership disclosure surface + cleanup pattern for downstream CAT-02 hygiene.
- **Skip-with-message** when offline (curl precheck against claude.ai); CI image has the required outbound HTTP.

## Threat-Model Coverage

Phase 13 threat-register entries (T-13-01..T-13-08) each have a documented disposition + mitigation evidence:

| Threat ID | Disposition | Mitigation Evidence |
|-----------|-------------|---------------------|
| T-13-01 (bash detect-cache trust) | mitigate | Plan 13-01 entrypoint-order @test + cache-overwrite-per-run pattern |
| T-13-02 (PATH-shim against bare apt-get) | mitigate | Plan 13-01 absolute-path `/usr/bin/apt-get` + raw `sudo -u -n` in detect::user_can_sudo_apt |
| T-13-03 (predicate bypass on user_decision) | mitigate | Plan 13-01 5-predicate ordered-matrix @tests (all 4 dispatch tokens covered) |
| T-13-04 (marker-line info disclosure) | accept | Plan 13-01 marker format documented in CONTEXT.md Area 1 Q4 |
| T-13-05 (CLI-side cache tampering) | mitigate | Plan 13-02 cache-overwrite-per-run + agent-readable-only on tmpfs; install.ts re-reads via env-overridable path |
| T-13-06 (inherited PATH-shim) | mitigate (transitive) | Plan 13-02 inherits T-13-02 mitigation; REUSE-03 doesn't invoke sudo |
| T-13-07 (sentinel JSON blind trust) | mitigate | Plan 13-02 existsSync + statSync re-validation in remove.ts + upgrade.ts; 4 unit tests (T-13-07 stale-cleanup in remove, T-13-07 stale-reused override in upgrade, etc.) |
| T-13-08 (AGGRESSIVE-remove UX surprise) | accept (with disclosure) | Plan 13-02 `(reused — managed by agentlinux upgrade/remove)` suffix in list output (3 unit tests asserting wording + visibility without --verbose) |

## Greenfield Invariant

Phase-13 changes are ADDITIVE against the v0.3.0 baseline. Verified by:

- `tests/bats/13-reuse.bats:381` "REUSE: greenfield invariant preserved — bats @test count unchanged from baseline" (raised from 112 → 119 in Plan 13-02 to accommodate the new @tests).
- Phase-12 read-only invariant preserved (detect::run_once is non-mutating).
- INST-02 idempotency invariant preserved (re-running installer on post-installer host fires REUSE-01 + skips useradd).
- Plan-13-02 brownfield E2E smoke captures the full additive contract.

## Acceptance Smoke (foundation for Phase 16 brownfield-AGT-02)

The Plan-13-02 brownfield E2E @test is the canonical foundation for Phase 16's brownfield-AGT-02 milestone-close acceptance gate. Concretely:

- **Pre-populated state:** manual agent user + NOPASSWD-for-apt sudoers + NodeSource Node 22 + claude-code 2.1.98 at canonical path.
- **Assertion shape:** ZERO useradd in installer transcript + [REUSE-01] + [REUSE-03] markers + sentinel with status=reused + (reused — managed) suffix in `list` output.
- **Phase 16 extension:** layer `claude update` against the live CDN on top of this fixture (AGT-02 release-gate equivalent).
- **Phase 14 extension:** add a PATH-MISMATCH variant (claude installed via `npm install -g @anthropic-ai/claude-code` at `~/.npm-global/bin/claude`) to exercise REMEDIATE-04.

## Phase-Close Conclusions

- **All 3 Phase-13 requirements Complete.** REQUIREMENTS.md checkbox-bullets `[x]` + traceability-table rows `Complete` for REUSE-01 + REUSE-02 + REUSE-03.
- **All 4 trust-boundary threats covered.** T-13-05..T-13-08 each have an explicit disposition + mitigation evidence; T-13-07's mitigation is operative across remove + upgrade.
- **Docker matrix GREEN** on both supported Ubuntu LTS versions (22.04 + 24.04) — 128/128 @tests pass.
- **Unit-test suite GREEN** — 128/128 Node-test @tests pass.
- **Greenfield invariant preserved** — additive contract; no regressions in pre-existing @tests.

**GATE: GREEN.** Phase 13 closes; Phase 14 (Remediate) ready to start.

---

*Phase 13 closed: 2026-05-20*
*Plan 13-01 Summary: `13-01-SUMMARY.md`*
*Plan 13-02 Summary: `13-02-SUMMARY.md`*
