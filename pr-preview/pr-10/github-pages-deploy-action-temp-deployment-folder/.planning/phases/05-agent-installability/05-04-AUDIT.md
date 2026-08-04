---
auditor: behavior-coverage-auditor
phase: 05-agent-installability
plan: 04
date: 2026-04-19
result: GREEN
dispatch: inline-rubric
rubric_source: .claude/agents/behavior-coverage-auditor.md
scope: Phase 5 — AGT-01, AGT-02, AGT-02b, AGT-03, AGT-04, AGT-05
---

# Phase 5 Close — behavior-coverage-auditor TST-07 Gate

**Rubric application note:** Per `.claude/skills/review/SKILL.md` §"Relation to
TST-07", the `behavior-coverage-auditor` is the unconditional phase-close gate.
The project's convention since Plan 02-04 has been to apply review-subagent
rubrics inline when the Task-tool subagent dispatch is unavailable in the
executor environment (ADR-010 + 02-05-SUMMARY / 04-07-SUMMARY precedent). The
auditor's rubric is codified in `.claude/agents/behavior-coverage-auditor.md`
and exercised verbatim below: greps over `tests/bats/*.bats` for @test-name
citations of every Phase 5 requirement ID, classifies each requirement as
covered / uncovered, and emits a final `TST-07 gate` verdict.

## Method

1. Extracted the Phase 5 requirement IDs from `.planning/REQUIREMENTS.md`:
   AGT-01, AGT-02, AGT-02b, AGT-03, AGT-04, AGT-05 (six IDs total).
2. Greped `tests/bats/*.bats` for `^@test "AGT-XX[: ]` for each ID.
3. For each hit, read the @test body to confirm the assertion exercises the
   requirement's observable behavior (not a name collision).
4. Cross-checked that the catalog's pinned versions are read from
   `/opt/agentlinux/catalog/0.3.0/catalog.json` via `jq` (no hardcoded
   versions in @test bodies — required per ADR-011).

## Coverage Table

| Req ID | Covered In | @test Name | Assertion Summary |
|--------|------------|-----------|-------------------|
| AGT-01 | `tests/bats/50-agents.bats:90` | `AGT-01: claude --version exits 0 in every invocation mode` | Loops `${INVOKE_MODES[@]}` (interactive, ssh, cron, systemd_user, sudo_u, sudo_u_i); exit 0 + semver regex `[0-9]+\.[0-9]+\.[0-9]+`; `SKIP_SYSTEMD_UNAVAILABLE` gate honored. |
| AGT-01 | `tests/bats/50-agents.bats:114` | `AGT-01: get-shit-done-cc --help exits 0 in every invocation mode` | Loops six modes on `get-shit-done-cc --help` (no `--version` flag exists); exit 0 per mode. |
| AGT-01 | `tests/bats/50-agents.bats:131` | `AGT-01: npx playwright --version exits 0 in every invocation mode` | Loops six modes on `npx --yes playwright --version`; exit 0 per mode. |
| AGT-02 | `tests/bats/51-agt02-release-gate.bats:52` | `AGT-02 (release-gate): claude update exits 0 with zero EACCES/permission-denied lines` | Live `claude update` against Anthropic CDN; transcript captured via `mktemp` under `timeout 120s sudo -u agent -H bash --login -c`; `assert_exit_zero` + `assert_no_eacces` (the permission invariant v0.3.0 exists to prove) + `sort -V` post-update monotonicity. |
| AGT-02b | `tests/bats/50-agents.bats:150` | `AGT-02b: claude --version returns exactly pinned_version from catalog.json` | `jq -r '.agents[] | select(.id=="claude-code") | .pinned_version' /opt/agentlinux/catalog/0.3.0/catalog.json` → substring match in `claude --version` output. No hardcoding (ADR-011 compliance). |
| AGT-03 | `tests/bats/50-agents.bats:181` | `AGT-03: claude --help exits 0 and prints no error strings` | `claude --help` exits 0 + no failure-prefix patterns (`error:`, `Error:`, `ERROR:`, `Traceback`, `permission denied`, `EACCES`); bare-word "error" excluded to avoid noun-in-help-text false positives per upstream CLI shape (e.g. `--mcp-debug` description). |
| AGT-04 | `tests/bats/50-agents.bats:201` | `AGT-04: get-shit-done-cc --help banner reports pinned version` | `jq` the pin → `get-shit-done-cc --help` banner contains `v${pinned}` substring. (Package has no `--version` flag — banner grep IS the version lock.) |
| AGT-05 | `tests/bats/50-agents.bats:219` | `AGT-05: npx playwright --version exits 0 with pinned version string` | `jq` the pin → `npx playwright --version` contains pinned. |
| AGT-05 | `tests/bats/50-agents.bats:237` | `AGT-05: chromium cached under ~agent/.cache/ms-playwright (no sudo/EACCES)` | `find ~agent/.cache/ms-playwright -maxdepth 1 -type d -name "chromium-*"` returns non-empty + `stat -c '%U'` owner == `agent` (ADR-004 keystone). |
| AGT-05 | `tests/bats/50-agents.bats:265` | `AGT-05: re-install playwright is idempotent (CLI-03 invariant on real agent)` | Second `agentlinux install playwright` exits 0 + prints `already installed` (does NOT re-download chromium). |

## Per-Requirement Verdict

| Req ID | Hits | Verdict |
|--------|------|---------|
| AGT-01 | 3 | COVERED |
| AGT-02 | 1 | COVERED |
| AGT-02b | 1 | COVERED |
| AGT-03 | 1 | COVERED |
| AGT-04 | 1 | COVERED |
| AGT-05 | 3 | COVERED |

**Total @tests citing Phase 5 req IDs:** 10 (9 in 50-agents.bats + 1 in 51-agt02-release-gate.bats)

## Ancillary Findings

- **No hardcoded versions in @test bodies.** `jq -r '.agents[] | select(.id=="<id>") | .pinned_version' "$CATALOG"` in all three version-lock @tests (AGT-02b, AGT-04, AGT-05-version) — a catalog version bump updates assertions without editing the test file. Matches ADR-011 intent.
- **Six-mode matrix fully exercised for AGT-01.** All three agents loop `${INVOKE_MODES[@]}` (interactive, ssh, cron, systemd_user, sudo_u, sudo_u_i) — the Phase 2 BHV-02..06 matrix is now proven for real agent binaries, not just node/npm.
- **ADR-004 ownership invariant enforced at the test layer.** AGT-05's `stat -c '%U'` owner check on chromium-* dir catches regressions where the Playwright install-deps sudo path might accidentally root-own the cache.
- **Destructive vs non-destructive separation holds.** AGT-02 (the only destructive Phase 5 test — runs real `claude update` against live CDN) lives in `51-agt02-release-gate.bats` so Phase 6's TST-05 release-gate can select `bats tests/bats/51-*.bats` separately from the non-destructive Phase 5 set. 50-agents.bats contains zero destructive operations (verified: `! grep -Fq 'claude update' tests/bats/50-agents.bats` returns exit 0).
- **40-*.bats INST-04 --purge recovery double-hooked.** 50-agents.bats setup_file recovers (a) the agentlinux CLI symlink via re-running `plugin/bin/agentlinux-install`, (b) the SSH keypair authorization from `/root/.ssh/id_ed25519.pub` → `/home/agent/.ssh/authorized_keys` (wiped by `userdel -r agent` during 40-*.bats --purge). Mirrors the 51-*.bats precedent (05-01 SUMMARY deviation #2).

## End-to-End Verification

| Check | Command | Result |
|-------|---------|--------|
| Docker smoke Ubuntu 24.04 | `./tests/docker/run.sh ubuntu-24.04` | 66/66 bats PASS |
| Docker smoke Ubuntu 22.04 | `./tests/docker/run.sh ubuntu-22.04` | 66/66 bats PASS |
| Harness meta-tests | `bash tests/harness/run.sh` | 104/104 PASS |
| Plan automated verify chain | (18 greps incl. @test counts + anti-pattern guards) | PASS |

Phase 5 suite composition: 49 Phase 1-4 @tests + 7 Phase 5.1 @tests (INST-06/BHV-07) + 9 Phase 5-04 @tests (AGT-01×3 + AGT-02b + AGT-03 + AGT-04 + AGT-05×3) + 1 Phase 5-01 @test (AGT-02 release-gate) = 66 @tests.

## Verdict

Every Phase 5 requirement (AGT-01, AGT-02, AGT-02b, AGT-03, AGT-04, AGT-05) has
at least one bats `@test` citing it in `tests/bats/*.bats`. The full suite is
green end-to-end on both Ubuntu 22.04 + 24.04 Docker matrix entries. The
behavior-test-contract invariant — every observable behavior in REQUIREMENTS.md
has a test that fails if the behavior breaks — is honored.

---

**TST-07 gate: GREEN**
