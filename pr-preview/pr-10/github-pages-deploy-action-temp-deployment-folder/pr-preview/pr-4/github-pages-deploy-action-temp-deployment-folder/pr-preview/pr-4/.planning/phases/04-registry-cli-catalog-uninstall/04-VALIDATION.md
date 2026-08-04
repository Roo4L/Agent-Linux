---
phase: 4
slug: registry-cli-catalog-uninstall
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-19
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | node:test (stdlib) for CLI units; bats-core for CLI integration; pre-commit (shellcheck/shfmt/biome/ajv-catalog-schema) |
| **Config file** | `plugin/cli/package.json` (scripts.test = "node --test"); `.pre-commit-config.yaml` with ajv-driven catalog hook; `tests/docker/run.sh` |
| **Quick run command** | `cd plugin/cli && pnpm test` (node:test unit) + `shellcheck plugin/provisioner/50-registry-cli.sh plugin/catalog/agents/*/install.sh plugin/catalog/agents/*/uninstall.sh` |
| **Full suite command** | `./tests/docker/run.sh ubuntu-22.04 && ./tests/docker/run.sh ubuntu-24.04` (runs installer with Phase 4 CLI + catalog, runs all bats including new 40-registry-cli.bats) |
| **Estimated runtime** | ~6–8 min full matrix (+ ~1–2 min per image for pnpm install + tsc build + ajv+commander+semver footprint inside Docker) |

---

## Sampling Rate

- **After every task commit:** Quick — `pnpm test` for TS, `shellcheck`+`shfmt -d` for bash. ≤10s.
- **After every plan wave:** Single-image full run (`./tests/docker/run.sh ubuntu-24.04`) ~3–4 min.
- **Before phase close:** Full matrix (22.04 + 24.04) green.
- **Max feedback latency:** 30s quick; 300s single-image full.

---

## Per-Task Verification Map

> Task IDs provisional — planner may restructure. Requirement IDs authoritative.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 scaffold | 1 | CLI-01 | T-04-01 | `plugin/cli/package.json` pins commander@^12, ajv@^8, semver@^7; biome clean | unit | `cd plugin/cli && pnpm install && pnpm run check` | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 scaffold | 1 | CAT-03 | T-04-02 | Ajv2020 validator at `plugin/cli/src/catalog/validator.ts` loads `plugin/catalog/schema.json` (2020-12 draft) and rejects malformed entries with clear diagnostics | unit | `node --test plugin/cli/test/validator.test.ts` | ❌ W0 | ⬜ pending |
| 04-01-03 | 01 scaffold | 1 | CAT-04 | T-04-03 | Schema requires `pinned_version` (semver pattern), `npm_package_name` (when source_kind=npm), `source_kind` enum | unit | Ajv validate test with fixture missing pinned_version → returns error | ❌ W0 | ⬜ pending |
| 04-02-01 | 02 catalog | 1 | CAT-01 | T-04-04 | `plugin/catalog/catalog.json` lists claude-code, gsd (get-shit-done-cc), playwright with pinned_version | integration | `ajv validate -s schema.json -d catalog.json` exit 0 | ❌ W0 | ⬜ pending |
| 04-02-02 | 02 catalog | 1 | CAT-02 | T-04-05 | Fresh installer run produces no `installed.d/*.json` sentinels (no default agents) | bats | `tests/bats/40-registry-cli.bats @test "CAT-02: ..."` | ❌ W0 | ⬜ pending |
| 04-02-03 | 02 catalog | 1 | CAT-03 | T-04-02 | Test-only `test-dummy` entry + shell install.sh/uninstall.sh; filtered from default `list` via `test_only: true` | bats | list --include-test shows 4 entries; list shows 3 | ❌ W0 | ⬜ pending |
| 04-03-01 | 03 list/install/remove | 2 | CLI-01, CLI-02 | T-04-06 | `agentlinux list` table format (NAME STATUS CURATED INSTALLED DESCRIPTION); `--json` flag emits machine-readable | bats | `run_interactive 'agentlinux list'` → table; `run_interactive 'agentlinux list --json' \| jq '.[0].id'` → valid | ❌ W0 | ⬜ pending |
| 04-03-02 | 03 list/install/remove | 2 | CLI-03, CAT-04 | T-04-07 | `agentlinux install test-dummy` invokes install.sh with `AGENTLINUX_PINNED_VERSION` env set; writes `/opt/agentlinux/state/installed.d/test-dummy.json` sentinel | bats | file-exists + jq query version match | ❌ W0 | ⬜ pending |
| 04-03-03 | 03 list/install/remove | 2 | CLI-03 | T-04-08 | `install` is idempotent: second call with same version skips (logs "already installed"); `--force` re-runs | bats | diff sentinel sha256 PRE/POST → identical | ❌ W0 | ⬜ pending |
| 04-03-04 | 03 list/install/remove | 2 | CLI-04 | T-04-09 | `agentlinux remove test-dummy` invokes uninstall.sh, removes sentinel; `remove <missing>` exits non-zero unless `--force` | bats | sentinel absent post-remove; exit code 0 then non-zero | ❌ W0 | ⬜ pending |
| 04-03-05 | 03 list/install/remove | 2 | CLI-05 | T-04-10 | Running as non-agent user (EUID != agent's UID) exits 1 with clear "Run as agent:" message; `hook('preAction')` guard | unit+bats | `sudo -u root agentlinux list` exit 1 | ❌ W0 | ⬜ pending |
| 04-04-01 | 04 upgrade | 2 | CLI-06 | T-04-11 | 6-state classifier: `synced` / `override-ahead` / `override-behind` / `pinned-override` / `drift-undeclared` / `not-installed` | unit | `node --test plugin/cli/test/divergence.test.ts` (pure function) | ❌ W0 | ⬜ pending |
| 04-04-02 | 04 upgrade | 2 | CLI-06 | T-04-12 | `agentlinux upgrade` offline by default; `--check-upstream` opts into npm view; `--reset-all-curated`, `--respect-overrides`, `--all-latest` flags | bats | fixture: sentinel claims 2.0.0, catalog pins 2.1.7 → upgrade reports override-behind; `--reset-all-curated` re-installs to 2.1.7 | ❌ W0 | ⬜ pending |
| 04-04-03 | 04 upgrade | 2 | CLI-06 | T-04-13 | `--all-latest` respects `version_constraint` (e.g. `^2.1` upper-bounds to highest 2.x, not 3.x) via `semver.maxSatisfying` | unit | `plugin/cli/test/upgrade.test.ts` uses semver range fixture | ❌ W0 | ⬜ pending |
| 04-05-01 | 05 pin | 2 | CLI-07 | T-04-14 | `agentlinux pin <name>=<curated\|latest\|x.y.z>` writes sentinel with `source: "pinned"` + `pinned_to` value; `upgrade` skips pinned entries | bats | pin test-dummy=latest; run upgrade → test-dummy unchanged, not re-prompted | ❌ W0 | ⬜ pending |
| 04-06-01 | 06 provisioner + purge | 3 | CLI-01 | T-04-15 | `plugin/provisioner/50-registry-cli.sh` stages dist under `/opt/agentlinux/cli/<version>/`, symlinks `/home/agent/.npm-global/bin/agentlinux` | bats | agentlinux on PATH in all 6 invocation modes (reuse invoke_modes helpers) | ❌ W0 | ⬜ pending |
| 04-06-02 | 06 provisioner + purge | 3 | INST-04 | T-04-16 | `plugin/bin/agentlinux-install --purge` teardown in 7 ordered idempotent steps; post-run: agent user gone, /home/agent gone, /opt/agentlinux gone, PATH files gone, log gone | bats | `run_sudo_u_i '<root-side> agentlinux-install --purge'` + 6 filesystem absence assertions | ❌ W0 | ⬜ pending |
| 04-06-03 | 06 provisioner + purge | 3 | INST-04 | T-04-17 | `--purge` does NOT apt-remove nodejs unless `--purge --remove-nodejs` passed (shared with other users) | bats | post-purge without --remove-nodejs: `which node` still works; with flag: node gone | ❌ W0 | ⬜ pending |
| 04-07-01 | 07 bats + TST-07 | 3 | TST-01, TST-04 | T-04-18 | `tests/bats/40-registry-cli.bats` covers CLI-01..07, CAT-01..04, INST-04 end-to-end; every @test references req ID | bats | `bats tests/bats/40-registry-cli.bats` — expected ≥15 @tests pass in both Docker images | ❌ W0 | ⬜ pending |
| 04-07-02 | 07 bats + TST-07 | 3 | TST-07 | T-04-19 | behavior-coverage-auditor at phase close: every CLI-XX, CAT-XX, INST-04 has ≥1 bats @test citing the ID — `TST-07 gate: GREEN` | review | auditor report in 04-SUMMARY.md | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `plugin/cli/package.json` — deps: commander@^12, ajv@^8, ajv-formats, semver@^7; devDeps: typescript, biome, @types/node; scripts: build, test, check
- [ ] `plugin/cli/tsconfig.json` — Node22 ES2024, strict, moduleResolution nodenext, outDir dist
- [ ] `plugin/cli/biome.json` — inherit project biome config
- [ ] `plugin/cli/src/index.ts` — Commander.js entrypoint with preAction EUID guard
- [ ] `plugin/cli/src/commands/{list,install,remove,upgrade,pin}.ts` — subcommand handlers
- [ ] `plugin/cli/src/catalog/validator.ts` — Ajv2020 validator
- [ ] `plugin/cli/src/catalog/loader.ts` — reads catalog.json + resolves recipe paths
- [ ] `plugin/cli/src/state/sentinel.ts` — `/opt/agentlinux/state/installed.d/<id>.json` read/write with atomic rename
- [ ] `plugin/cli/src/runner.ts` — dispatches to recipe install.sh/uninstall.sh via as_user with AGENTLINUX_* env
- [ ] `plugin/cli/src/upgrade/divergence.ts` — 6-state classifier (pure function)
- [ ] `plugin/cli/test/*.test.ts` — node:test unit tests per src module
- [ ] `plugin/catalog/catalog.json` — 3 real entries (claude-code, gsd as get-shit-done-cc, playwright) + test-dummy
- [ ] `plugin/catalog/schema.json` — extended for pinned_version, npm_package_name, source_kind
- [ ] `plugin/catalog/agents/{claude-code,gsd,playwright,test-dummy}/{install,uninstall}.sh` — recipes
- [ ] `plugin/provisioner/50-registry-cli.sh` — stages CLI + creates PATH symlink
- [ ] `plugin/bin/agentlinux-install` — EXTEND `--purge` stub flag to real 7-step teardown
- [ ] `plugin/cli/scripts/validate-catalog.mjs` — REPLACE zero-dep scaffold with ajv-driven validator (pre-commit calls it)
- [ ] `tests/bats/40-registry-cli.bats` — NEW; ≥15 @tests covering CLI-01..07, CAT-01..04, INST-04

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real claude-code install + self-update from pinned version | AGT-02, AGT-02b | Phase 5 concern; Phase 4 uses test-dummy to exercise dispatch | Deferred to Phase 5 |
| Release-pipeline catalog snapshot publication | CAT-05 | Phase 6 concern (release.yml) | Deferred to Phase 6 |
| Pinned-combo CI gate before tag | TST-08 | Phase 6 concern (release.yml) | Deferred to Phase 6 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all 18 MISSING references
- [ ] No watch-mode flags (node:test one-shot; bats one-shot; shellcheck one-shot)
- [ ] Feedback latency < 30s quick, < 300s single-image full
- [ ] `nyquist_compliant: true` set in frontmatter after Wave 0 completes

**Approval:** pending
