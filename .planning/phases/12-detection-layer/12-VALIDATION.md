---
phase: 12
slug: detection-layer
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-10
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core (bash test) + node:test (TypeScript CLI) |
| **Config file** | `tests/bats/helpers/*.bash`, `tests/docker/run.sh ubuntu-{22.04,24.04}` |
| **Quick run command** | `./tests/docker/run.sh ubuntu-24.04 -- tests/bats/15-detection.bats` |
| **Full suite command** | `./tests/docker/run.sh ubuntu-24.04 && ./tests/docker/run.sh ubuntu-22.04` |
| **Estimated runtime** | ~90 seconds (single .bats file in one Ubuntu image); ~6 minutes (full Docker matrix) |

---

## Sampling Rate

- **After every task commit:** Run `./tests/docker/run.sh ubuntu-24.04 -- tests/bats/15-detection.bats` (single bats file under one Ubuntu image)
- **After every plan wave:** Run full Docker matrix (`ubuntu-22.04` + `ubuntu-24.04`)
- **Before `/gsd-verify-work`:** Full Docker matrix green; bash unit-helpers green
- **Max feedback latency:** ~90 seconds for incremental, ~6 minutes for matrix

---

## Per-Task Verification Map

> Filled in by gsd-planner during planning. Each task in PLAN.md gets a row mapping it to (a) the REQ-ID it advances, (b) the bats @test that asserts the behavior, (c) the Docker image(s) it runs under.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 12-01-01 | 01 | 1 | DET-04, DET-06 (REQUIREMENTS amend) | — | REQUIREMENTS catches DET-04 binary-name typo + DET-06 schema-ceremony strikeout before any code lands | doc | `git diff --quiet HEAD~1 -- .planning/REQUIREMENTS.md && exit 1 \|\| exit 0` | ❌ W0 | ⬜ pending |
| 12-01-02 | 01 | 1 | DET-01 | — | `detect::user_*` readers return parseable values for present + absent user | bats | `./tests/docker/run.sh ubuntu-24.04 -- tests/bats/15-detection.bats` | ❌ W0 | ⬜ pending |
| 12-02-01 | 02 | 2 | DET-02 | — | All 8 Node sources detected on fixture hosts (NodeSource present, nvm symlink, etc.) | bats | `./tests/docker/run.sh ubuntu-24.04 -- tests/bats/15-detection.bats` | ❌ W0 | ⬜ pending |
| 12-02-02 | 02 | 2 | DET-03 | — | npm prefix returns the 3-value shape (user_prefix, system_prefix, effective_prefix) per RESEARCH | bats | `./tests/docker/run.sh ubuntu-24.04 -- tests/bats/15-detection.bats` | ❌ W0 | ⬜ pending |
| 12-02-03 | 02 | 2 | DET-04 | — | Each catalog binary (claude, get-shit-done-cc, playwright-cli) classified healthy/broken/absent on fixture hosts | bats | `./tests/docker/run.sh ubuntu-24.04 -- tests/bats/15-detection.bats` | ❌ W0 | ⬜ pending |
| 12-02-04 | 02 | 2 | DET-05 | T-12-01 (sudoers tampering surface) | sudoers SHA256 captured + drift flag accurate; file is never written | bats | `./tests/docker/run.sh ubuntu-24.04 -- tests/bats/15-detection.bats` | ❌ W0 | ⬜ pending |
| 12-03-01 | 03 | 3 | DET-06 (text + json) | — | text format has [DET-NN] markers; `--report-format=json` parses via jq; both render every captured field | bats | `./tests/docker/run.sh ubuntu-24.04 -- tests/bats/15-detection.bats` | ❌ W0 | ⬜ pending |
| 12-03-02 | 03 | 3 | DET-01..06 (read-only invariant) | — | snapshot of /etc /home /usr/local/bin /opt /home/agent before+after detection is byte-identical | bats | `./tests/docker/run.sh ubuntu-24.04 -- tests/bats/15-detection.bats::"detection writes zero bytes"` | ❌ W0 | ⬜ pending |
| 12-03-03 | 03 | 3 | DET-01..06 (greenfield) | — | full v0.3.0 bats matrix stays green (66/66 baseline preserved) | bats | `./tests/docker/run.sh ubuntu-24.04` | ✅ existing | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

> Note: this map is the PRE-PLANNING expectation. The planner will refine task IDs and may reorganize across plans/waves; the test commands and REQ-IDs are stable.

---

## Wave 0 Requirements

- [ ] `tests/bats/15-detection.bats` — new file; one @test per DET-XX REQ-ID + a no-op snapshot @test + a greenfield-regression @test
- [ ] `tests/bats/helpers/detect.bash` — shared helpers for fixture host setup (e.g., `with_nvm_installed`, `with_root_owned_npm_prefix`, `with_drifted_sudoers`)
- [ ] `tests/docker/Dockerfile.ubuntu-{22.04,24.04}` — pre-install `jq` so the no-op snapshot @test isn't tripped by `apt-get install jq` (per RESEARCH §Pitfall #4)
- [ ] `plugin/lib/detect/README.md` — paragraph-form allowed-probe list (`dpkg-query`, `apt list --installed`, `id`, `getent`, `stat`, `node --version`, `npm config get prefix`, `<agent> --version`)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| (none) | — | — | All Phase 12 behaviors have automated bats coverage. The brownfield-acceptance smoke (AGT-02 still green) is the milestone-close gate, owned by Phase 16 — not Phase 12. |

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (jq pre-install in Dockerfile; new bats file; helpers)
- [ ] No watch-mode flags (Docker `run.sh` is one-shot)
- [ ] Feedback latency ~90s incremental
- [ ] `nyquist_compliant: true` set in frontmatter (after planner finalizes task IDs)

**Approval:** pending
