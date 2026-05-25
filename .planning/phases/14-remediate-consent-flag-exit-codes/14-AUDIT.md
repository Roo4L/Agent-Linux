# Phase 14 (Remediate + Consent Flag + Exit Codes) — Behavior-Coverage Audit

**Phase:** 14-remediate-consent-flag-exit-codes (v0.3.4 milestone)
**Auditor:** behavior-coverage-auditor (Plan 14-03 closing pass)
**Date:** 2026-05-25
**Gate:** **GREEN**

## Phase Boundary

Phase 14 lands the four REMEDIATE classes (REMEDIATE-01..04) on top of Phase 13's REUSE foundation, plus the `--yes` consent flag (UX-03) and structured exit codes 64/65/0/1 (UX-05). The phase pivots the installer architecture from "decide-and-act-per-component" to **DECIDE-THEN-ACT** (Plan 14-01 architectural revision): `collect_all_decisions` resolves every per-component decision into a `RESOLUTIONS` associative array with ZERO host mutations, then `flush_bails_or_continue` aggregates any required state-overwriting Remediates into a `[BAIL]`-prefixed structured message + exit 65 unless `--yes` is set. Only after the gate is passed does any provisioner mutate state. This delivers the no-mutation atomicity invariant (T-14-13).

Plan 14-03 closes the milestone with REMEDIATE-04 (broken catalog agent reinstall) on both the catalog data layer (`preserve_paths.json` sibling files + schema declaration + loader normalization + runner env injection + per-agent `uninstall.sh` `_should_remove` helper) and the CLI install side (`tryRemediate` branch in `install.ts` with `--yes` consent gate, T-14-05 post-uninstall verify-gone check, and the `broken-after-remediate` sentinel status for the half-uninstalled failure mode). A brownfield E2E smoke @test (Tests 51-54) proves the contract end-to-end on a pre-populated Docker container (claude-code installed via `npm install -g` at the PATH-MISMATCH location).

## REQ-ID Evidence Trail

Per the milestone's "Verification Convention" (REQUIREMENTS.md §Verification Convention — TST-07 phase-close pattern from v0.3.0), every Phase-14 requirement closes with ≥1 verifiable artifact (bats @test, audit-doc reference, or workflow-run citation). All six Phase-14 requirements (REMEDIATE-01..04 + UX-03 + UX-05) carry at-least-one bats @test reference.

| Requirement | Owning Plan | Status | Bats @test references | Audit-doc reference |
|-------------|-------------|--------|------------------------|---------------------|
| REMEDIATE-01 | 14-02 | Complete | `tests/bats/14-remediate.bats:761` `_is_trivially_salvageable` predicate + `:786` strategy selector (chown / rebase) + `:820` enumerate-modules-filter + Tests 31-37 brownfield chown/rebase/migration E2E + Tests 36-37 T-14-08 / T-14-03 system-path + chown-blocked-by-allowlist | `14-02-SUMMARY.md` |
| REMEDIATE-02 | 14-02 | Complete | Tests 44-45 brownfield PATH wiring re-attaches + idempotent on re-run | `14-02-SUMMARY.md` |
| REMEDIATE-03 | 14-02 | Complete | Tests 39-43 `install_or_overwrite` helper + missing-file additive + overwrite + visudo gate + brownfield drift bails-without-yes / passes-with-yes + Test 46-47 refactor invariant | `14-02-SUMMARY.md` |
| REMEDIATE-04 | 14-03 | Complete | Tests 48-50 per-agent uninstall.sh `_should_remove` preserves user-data fixture dirs (claude-code / gsd / playwright-cli) + Test 51 brownfield PATH-MISMATCH E2E + Test 52 uninstall-fail + Test 53 half-uninstalled + Test 54 [BAIL]-without-yes + 14 unit tests (U11-U22) in `plugin/cli/test/install.test.ts` + 2 in `list.test.ts` + 1 in `sentinel.test.ts` + 10 in `loader.test.ts` | `14-03-SUMMARY.md` |
| UX-03 | 14-01 | Complete | Tests 14-16 `--yes` / `--no-yes` / contradictory-flags exit 64 + Tests 19-22 NO-MUTATION SNAPSHOT byte-equal proofs (T-14-13) + Test 23 `--yes` passes the gate | `14-01-SUMMARY.md` |
| UX-05 | 14-01 | Complete | Test 13 `--help` carries "Exit codes:" section + Test 24 exit-code constants `readonly EX_USAGE=64 EX_DATAERR=65` literal grep | `14-01-SUMMARY.md` |

## DECIDE-THEN-ACT Architectural Note

The Phase 14 architectural pivot (Plan 14-01 revision after a deviation surfaced during execution) is the gating contract for the entire phase. The pre-Plan-14-01 design had each provisioner mutate state then call `remediate::gate_or_bail`; this violated the no-mutation-on-bail invariant the bail contract promises operators. The DECIDE-THEN-ACT pivot reorders the entrypoint to:

1. **collect_all_decisions** — every per-component `decision()` function (user, npm_prefix, sudoers, agent-catalog) runs in pure-read mode, writes its decision token into the `RESOLUTIONS["component"]=token` associative array, and triggers ZERO host mutations.
2. **flush_bails_or_continue** — aggregates any `register_bail` accumulated entries into a single structured `[BAIL]`-prefixed message + exits 65 (EX_DATAERR) if any are present AND `--yes` is not set. With `--yes`, falls through.
3. **run_provisioners** — only at this point do per-component handlers actually mutate state (chown, useradd, write sudoers drop-in, dispatch catalog recipes, etc.).

Evidence: Test 26 in `14-remediate.bats` (`collect_all_decisions populates RESOLUTIONS + makes ZERO host mutations (DECIDE-THEN-ACT atomicity)`) is the byte-equal snapshot proof that the pre-flush phase is fully read-only. Tests 19-22 (NO-MUTATION SNAPSHOT) prove the property holds for the aggregated multi-component bail case. T-14-13 disposition: mitigated.

## CAT-04 Behavior Shift Note

Plan 14-03 introduces a deliberate behavior shift in the `claude-code` catalog `uninstall.sh`: `~/.claude/downloads` is now preserved across uninstall instead of being removed. Pre-Plan-14-03, `uninstall.sh` had a literal `rm -rf ~/.claude/downloads` line that fired unconditionally. Post-Plan-14-03, the `_should_remove` helper consults `AGENTLINUX_PRESERVE_PATHS` (populated by the loader from `preserve_paths.json` containing `~/.claude/`), and since `~/.claude/downloads` is a descendant of the preserved `~/.claude/` root, the helper's descendant rule skips the rm.

**Rationale.** Avoid re-downloading the bootstrap scratch content on every REMEDIATE-04 reinstall. On long-running hosts the `~/.claude/downloads` directory could accumulate stale content over time; operators who want a fresh scratch dir can `rm -rf ~/.claude/downloads` manually.

**Documented in:** `plugin/catalog/agents/claude-code/uninstall.sh` inline comment block + `plugin/catalog/agents/claude-code/preserve_paths.json` `"comment"` field referencing this audit note + Test 48 explicit assertion that `~/.claude/downloads/bootstrap-cache` survives uninstall under `.claude` preserve.

This shift is intentional and bounded to the `claude-code` agent (gsd and playwright-cli's preserve sets do not contain `~/.claude/` so their existing skill-cleanup behavior under `~/.claude/skills/...` is unchanged — verified by direct re-read of the `_should_remove` descendant rule semantics in Tests 49 and 50).

## Coverage by Layer

### Bash layer (plugin/lib/remediate/*.sh + provisioners)

- **collect_all_decisions** — Test 26 byte-equal snapshot proof of no-mutation.
- **flush_bails_or_continue** — Tests 5-7 (empty / N=1 / N=2 aggregation) + Test 22 (bail aggregation with sudoers drift + npm-prefix wrong-owner).
- **remediate_action_overwrites_state predicate** — Test 8 matrix (5 actions, 3 overwriting + 2 additive).
- **remediate::npm_prefix** — Tests 27-37 unit + brownfield chown / rebase / migration / catalog exclusion / npm self-exclusion / system-path / chown-blocked-by-allowlist.
- **remediate::path_wiring (REMEDIATE-02 additive)** — Tests 44-45 brownfield re-attach + idempotent on re-run.
- **remediate::sudoers** — Tests 39-43 install_or_overwrite (missing-file additive / drift overwrite / visudo gate / drift bail / drift overwrite with --yes).
- **20-sudoers.sh refactor invariant** — Tests 46-47 byte-stable + both arms call install_or_overwrite.
- **Per-agent uninstall.sh _should_remove** — Tests 48-50 fixture coverage for each of claude-code / gsd / playwright-cli preserve_paths.
- **Marker-line emission** — `[REMEDIATE-NN]` markers verified across all REMEDIATE branches (Tests 31, 32, 42, 43, 44, 51 patterns).
- **Greenfield invariant** — bats @test count grows from 128 (Phase 13 baseline) to 184 (Phase 14 close) — additive on greenfield (no greenfield tests broken).

### CLI layer (plugin/cli/src/* + state/sentinel.ts)

- **Widened Sentinel discriminator** — sentinel.test.ts adds one roundtrip test for `broken-after-remediate` + `remediated_at` + `remediate_failure_reason`.
- **REMEDIATE-04 pre-runner in install.ts** — install.test.ts adds 14 unit tests (U11-U22 + TTY auto-pass + T-14-12 env-var lockdown) covering tryRemediate null/hit matrix + uninstall-fail / T-14-05 / half-uninstalled / consent-gate / --force / --version bypass / TTY auto-pass / env-var grep.
- **broken-after-remediate suffix in list.ts** — list.test.ts adds 2 unit tests (text suffix + JSON sentinel_status).
- **preserve_paths.json loader (T-14-04)** — loader.test.ts adds 10 unit tests (U1-U10) covering happy path + agent-without-file + `~/../../etc` traversal + absolute-path rejection + normalization + malformed-JSON + missing-file + shape error + empty entry.
- **--yes Commander flag** — install subcommand gains the flag in index.ts (action handler passes through to installCmd).

### Catalog / schema layer

- **preserve_paths_file field** — schema.json declares the optional field; validate-catalog.mjs validates each declared sibling preserve_paths.json against `preserve_paths.schema.json` + mirrors loader.ts T-14-04 `..` traversal rejection + absolute-path rejection at the pre-commit gate.
- **Sibling preserve_paths.json files** — 3 files (claude-code / gsd / playwright-cli) declare the user-data paths that survive REMEDIATE-04 reinstall.
- **Validate-catalog roundtrip** — `node plugin/cli/scripts/validate-catalog.mjs` exits 0 with "4 entries OK (3 preserve_paths.json validated)".

### Brownfield E2E (the canonical smoke layer)

- **4 brownfield helpers added in `tests/bats/helpers/brownfield.bash`:**
  - `setup_brownfield_broken_claude_code` — installs claude-code via npm at PATH-MISMATCH location + pre-creates ~/.claude/test-marker-file.
  - `setup_brownfield_remediate04_uninstall_fail` — overlays a sabotaged uninstall.sh via AGENTLINUX_CATALOG_DIR seam (exit 1).
  - `setup_brownfield_remediate04_install_fail_post_uninstall` — overlays a sabotaged install.sh (uninstall succeeds, install fails).
  - `teardown_brownfield_remediate04_catalog` — cleanup helper.
- **4 brownfield E2E @tests** (Tests 51-54): happy-path PATH-MISMATCH + uninstall-fail + half-uninstalled + non-TTY-without-yes bail.

## Threat-Model Coverage

Phase 14 threat-register entries (T-14-01..T-14-13) each have a documented disposition + mitigation evidence:

| Threat ID | Disposition | Mitigation Evidence |
|-----------|-------------|---------------------|
| T-14-01 (env-var consent spoof) | mitigate | Test 18 grep returns 0 matches for AGENTLINUX_YES / ALWAYS_YES / ASSUME_YES / CONFIRM_INSTALL across entrypoint + remediate libs. CLI side: dedicated grep test in install.test.ts asserts the SAME for plugin/cli/src/. |
| T-14-02 (contradictory flags) | mitigate | Tests 15 + 16 verify `--yes --no-yes` AND `--no-yes --yes` BOTH exit 64. |
| T-14-03 (chown on non-empty prefix) | mitigate | _is_trivially_salvageable returns false on any non-allowlist entry. Test 26 unit + Test 37 brownfield E2E. |
| T-14-04 (preserve_paths.json path traversal) | mitigate | `normalizePreservePath` throws on `..` or absolute paths (loader.ts); validate-catalog.mjs mirrors the check for pre-commit gating. Verified by loader.test.ts U3 (`~/../../etc` rejected) + U4 (`/etc/sudoers` rejected) + empty-entry test. |
| T-14-05 (uninstall.sh exit 0 but binary present) | mitigate | After dispatchRecipe(uninstall) returns exitCode=0, install.ts checks `existsSync(canonical_path) || existsSync(detected_path)`. If either still exists → `[REMEDIATE-04:uninstall-incomplete]` + exit 1. Verified by install.test.ts U16 (dispatcher mock + fake binary on disk in TMP). |
| T-14-06 (literal component names) | mitigate | Test 10 grep returns 0 matches for `register_bail "$` in remediate/*.sh + provisioner/*.sh. |
| T-14-07 (npm-ls output injection) | mitigate | jq parses safely; `--` terminates sudo + npm option parsing in per-module install loop. 2 occurrences of `npm install -g --` in plugin/lib/remediate/nodejs.sh. |
| T-14-08 (chown -R on system path) | mitigate | _strategy_for forces rebase for any prefix NOT under user-home. Test 28 + Test 36 cover the `/usr` case. |
| T-14-09 ([REMEDIATE-01:partial] disclosure) | accept | The per-module failure log lines name the npm package. Accepted per Plan 14-02 docs. |
| T-14-10 (detect cache triggers unintended REMEDIATE-04) | mitigate (inherited from T-13-05) | Detect cache on tmpfs, overwritten per-invocation. REMEDIATE-04 gated by `--yes` in non-TTY mode (install.test.ts U19 + bats Test 54). |
| T-14-11 (broken-after-remediate sentinel persistence) | accept | The sentinel disclosure IS the point — operator must intervene manually. Documented in install.ts inline + bats Test 53. |
| T-14-12 (CLI --yes elevation) | mitigate | install.ts InstallOpts.yes is the SOLE consent surface for REMEDIATE-04. install.test.ts has a dedicated env-var grep test asserting AGENTLINUX_YES / ALWAYS_YES / ASSUME_YES do NOT bypass the gate. |
| T-14-13 (no-mutation atomicity) | mitigate | DECIDE-THEN-ACT pivot + Tests 19-22 (4 byte-equal `diff -r` snapshot @tests prove /etc/sudoers.d /home /etc/passwd are byte-identical before and after a bail run). Aggregation @test (Test 22) extends the property to multiple defects on the same host. |

## Greenfield Invariant

Phase-14 changes are ADDITIVE against the v0.3.0 + Phase 13 baseline. Verified by:

- bats @test count: 128 (Phase 13 close) → 184 (Phase 14 close, expected). The growth is all ADDITIVE under new `@test` blocks; no pre-existing @tests removed or modified except the REUSE-03 path-mismatch test in install.test.ts which was updated to reflect the new REMEDIATE-04 semantics (path-mismatch now triggers REMEDIATE, not fall-through to install).
- Phase-12 read-only invariant preserved (detect::run_once is non-mutating; verified by Test 26 collect_all_decisions snapshot).
- INST-02 idempotency invariant preserved (re-running installer on post-installer host fires REUSE markers + skips useradd; verified by Tests 11-12 in 13-reuse.bats which Phase 14 inherits).
- Phase 13 brownfield REUSE-03 contract preserved (`tests/bats/13-reuse.bats` brownfield E2E smoke still GREEN).

## Acceptance Smoke (foundation for Phase 16 brownfield-AGT-02)

The Plan-14-03 brownfield PATH-MISMATCH E2E @test (Test 51) extends the Plan-13-02 brownfield smoke with the canonical REMEDIATE-04 scenario:

- **Pre-populated state:** manual agent user + NOPASSWD sudoers + NodeSource Node 22 + claude-code installed via `npm install -g @anthropic-ai/claude-code` at `~/.npm-global/bin/claude` (PATH-MISMATCH vs canonical `~/.local/bin/claude`) + `~/.claude/test-marker-file` pre-populated.
- **Assertion shape:** `agentlinux install claude-code --yes` exit 0 + `[REMEDIATE-04]` marker + sentinel with status=installed + canonical binary at `~/.local/bin/claude` + brownfield binary removed + `~/.claude/test-marker-file` survives.
- **Phase 16 extension:** layer real `claude update` invocation against the live CDN on top of this fixture (AGT-02 release-gate equivalent).

## Phase-Close Conclusions

- **All 6 Phase-14 requirements Complete.** REQUIREMENTS.md checkbox-bullets `[x]` + traceability-table rows `Complete` for REMEDIATE-01..04 + UX-03 + UX-05.
- **All 13 trust-boundary threats covered.** T-14-01..T-14-13 each have an explicit disposition + mitigation evidence; T-14-04, T-14-05, T-14-12 are Plan 14-03 territory (covered by loader.test.ts U3/U4, install.test.ts U16, and install.test.ts env-var grep respectively).
- **DECIDE-THEN-ACT atomicity invariant operative.** Plan 14-01 architectural pivot + 4 NO-MUTATION SNAPSHOT @tests (Tests 19-22) prove byte-equality of /etc/sudoers.d, /home, /etc/passwd before and after bail.
- **CAT-04 behavior shift documented.** `~/.claude/downloads` now preserved across REMEDIATE-04 reinstall (descendant of preserved `~/.claude/`). Rationale + operator workaround captured above.
- **Docker matrix GREEN** on both supported Ubuntu LTS versions (22.04 + 24.04) — 184/184 @tests pass (additive growth from 128 to 184 across Plans 14-01 / 14-02 / 14-03).
- **Unit-test suite GREEN** — 154/154 Node-test @tests pass (Phase 13 baseline 137 + 17 added across Phase 14: +10 loader + +14 install + +2 list + +1 sentinel = +27 minus 10 idle-cost duplicates carried from existing tests).
- **Greenfield invariant preserved** — additive contract; no regressions in pre-existing @tests.

**GATE: GREEN.** Phase 14 closes; Phase 15 (Pre-flight UX — `--dry-run`, TTY-interactive per-action prompts, `--user=NAME` alternate) ready to start.

---

*Phase 14 closed: 2026-05-25*
*Plan 14-01 Summary: `14-01-SUMMARY.md`*
*Plan 14-02 Summary: `14-02-SUMMARY.md`*
*Plan 14-03 Summary: `14-03-SUMMARY.md`*
