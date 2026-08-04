---
phase: 5
slug: agent-installability
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-19
---

# Phase 5 — Validation Strategy

> Real-agent recipes + AGT-01..05 + AGT-02b.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core (black-box) + pre-commit (shellcheck/shfmt/biome/ajv) |
| **Config file** | `tests/docker/run.sh` (extends Phase 4 matrix) |
| **Quick run command** | `shellcheck plugin/catalog/agents/*/install.sh plugin/catalog/agents/*/uninstall.sh` |
| **Full suite command** | `./tests/docker/run.sh ubuntu-22.04 && ./tests/docker/run.sh ubuntu-24.04` (includes real claude-code install + `claude update` + gsd + playwright with chromium download) |
| **Estimated runtime** | ~12–16 min full matrix (adds ~6–8 min per image for real installs + chromium ~281MB download + Playwright install-deps apt) |

---

## Sampling Rate

- **After every task commit:** `shellcheck` on touched recipes (≤5s).
- **After every plan:** Single-image full run (`./tests/docker/run.sh ubuntu-24.04`) ~6–8 min.
- **Before phase close:** Full matrix (22.04 + 24.04) green; AGT-02 release-gate bats file (`51-agt02-release-gate.bats`) green independently.
- **Max feedback latency:** 30s quick; 480s single-image full.

---

## Per-Task Verification Map

> Task IDs provisional — planner may restructure. Requirement IDs authoritative.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 claude-code | 1 | AGT-01, AGT-02b | T-05-01 | install.sh runs `curl .../install.sh \| bash -s "$AGENTLINUX_PINNED_VERSION"` via as_user; claude binary at /home/agent/.local/bin/claude | integration | bats: `run_interactive 'claude --version'` matches `2.1.98` | ❌ W0 | ⬜ pending |
| 05-01-02 | 01 claude-code | 1 | AGT-02 | T-05-02 | `claude update` exit 0, transcript no EACCES, version monotonic; release-gate tagged | bats | `bats tests/bats/51-agt02-release-gate.bats` — exit 0 | ❌ W0 | ⬜ pending |
| 05-01-03 | 01 claude-code | 1 | AGT-03 | T-05-03 | `claude --help` exits 0, no error strings (substitute for interactive `claude doctor`) | bats | `run_interactive 'claude --help'` exit 0 | ❌ W0 | ⬜ pending |
| 05-02-01 | 02 gsd | 1 | AGT-04 | T-05-04 | install.sh `as_user -- npm install -g get-shit-done-cc@$AGENTLINUX_PINNED_VERSION`; binary at /home/agent/.npm-global/bin/get-shit-done-cc | integration | bats: `run_interactive 'get-shit-done-cc --help'` contains `v1.37.1` banner | ❌ W0 | ⬜ pending |
| 05-03-01 | 03 playwright | 1 | AGT-05 | T-05-05 | install.sh `as_user -- npm install -g playwright@$AGENTLINUX_PINNED_VERSION` + `npx playwright install --with-deps chromium` (sudo auto-prepended via ADR-012) | integration | bats: `run_interactive 'npx playwright --version'` matches `1.59.1`; chromium exists under /home/agent/.cache/ms-playwright/ | ❌ W0 | ⬜ pending |
| 05-04-01 | 04 bats+TST-07 | 2 | AGT-01 | T-05-06 | AGT-01 six-mode loop: claude, get-shit-done-cc, npx playwright all runnable across all 6 INVOKE_MODES | bats | `tests/bats/50-agents.bats @test "AGT-01: ..."` | ❌ W0 | ⬜ pending |
| 05-04-02 | 04 bats+TST-07 | 2 | TST-07 | T-05-07 | behavior-coverage-auditor phase-close: AGT-01..05 + AGT-02b all have ≥1 bats @test; TST-07 gate GREEN | review | auditor output in 05-SUMMARY.md | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `plugin/catalog/agents/claude-code/install.sh` — REPLACE scaffold body with real native-installer invocation via as_user
- [ ] `plugin/catalog/agents/claude-code/uninstall.sh` — REPLACE scaffold body with real uninstall (~/.local/bin/claude + ~/.claude/)
- [ ] `plugin/catalog/agents/gsd/install.sh` — REPLACE scaffold body (npm install -g get-shit-done-cc@pin via as_user)
- [ ] `plugin/catalog/agents/gsd/uninstall.sh` — REPLACE scaffold body (npm uninstall -g get-shit-done-cc)
- [ ] `plugin/catalog/agents/playwright/install.sh` — REPLACE scaffold body (npm install -g + npx playwright install --with-deps chromium)
- [ ] `plugin/catalog/agents/playwright/uninstall.sh` — REPLACE scaffold body (npm uninstall -g + optional cache cleanup)
- [ ] `tests/bats/50-agents.bats` — NEW; ≥10 @tests covering AGT-01..05 + AGT-02b
- [ ] `tests/bats/51-agt02-release-gate.bats` — NEW; AGT-02 canonical test, release-gate tagged for Phase 6 CI selection
- [ ] Catalog entries — verify `catalog.json` pinned_versions match current stable; bump if yanked (claude-code 2.1.98, gsd 1.37.1, playwright 1.59.1 all confirmed via research)
- [ ] Update claude-code entry `display_name` to confirm `source_kind: "script"` (native installer path, not npm)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real `claude update` against live Anthropic servers (network dependency) | AGT-02 release-gate | CI may hit rate limits; manual confirms "works on fresh Ubuntu" end-to-end | Run `./tests/docker/run.sh ubuntu-24.04` locally after each release candidate |
| AGT-05 browser launch smoke (`npx playwright launch chromium --no-sandbox`) | AGT-05 | Headed browser startup in Docker is flaky; adequate for bats is version + install | Manual spot-check on fresh Ubuntu cloud image in Phase 6 QEMU run |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity satisfied
- [ ] Wave 0 covers 10 MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s quick, < 480s single-image full
- [ ] `nyquist_compliant: true` after Wave 0 completes

**Approval:** pending
