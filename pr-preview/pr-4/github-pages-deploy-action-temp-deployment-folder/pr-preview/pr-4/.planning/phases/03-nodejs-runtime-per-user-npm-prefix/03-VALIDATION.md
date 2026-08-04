---
phase: 3
slug: nodejs-runtime-per-user-npm-prefix
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-18
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core (black-box behavior tests) + pre-commit (shellcheck/shfmt) |
| **Config file** | `.pre-commit-config.yaml` (Phase 1); `tests/docker/run.sh` (Phase 2) |
| **Quick run command** | `shellcheck plugin/provisioner/30-nodejs.sh plugin/provisioner/40-path-wiring.sh` + `bash -n plugin/**/*.sh` |
| **Full suite command** | `./tests/docker/run.sh ubuntu-22.04 && ./tests/docker/run.sh ubuntu-24.04` — runs installer (now with 30-nodejs.sh dispatched) + all bats (10-installer.bats, 20-agent-user.bats, 30-runtime.bats) inside each container |
| **Estimated runtime** | ~5–7 min full matrix (adds ~1–2 min per image for apt-install nodejs) |

---

## Sampling Rate

- **After every task commit:** Run `shellcheck` on touched `.sh` (≤5s)
- **After every plan wave:** Run `./tests/docker/run.sh ubuntu-24.04` (full installer + all bats in one image, ~3–4 min)
- **Before phase close:** Full matrix (22.04 + 24.04) must be green
- **Max feedback latency:** 30s for quick lint; 240s for single-image full run

---

## Per-Task Verification Map

> Task IDs are provisional — planner may collapse/split. Requirement IDs authoritative.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 provisioner | 1 | RT-01 | T-03-01 | `plugin/provisioner/30-nodejs.sh` adds NodeSource repo idempotently (detect `nodesource.sources` + `nodesource.list`), installs `nodejs` ≥22 | integration | bats: `run_interactive 'node --version'` → `/^v22\./` | ❌ W0 | ⬜ pending |
| 03-01-02 | 01 provisioner | 1 | RT-04 | T-03-02 | Write `/home/agent/.npmrc` with `prefix=/home/agent/.npm-global` via `as_user` + `ensure_line_in_file`; create dir `ensure_dir /home/agent/.npm-global 0755 agent:agent` | integration | bats: `run_interactive 'npm config get prefix'` → `/^\/home\/agent\//` | ❌ W0 | ⬜ pending |
| 03-01-03 | 01 provisioner | 1 | RT-04 | T-03-03 | EXTEND `plugin/provisioner/40-path-wiring.sh` to prepend `/home/agent/.npm-global/bin` to PATH in profile.d, agentlinux.env, cron.d + add `NPM_CONFIG_PREFIX=/home/agent/.npm-global` (belt-and-braces, avoids split-brain with .npmrc) | integration | bats: six-mode PATH inspection — each mode contains `.npm-global/bin` | ❌ W0 | ⬜ pending |
| 03-01-04 | 01 provisioner | 1 | INST-02 | T-03-04 | Idempotency: re-run installer; assert byte-stable state across 30-nodejs artefacts (extend INST-02 test: sha256 of `/home/agent/.npmrc`, `/etc/apt/sources.list.d/nodesource.sources`) | integration | bats `tests/bats/10-installer.bats` INST-02 extended | ❌ W0 | ⬜ pending |
| 03-02-01 | 02 tests | 2 | RT-01 | T-03-01 | `tests/bats/30-runtime.bats @test "RT-01: node --version returns LTS v22 in every invocation mode"` — loop all six helpers | bats | `bats tests/bats/30-runtime.bats` | ❌ W0 | ⬜ pending |
| 03-02-02 | 02 tests | 2 | RT-02 | T-03-05 | `@test "RT-02: agent user can npm install -g cowsay across six modes without sudo/EACCES"` — installs, then loops six modes asserting `command -v cowsay && cowsay hi` | bats | `bats tests/bats/30-runtime.bats` | ❌ W0 | ⬜ pending |
| 03-02-03 | 02 tests | 2 | RT-03 | T-03-06 | `@test "RT-03: npm uninstall -g cowsay is byte-clean"` — `as_user -- npm uninstall -g cowsay`; assert `command -v cowsay` non-zero in all six modes; assert `/home/agent/.npm-global/bin/{cowsay,cowthink}` absent (cowsay@1.6.0 ships TWO bin entries per research); assert `/home/agent/.npm-global/lib/node_modules/cowsay` absent | bats | `bats tests/bats/30-runtime.bats` | ❌ W0 | ⬜ pending |
| 03-02-04 | 02 tests | 2 | RT-04 | T-03-07 | `@test "RT-04: npm config get prefix is under agent home"` — uses NEW helper `assert_user_prefix_in_home` in `tests/bats/helpers/assertions.bash`; asserts prefix path starts with `/home/agent/`, never `/usr` | bats | `bats tests/bats/30-runtime.bats` + helper sanity | ❌ W0 | ⬜ pending |
| 03-02-05 | 02 tests | 2 | INST-05 | T-03-08 | Extend `tests/bats/10-installer.bats` INST-05 test to cover `npm install -g cowsay` transcript — no EACCES from npm itself in the installer log or during the RT-02 test | bats | installer log grep + RT-02 test log grep | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `plugin/provisioner/30-nodejs.sh` — NodeSource apt repo install, idempotent, writes ~agent/.npmrc, installs Node 22 LTS
- [ ] `plugin/provisioner/40-path-wiring.sh` — EXTEND with `/home/agent/.npm-global/bin` prepend + `NPM_CONFIG_PREFIX=/home/agent/.npm-global`
- [ ] `tests/bats/helpers/assertions.bash` — APPEND `assert_user_prefix_in_home`
- [ ] `tests/bats/30-runtime.bats` — NEW; 5 @tests covering RT-01..04 + INST-05 extension
- [ ] `tests/bats/10-installer.bats` — EDIT INST-02 test to include `~agent/.npmrc` + `/etc/apt/sources.list.d/nodesource.sources` in sha256 byte-stability set
- [ ] Docker images `tests/docker/Dockerfile.ubuntu-{22,24}.04` — PREQ: ensure `curl`, `gnupg`, `ca-certificates` are present (belt-and-braces; NodeSource's own script also installs them, but having them pre-stamped speeds up builds)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real Claude Code installation using this prefix proves AGT-02 | RT-02 / AGT-02 link | The canonical acceptance test (AGT-02) lands in Phase 5, not Phase 3 — cowsay is the smoke proxy that validates the mechanism | Deferred to Phase 5 Plan 05-01 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all 6 MISSING references
- [ ] No watch-mode flags (bats one-shot; shellcheck one-shot)
- [ ] Feedback latency < 30s for quick lint, < 240s for single-image full run
- [ ] `nyquist_compliant: true` set in frontmatter after Wave 0 completes

**Approval:** pending
