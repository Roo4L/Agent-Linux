---
phase: 5
slug: agent-installability
verified_date: 2026-04-19
status: human_needed
must_haves_verified: 26/26
phase_requirements_covered: 6/6
tst07_gate: GREEN
bats_tests_ubuntu_22_04: unverified-in-verifier-env
bats_tests_ubuntu_24_04: unverified-in-verifier-env
bats_test_count_on_disk: 66/66
human_verification:
  - test: "Run full Docker matrix on Ubuntu 22.04"
    expected: "./tests/docker/run.sh ubuntu-22.04 → 66/66 bats green including AGT-02 live claude update"
    why_human: "Docker build + ~8 min bats run (incl. ~281 MB chromium download + live claude.ai CDN fetch) exceeds verifier wall-time budget; SUMMARY claims 66/66 but re-run is a release-gate obligation per plan and ADR-011"
  - test: "Run full Docker matrix on Ubuntu 24.04"
    expected: "./tests/docker/run.sh ubuntu-24.04 → 66/66 bats green"
    why_human: "Same as above; matrix parity check against 22.04; Plan 05-02 SUMMARY documents a prior AGT-02 flake on 24.04 (exit 124 timeout-SIGTERM against live Anthropic CDN) that cleared on retry — reproduces environmental sensitivity of AGT-02"
  - test: "Confirm AGT-02 release-gate transcript has zero EACCES against live Anthropic CDN"
    expected: "transcript at /tmp/agt02-claude-update.*.log (kept only on failure) shows post-update version >= 2.1.98; assert_no_eacces passes"
    why_human: "Requires real network + real Anthropic CDN; destructive (mutates claude binary in container); verifier cannot spin up live-network container"
---

# Phase 5: Agent Installability — Verification Report

**Phase Goal (ROADMAP §Phase 5):** Each of the three catalog agents (claude-code, gsd, playwright) can be installed via `agentlinux install <name>` and runs correctly for the agent user across all six BHV invocation modes. AGT-02 (Claude Code self-updates without sudo/EACCES) passes as the canonical acceptance test. AGT-02b verifies the stability-first pin mechanism produces exactly `pinned_version` on disk.

**Verified:** 2026-04-19
**Status:** human_needed (all static evidence GREEN; Docker matrix re-run needed for release-gate confirmation of live `claude update` and live chromium download)
**Re-verification:** No — initial verification

---

## Goal Achievement — ROADMAP Success Criteria (7 criteria, 6 req IDs)

| # | Success Criterion | Status | Evidence |
|---|-------------------|--------|----------|
| SC-1 | `claude --version` succeeds in all six INVOKE_MODES (AGT-01) | PASS (static) | `tests/bats/50-agents.bats:90` — `@test "AGT-01: claude --version exits 0 in every invocation mode"` — loops `${INVOKE_MODES[@]}` + semver regex `[0-9]+\.[0-9]+\.[0-9]+` + SKIP_SYSTEMD_UNAVAILABLE honored. Two sister @tests cover `get-shit-done-cc --help` (L114) and `npx --yes playwright --version` (L131) in all six modes. |
| SC-2 | `claude update` unprivileged, no EACCES, monotonic (AGT-02) | PASS (static + network-dependent) | `tests/bats/51-agt02-release-gate.bats:52` — `@test "AGT-02 (release-gate): claude update exits 0 with zero EACCES/permission-denied lines"` — `timeout 120s sudo -u agent -H bash --login -c 'claude update'` + mktemp transcript + `assert_no_eacces` + `sort -V` monotonicity. Plan 05-01 SUMMARY documents observed 2.1.114 ≥ pinned 2.1.98 on both Ubuntu images. |
| SC-3 | `claude --version == pinned_version` (AGT-02b) | PASS | `tests/bats/50-agents.bats:150` — `@test "AGT-02b: claude --version returns exactly pinned_version from catalog.json"` — `jq -r` reads pin from `/opt/agentlinux/catalog/0.3.0/catalog.json` (no hardcoding, ADR-011 compliant) + substring match. In-recipe: `plugin/catalog/agents/claude-code/install.sh:47` also fails fast on drift via `grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"`. |
| SC-4 | `claude diagnostic` clean (AGT-03) | PASS | `tests/bats/50-agents.bats:181` — `@test "AGT-03: claude --help exits 0 and prints no error strings"` — `claude doctor` requires stdin (GH issue claude-code#26487); `claude --help` is the scriptable substitute; failure-prefix regex `error:|Error:|ERROR:|Traceback|traceback \(` + case-insensitive `permission denied|EACCES` (bare-word `error` excluded to avoid false positive on upstream `--mcp-debug` description). |
| SC-5 | `gsd --version` or equivalent (AGT-04) | PASS | `tests/bats/50-agents.bats:201` — `@test "AGT-04: get-shit-done-cc --help banner reports pinned version"` — get-shit-done-cc has NO `--version` flag (verified via `npm view get-shit-done-cc bin` — only `get-shit-done-cc` → `bin/install.js`); banner-grep against `--help` output is the version-lock mechanism; catalog-driven pin lookup via jq. |
| SC-6 | `playwright --version` + browser install, no EACCES (AGT-05) | PASS (static; network-dependent for live browser download) | Three @tests in `tests/bats/50-agents.bats`: L219 (version pinned match), L237 (chromium cache exists under `~agent/.cache/ms-playwright/chromium-*` AND `stat -c '%U'` owner == `agent` — ADR-004 keystone), L265 (idempotent re-install — CLI-03 invariant on real agent). |
| SC-7 | Docker bats matrix covers AGT-01..05 + AGT-02b; AGT-02 release-gate tagged | PASS (static) | `tests/bats/50-agents.bats` (9 @tests, non-destructive) + `tests/bats/51-agt02-release-gate.bats` (1 @test, destructive, `51-*.bats` glob selection for Phase 6 TST-05). Total Phase 5 additions: +10 @tests over Phase 5.1 baseline (56→66). |

**Score:** 7/7 ROADMAP success criteria verified statically. SC-2 and SC-6 have network-dependent runtime components flagged for human verification.

### Observable Truths (Plan-level must_haves aggregated across 4 plans)

| # | Truth Source | Truth | Status | Evidence |
|---|--------------|-------|--------|----------|
| 1 | Plan 05-01 | `agentlinux install claude-code` lands `/home/agent/.local/bin/claude` owned agent:agent reporting exactly 2.1.98 (AGT-02b) | PASS | install.sh lines 23-53 (`:?` guards + curl\|bash-s-PINNED + PIPESTATUS + binary-exists check + version-lock grep). Plan 05-01 SUMMARY documents live Docker observation: `claude --version` == "2.1.98 (Claude Code)". |
| 2 | Plan 05-01 | claude-code install recipe fails fast on missing PINNED_VERSION or version mismatch | PASS | `: "${AGENTLINUX_PINNED_VERSION:?...}"` L23; `grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"` L47 with exit 1 on mismatch. |
| 3 | Plan 05-01 | `claude update` as agent user exits 0 with zero EACCES/permission-denied and monotonic version (AGT-02 release gate) | PASS (static) | 51-*.bats:68 `timeout 120s sudo -u agent -H bash --login -c 'claude update' >${transcript} 2>&1` + L71 `assert_exit_zero` + L74 `assert_no_eacces "AGT-02" "$transcript"` + L87-88 `sort -V` monotonicity. Plan SUMMARY documents 2.1.114 ≥ 2.1.98 observed. |
| 4 | Plan 05-01 | Release-gate bats at `tests/bats/51-agt02-release-gate.bats` for Phase 6 TST-05 glob | PASS | File exists at exactly that path. Phase 6 can select via `bats tests/bats/51-*.bats`. |
| 5 | Plan 05-01 | `agentlinux remove claude-code` deletes binary, share, ~/.claude/downloads; preserves user config at ~/.claude/ | PASS | uninstall.sh lines 16-18 (`rm -f ~/.local/bin/claude` + `rm -rf ~/.local/share/claude` + `rm -rf ~/.claude/downloads`); grep confirms NO `rm -rf "${AGENTLINUX_AGENT_HOME}/.claude"` (preserves user data). |
| 6 | Plan 05-02 | `agentlinux install gsd` lands `/home/agent/.npm-global/bin/get-shit-done-cc`; `--help` banner contains v1.37.1 (AGT-04) | PASS | install.sh lines 20-50 (fail-fast PINNED guard + `npm install -g get-shit-done-cc@$PINNED --omit=dev --no-fund --no-audit` + `command -v` PATH-resolve + banner-grep). |
| 7 | Plan 05-02 | gsd recipe fails fast on missing PINNED_VERSION or missing PATH resolution | PASS | L20 `:?` guard + L36-38 `command -v` absence triggers exit 1. |
| 8 | Plan 05-02 | gsd recipe fails fast on banner-grep mismatch | PASS | L44-48 `banner \| grep -q -F "v${PINNED}"` with exit 1 on mismatch. |
| 9 | Plan 05-02 | gsd recipe never invokes `sudo npm install -g` (CLAUDE.md rule #1) | PASS | Non-comment grep confirms zero `sudo npm install` in plugin/catalog/; only hits are explanatory comments in `plugin/provisioner/10-agent-user.sh` documenting the anti-pattern. |
| 10 | Plan 05-02 | `agentlinux remove gsd` calls `npm uninstall -g get-shit-done-cc`; `command -v get-shit-done-cc` returns non-zero after | PASS | uninstall.sh lines 10-16: `npm uninstall -g get-shit-done-cc` + `command -v` absence check with exit 1 if still present. |
| 11 | Plan 05-03 | `agentlinux install playwright` installs playwright@1.59.1 + downloads chromium + apt deps via sudo, no EACCES (AGT-05) | PASS (static; network-dependent) | install.sh lines 27-76: PINNED+HOME guards + `npm install -g playwright@$PINNED` + `command -v` + `--version` pin check + `npx --yes playwright install --with-deps chromium` + cache-dir + chromium-* dir check. Plan 05-03 declares observed live Docker install complete. |
| 12 | Plan 05-03 | Chromium under `/home/agent/.cache/ms-playwright/chromium-*`, owned agent:agent | PASS | install.sh:73 `find "$cache_dir" -maxdepth 1 -type d -name 'chromium-*' \| head -1` in-recipe check. 50-*.bats:237 `@test` adds `stat -c '%U'` owner-is-agent assertion (ADR-004 keystone). |
| 13 | Plan 05-03 | apt deps install uses sudo transparently via ADR-012 NOPASSWD drop-in | PASS | install.sh:63 `npx --yes playwright install --with-deps chromium` — internal playwright-core `registry/dependencies.ts` auto-prepends sudo when getuid != 0; ADR-012 `/etc/sudoers.d/agentlinux` (Phase 5.1) makes it non-interactive; no explicit `sudo` command in recipe body (`! grep -Eq '^[^#]*sudo[[:space:]]'` passes). |
| 14 | Plan 05-03 | playwright recipe fails fast on PINNED_VERSION/AGENT_HOME unset, PATH miss, version mismatch, or missing chromium-* dir | PASS | L27-28 `:?` guards; L38-41 PATH-resolve exit 1; L46-50 version-pin exit 1; L67-70 cache-dir exit 1; L73-76 chromium-* exit 1. |
| 15 | Plan 05-03 | `agentlinux remove playwright` calls `npm uninstall -g playwright` + `rm -rf ~agent/.cache/ms-playwright`; `command -v playwright` returns non-zero | PASS | uninstall.sh:9-20: npm uninstall -g + `rm -rf "${AGENTLINUX_AGENT_HOME}/.cache/ms-playwright"` + `command -v` absence check. |
| 16 | Plan 05-04 | `tests/bats/50-agents.bats` exists with ≥1 @test citing each of AGT-01, AGT-02b, AGT-03, AGT-04, AGT-05 | PASS | File exists (272 lines). grep confirms: AGT-01 ×3, AGT-02b ×1, AGT-03 ×1, AGT-04 ×1, AGT-05 ×3 = 9 total. |
| 17 | Plan 05-04 | AGT-01 loops all six INVOKE_MODES for claude, get-shit-done-cc, npx playwright with exit 0 + non-empty version | PASS | Three @tests at L90/L114/L131 loop `${INVOKE_MODES[@]}`; claude version adds semver regex check to defend against empty-output false-pass. |
| 18 | Plan 05-04 | AGT-02b asserts claude --version contains catalog pinned_version (substring match, not semver range) | PASS | 50-*.bats:150-163 — jq reads pin + `grep -q -F -- "$pinned"` substring match. |
| 19 | Plan 05-04 | AGT-03 asserts claude --help exits 0 with no error/traceback/permission-denied/EACCES | PASS | 50-*.bats:181-192 — failure-prefix regex (colon-anchored) + case-insensitive permission-denied/EACCES check. |
| 20 | Plan 05-04 | AGT-04 asserts get-shit-done-cc --help banner contains v1.37.1 substring | PASS | 50-*.bats:201-213 — jq-driven; grep -F banner match. |
| 21 | Plan 05-04 | AGT-05 asserts npx playwright --version matches 1.59.1; chromium-* dir exists owned by agent; re-install idempotent | PASS | Three @tests at L219/L237/L265 — version substring match, find + `stat -c '%U' == agent`, re-install prints "already installed". |
| 22 | Plan 05-04 | setup_file installs all three agents once; teardown_file cleans | PASS | 50-*.bats:32-70 (setup_file re-installs CLI symlink + SSH authorized_keys + three `agentlinux install <id>`); L72-81 (teardown_file with agentlinux-symlink guard). |
| 23 | Plan 05-04 | 50-*.bats (non-destructive) + 51-*.bats (destructive AGT-02) clean separation | PASS | `! grep -Fq 'claude update' tests/bats/50-agents.bats` exits 0; destructive `claude update` confined to 51-*.bats. |
| 24 | Plan 05-04 | Six-mode matrix + catalog-driven pin lookup + no hardcoded versions in @test bodies | PASS | `grep -Fq 'jq -r' tests/bats/50-agents.bats` passes; catalog path `/opt/agentlinux/catalog/0.3.0/catalog.json` used consistently (ADR-011 compliant). |
| 25 | Plan 05-04 | behavior-coverage-auditor (TST-07 phase-close gate) report GREEN | PASS | `.planning/phases/05-agent-installability/05-04-AUDIT.md` frontmatter `result: GREEN`; final line `TST-07 gate: GREEN`; coverage table confirms 6/6 Phase 5 req IDs covered across two bats files. |
| 26 | Plan 05-04 | 10 @tests across two files (9 non-destructive in 50-*.bats + 1 destructive in 51-*.bats) citing AGT-XX | PASS | Direct grep confirms: `grep -c ^@test tests/bats/50-agents.bats` = 9; `grep -c ^@test tests/bats/51-agt02-release-gate.bats` = 1. Total 10. |

**Score:** 26/26 aggregated must-haves verified statically.

### Required Artifacts (3-level verification: exists, substantive, wired)

| Artifact | Expected | Exists | Substantive | Wired | Status |
|----------|----------|--------|-------------|-------|--------|
| `plugin/catalog/agents/claude-code/install.sh` | Real native-installer body (53 lines; curl\|bash-s-PINNED + PIPESTATUS + AGT-02b in-recipe grep) | YES (53 lines, executable, `#!/usr/bin/env bash` + `set -euo pipefail`) | YES (all 17 plan-required greps pass: fail-fast guards, PIPESTATUS, binary-exists, grep -F pin, etc.) | YES (runner.ts dispatches; bats setup_file calls `agentlinux install claude-code` which invokes this recipe) | VERIFIED |
| `plugin/catalog/agents/claude-code/uninstall.sh` | Symmetric inverse preserving ~/.claude/ | YES (24 lines) | YES (rm binary + share + downloads; zero `rm -rf ~/.claude"` literal) | YES (runner.ts dispatches on `agentlinux remove claude-code`) | VERIFIED |
| `plugin/catalog/agents/gsd/install.sh` | Real npm-global body (50 lines; `npm install -g get-shit-done-cc@$PINNED` + PATH-resolve + banner-grep) | YES (50 lines) | YES (all plan-required greps pass; no `gsd` word-boundary binary invocations; `--omit=dev --no-fund --no-audit` present) | YES (runner.ts dispatches on `agentlinux install gsd`) | VERIFIED |
| `plugin/catalog/agents/gsd/uninstall.sh` | Symmetric inverse (`npm uninstall -g get-shit-done-cc` + command-v absence check) | YES (18 lines) | YES | YES | VERIFIED |
| `plugin/catalog/agents/playwright/install.sh` | Real 3-part body (npm install + version-lock + npx install --with-deps chromium + cache verify) | YES (78 lines) | YES (all plan-required greps pass; zero firefox/webkit; no explicit sudo in non-comment lines) | YES (runner.ts dispatches on `agentlinux install playwright`) | VERIFIED |
| `plugin/catalog/agents/playwright/uninstall.sh` | Symmetric inverse (`npm uninstall -g` + cache rm -rf + command-v absence) | YES (22 lines) | YES | YES | VERIFIED |
| `tests/bats/50-agents.bats` | 9 non-destructive @tests (AGT-01 ×3 + AGT-02b + AGT-03 + AGT-04 + AGT-05 ×3) | YES (272 lines) | YES (9 @tests confirmed via grep; AGT counts match 3/1/1/1/3; setup_file + teardown_file present; INVOKE_MODES + jq + chromium-* + stat all present; NO claude update) | YES (Docker run.sh auto-globs tests/bats/*.bats; per SUMMARY, Plan 05-04 reports observed 66/66 green on both images) | VERIFIED |
| `tests/bats/51-agt02-release-gate.bats` | 1 destructive @test (AGT-02 release-gate with timeout 120s + mktemp + sort -V) | YES (97 lines) | YES (1 @test confirmed; timeout 120s, assert_no_eacces "AGT-02", claude update, mktemp, sort -V, setup_file all present) | YES (auto-globbed for every-PR matrix; `51-*.bats` prefix reserves Phase 6 TST-05 glob) | VERIFIED |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `plugin/catalog/agents/claude-code/install.sh` | Anthropic bootstrap URL | `curl -fsSL https://claude.ai/install.sh \| bash -s ${PINNED}` | WIRED | Line 30 — PIPESTATUS guarded on L31-33. |
| `plugin/catalog/agents/claude-code/install.sh` | `/home/agent/.local/bin/claude` | Native installer writes to agent-owned prefix | WIRED | Lines 36-40 binary-exists assertion. |
| `tests/bats/51-*.bats` | `claude update` self-update path | `timeout 120s sudo -u agent -H bash --login -c 'claude update' > transcript 2>&1` | WIRED | Line 68 fully formed. |
| `plugin/catalog/agents/claude-code/install.sh` | AGT-02b version-lock | `grep -q -F -- "${AGENTLINUX_PINNED_VERSION}"` on `claude --version` | WIRED | Line 47; in-recipe fail-fast before sentinel write. |
| `plugin/catalog/agents/gsd/install.sh` | `/home/agent/.npm-global/bin/get-shit-done-cc` | `npm install -g` + NPM_CONFIG_PREFIX from runner.ts | WIRED | Lines 26-30 + L35-39 `command -v` check. |
| `plugin/catalog/agents/gsd/install.sh` | AGT-04 version-lock | `get-shit-done-cc --help \| grep -q -F v${PINNED}` | WIRED | Lines 43-48. |
| `plugin/catalog/agents/playwright/install.sh` | chromium in `/home/agent/.cache/ms-playwright/chromium-*` | `npx --yes playwright install --with-deps chromium` | WIRED | Line 63 + L73 find-based assertion. |
| `plugin/catalog/agents/playwright/install.sh` | apt deps via sudo (ADR-012) | Internal playwright registry/dependencies.ts auto-prepend sudo when !root | WIRED | Line 63 `--with-deps` flag; ADR-012 NOPASSWD drop-in verified in Phase 5.1 (22-agent-sudo.bats passes 7/7). |
| `tests/bats/50-agents.bats` setup_file | Three `agentlinux install <id>` | `sudo -u agent -H bash --login -c 'agentlinux install ...'` | WIRED | Lines 67-69 sequential serial installs. |
| `tests/bats/50-agents.bats` AGT-02b/AGT-04/AGT-05 | catalog pinned_version | `jq -r '.agents[] \| select(.id=="<id>") \| .pinned_version' /opt/agentlinux/catalog/0.3.0/catalog.json` | WIRED | L152, L203, L221 — ADR-011 stability-first compliance. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| 50-agents.bats AGT-02b | `$pinned` | `jq -r '.agents[] \| select(.id=="claude-code") \| .pinned_version' /opt/agentlinux/catalog/0.3.0/catalog.json` | YES (catalog.json confirmed on disk with claude-code.pinned_version = "2.1.98") | FLOWING |
| 50-agents.bats AGT-04 | `$pinned` | jq against gsd catalog entry | YES (catalog.json confirmed: gsd.pinned_version = "1.37.1") | FLOWING |
| 50-agents.bats AGT-05 | `$pinned` | jq against playwright catalog entry | YES (catalog.json confirmed: playwright.pinned_version = "1.59.1") | FLOWING |
| install.sh recipes | `$AGENTLINUX_PINNED_VERSION` | runner.ts env injection from catalog.json at dispatch time | YES (verified in Plan 05-01 SUMMARY live observation: "2.1.98 (Claude Code)" observed from `claude --version` after install) | FLOWING |
| 50-agents.bats AGT-05 chromium check | `${output}` (find output) | `find /home/agent/.cache/ms-playwright -maxdepth 1 -type d -name "chromium-*"` after setup_file | YES (SUMMARY documents chromium-1217 observed owned agent:agent on both Ubuntu images) | FLOWING |

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|-------------|----------------|-------------|--------|----------|
| AGT-01 | 05-01, 05-04 | `claude --version` + peers succeed in all six invocation modes | SATISFIED | 3 @tests in 50-agents.bats (L90, L114, L131) loop ${INVOKE_MODES[@]} across claude/gsd/playwright. Auditor report verifies coverage. |
| AGT-02 | 05-01 | Self-update no sudo/EACCES, canonical v0.3.0 acceptance test | SATISFIED | 1 @test in 51-agt02-release-gate.bats:52 with live `claude update` + assert_no_eacces + monotonicity. Plan 05-01 SUMMARY documents observed 2.1.114 ≥ 2.1.98. (Runtime network verification flagged as human_needed — intrinsic to AGT-02's design.) |
| AGT-02b | 05-01, 05-04 | Installed version == catalog pinned_version | SATISFIED | In-recipe grep fail-fast (install.sh:47) + bats-side jq+grep (50-*.bats:150). Plan 05-01 live observation: "2.1.98 (Claude Code)" matches pin exactly. |
| AGT-03 | 05-04 | Diagnostic clean after install | SATISFIED | 1 @test in 50-agents.bats:181 using `claude --help` (doctor waits stdin per claude-code#26487) with failure-prefix regex. |
| AGT-04 | 05-02, 05-04 | gsd version-equivalent smoke | SATISFIED | In-recipe banner-grep (install.sh:44) + 1 bats @test (50-*.bats:201) with jq-driven catalog pin lookup. No --version flag — banner-grep is the version-lock. |
| AGT-05 | 05-03, 05-04 | Playwright + chromium + no sudo/EACCES | SATISFIED | In-recipe chromium-* check (install.sh:73) + 3 bats @tests (version, cache+ownership, idempotent). ADR-012 sudo used for apt install-deps; no explicit sudo in recipe body. |

**Coverage:** 6/6 Phase 5 requirement IDs satisfied. No orphans (REQUIREMENTS.md maps exactly these 6 to Phase 5). Auditor report at 05-04-AUDIT.md confirms GREEN.

### Threat Coverage (T-05-01..08 per plan threat_models)

| Threat ID | Source Plan | Category | Disposition | Verifier Confirms |
|-----------|-------------|----------|-------------|-------------------|
| T-05-01 | 05-01 | Tampering / Integrity (bootstrap fetch) | mitigate via upstream GPG + PIPESTATUS | install.sh:31-33 PIPESTATUS guard confirmed; delegating SHA/GPG to upstream per documented Anthropic bootstrap pattern |
| T-05-01b | 05-01 | Info disclosure (version format drift) | accept via substring match | install.sh:47 grep -F substring (not equality); tolerates "X.Y.Z (Claude Code)" formats |
| T-05-02 | 05-01 | DoS / availability (claude update destructive) | mitigate via sampling once + timeout 120s | 51-*.bats:68 `timeout 120s` present; single @test (no INVOKE_MODES loop on destructive op) |
| T-05-03 | 05-01 (moved to 05-04) | AGT-03 interactive doctor | mitigate via --help substitute | 50-*.bats:181 uses `claude --help` not doctor; failure-prefix regex not bare-word |
| T-05-04 | 05-02 | Tampering / integrity (npm package) | mitigate via catalog pin + runner.ts injection | gsd/install.sh:30 consumes `${AGENTLINUX_PINNED_VERSION}` from runner.ts env; `:?` fail-fast guard on L20 |
| T-05-04b | 05-02 | Spoofing (binary name confusion: gsd vs get-shit-done-cc) | mitigate via word-boundary discipline | zero binary invocations of `gsd` in install.sh (verified: only log-prefix comments); 50-*.bats and install.sh use `get-shit-done-cc` exclusively |
| T-05-04c | 05-02 | EoP (`npm install -g` sudo path) | mitigate via ADR-004 agent-owned prefix | zero sudo in gsd/install.sh; NPM_CONFIG_PREFIX=/home/agent/.npm-global from runner.ts |
| T-05-04d | 05-02 | DoS (version flag absence regression) | accept via banner-grep fallback | banner-grep mechanism stable; if upstream adds --version, banner still prints on --help |
| T-05-05 | 05-03 | EoP (sudo scope for Playwright install-deps) | accept per ADR-012 | zero explicit `sudo` in playwright/install.sh body; internal Playwright subprocess uses sudo via ADR-012 NOPASSWD drop-in |
| T-05-05b | 05-03 | Tampering (chromium download) | mitigate via upstream playwright-core checksum | delegated to playwright-core; agent-owned cache prevents shim injection |
| T-05-05c | 05-03 | DoS (281 MB chromium per run) | accept per VALIDATION | caching deferred to Phase 6 per CONTEXT; in-recipe chromium-* check catches fetch failure |
| T-05-05d | 05-03 | Info disclosure (agent cache) | accept | cache agent-owned 0755; no secrets; `rm -rf` in uninstall |
| T-05-05e | 05-03 | Scope creep (firefox/webkit) | mitigate via explicit chromium arg | zero `firefox\|webkit` strings in playwright/install.sh (verified) |
| T-05-06 | 05-04 | Coverage / spoofing (@test names) | mitigate via behavior-coverage-auditor grep | 05-04-AUDIT.md confirms 6/6 per-req coverage; @test count exactly 9 in 50-*.bats |
| T-05-06b | 05-04 | Info disclosure (catalog pins public) | accept | catalog pins are public product data; no secrets |
| T-05-06c | 05-04 | DoS (systemd-unavailable flakiness) | mitigate via SKIP_SYSTEMD_UNAVAILABLE sentinel | 50-*.bats L94/L118/L135 honor the sentinel |
| T-05-06d | 05-04 | DoS (setup_file wall-time) | accept per VALIDATION | documented ~6-8 min single-image, 12-16 min matrix |
| T-05-07 | 05-04 | TST-07 gate integrity | mitigate via unconditional auditor spawn | 05-04-AUDIT.md frontmatter `result: GREEN`; inline-rubric application documented |

**Threat coverage:** 18 threat IDs across 4 plans — all mitigated/accepted with documented rationale. No unaddressed STRIDE categories.

### Invariants Check

| Invariant | Check | Result |
|-----------|-------|--------|
| No `sudo npm install -g` in plugin/ (non-comment) | `grep -rnE "^[^#]*sudo[[:space:]]+npm[[:space:]]+install" plugin/` | PASS (0 hits; 3 comment hits documenting the anti-pattern) |
| No `/usr/local/bin/` shims in plugin/catalog/agents/ | `grep -rE "/usr/local/bin/" plugin/catalog/agents/` | PASS (0 hits) |
| shellcheck clean on new recipes | `shellcheck --severity=warning` on 6 files | PASS (all clean) |
| `bash tests/harness/run.sh` 104/104 | Executed in verifier env | PASS (104 ok, 0 not ok) |
| `./tests/docker/run.sh ubuntu-{22.04,24.04}` 66/66 | Docker not run in verifier env | UNVERIFIED (human_needed) — claimed by Plan 05-04 SUMMARY and 05-04-AUDIT.md |
| 66 @tests total on disk | `grep -hE '^@test ' tests/bats/*.bats \| wc -l` | PASS (66 confirmed: 10-installer 8 + 20-agent-user 14 + 22-agent-sudo 7 + 30-runtime 5 + 40-registry-cli 22 + 50-agents 9 + 51-agt02 1 = 66) |
| No `claude update` in 50-*.bats (destructive separation) | `! grep -Fq 'claude update' tests/bats/50-agents.bats` | PASS |
| No `firefox\|webkit` in playwright recipe | `! grep -Eq '(firefox\|webkit)' plugin/catalog/agents/playwright/install.sh` | PASS |
| Pinned versions match catalog.json | Direct inspection | PASS (claude-code 2.1.98, gsd 1.37.1, playwright 1.59.1 — all match plan interfaces) |
| TST-07 gate GREEN | `.planning/phases/05-agent-installability/05-04-AUDIT.md` frontmatter | PASS (`result: GREEN`) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Recipe syntax valid | `bash -n plugin/catalog/agents/*/install.sh plugin/catalog/agents/*/uninstall.sh` | All exit 0 | PASS |
| shellcheck clean | `shellcheck --severity=warning` on all 6 recipes | Exit 0, no warnings | PASS |
| Harness meta-tests | `bash tests/harness/run.sh` | 104 ok / 0 not ok | PASS |
| @test count exactness | `grep -c ^@test tests/bats/50-agents.bats` = 9; `...51-...bats` = 1 | Both match plan | PASS |
| AGT ID coverage | `grep -E '^@test "AGT-0[1-5]b?:' tests/bats/50-agents.bats tests/bats/51-*.bats` | 10 hits across 6 unique IDs | PASS |
| jq-driven pin lookup (ADR-011) | `grep -Fq 'jq -r' tests/bats/50-agents.bats` | Exit 0 | PASS |
| Destructive separation | `! grep -Fq 'claude update' tests/bats/50-agents.bats` | Exit 0 | PASS |
| Full Docker matrix green | `./tests/docker/run.sh ubuntu-{22.04,24.04}` | Not run in verifier env | SKIP (human_needed — documented 66/66 in plan SUMMARY) |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | — | — | No blockers, warnings, or informational anti-patterns detected in Phase 5 files. |

Specifically verified absent:
- TODO/FIXME/PLACEHOLDER markers: 0 hits
- `return null`/`return {}`/`return []` empty implementations: N/A (bash)
- Stub `echo "not implemented"` prints: 0 hits
- `sudo npm install -g` (non-comment): 0 hits
- `/usr/local/bin/` shims: 0 hits
- Hardcoded version strings in @test bodies: 0 hits (all via jq)

### Human Verification Required

See frontmatter `human_verification:` — three items (Docker matrix Ubuntu 22.04, Docker matrix Ubuntu 24.04, live AGT-02 transcript). The network-dependent AGT-02 `claude update` test is intrinsically network-dependent (fetches from Anthropic CDN); Plan 05-01 SUMMARY documents a prior flake (exit 124 timeout-SIGTERM) with successful retry — this is not a design defect but an environmental sensitivity the plan explicitly accepts. All static evidence for SC-2/SC-6/SC-7 is PASS.

### Gaps Summary

No gaps found. All 26 aggregated must-haves verified statically. All 7 ROADMAP success criteria satisfied. All 6 Phase 5 req IDs have ≥1 bats @test citing them (TST-07 gate GREEN per 05-04-AUDIT.md). All invariants pass. All threats mitigated. All anti-patterns absent.

The three human_verification items flagged above are re-confirmations of runtime behavior on live containers + live network — the plan authors observed 66/66 green on both Ubuntu images and documented the evidence in 05-04-SUMMARY.md, 05-04-AUDIT.md, REQUIREMENTS.md, and ROADMAP.md. The verifier recommends the developer confirm no regression has slipped in since those observations (low risk — no post-close commits touch Phase 5 code per `git log --oneline -20`).

---

_Verified: 2026-04-19_
_Verifier: Claude (gsd-verifier)_
