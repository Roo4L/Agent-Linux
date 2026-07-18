---
phase: 50
slug: integration-qa
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-07-18
---

# Phase 50 — Validation Strategy

> Per-phase validation contract for the reusable QA workflow and its recorded integration sweep.

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | shell assertions, Markdown checks, existing pnpm/node:test, Docker harness, real PTY helper |
| **Config file** | `plugin/cli/package.json`, `tests/docker/rc-sandbox.sh`, `tests/bats/helpers/tty-driver.py` |
| **Quick run command** | `bash .planning/phases/50-integration-qa/verify-skill.sh` |
| **Full suite command** | `bash .planning/phases/50-integration-qa/verify-skill.sh && (cd plugin/cli && pnpm test) && bash tests/harness/run.sh` |
| **Estimated runtime** | quick <10s; existing CLI/harness suite varies by host; Docker/QEMU sessions are separately recorded |

## Sampling Rate

- **After every task commit:** Run `bash .planning/phases/50-integration-qa/verify-skill.sh`
- **After every plan wave:** Run the full suite command above, plus the targeted disposable Docker scenarios in the QA report.
- **Before `$gsd-verify-work`:** The skill self-check, CLI tests, harness tests, and the recorded integration sweep must be green or explicitly handed back with limits.
- **Max feedback latency:** 60 seconds for static checks; the report records longer Docker/PTY/QEMU runs.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 50-01-01 | 01 | 1 | TST-08 | T-50-01 | Skill is discoverable from the canonical Claude project skill directory and contains no secret values | static | `bash .planning/phases/50-integration-qa/verify-skill.sh` | Wave 0 | ⬜ pending |
| 50-01-02 | 01 | 1 | TST-08 | T-50-02 | PTY, TERM, width, color, live-output, quiet-round, and handback rules are present | static | `bash .planning/phases/50-integration-qa/verify-skill.sh` | Wave 0 | ⬜ pending |
| 50-02-01 | 02 | 1 | TST-08 | T-50-03 | Existing CLI unit and harness tests remain green after the skill registration/docs changes | regression | `(cd plugin/cli && pnpm test) && bash tests/harness/run.sh` | ✅ | ⬜ pending |
| 50-03-01 | 03 | 1 | TST-08 | T-50-04 | Co-install findings are recorded with direct/adjacent scope, severity, repro, disposition, and Docker/QEMU limits | integration/report | `test -s .planning/phases/50-integration-qa/50-QA-REPORT.md && grep -q 'Coverage limits' .planning/phases/50-integration-qa/50-QA-REPORT.md` | Wave 0 | ⬜ pending |

## Wave 0 Requirements

- [x] Existing `tests/bats/helpers/tty-driver.py` and Docker harnesses cover the phase's execution primitives.
- [x] Static self-check script is created with the skill in Wave 1 before integration execution.
- [x] No new unit-test framework or catalog fixture is required; this phase validates a workflow and a report.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Representative terminal UX and live/background output | TST-08 | A transcript cannot prove the observer saw the real terminal geometry and streaming behavior | Run the skill's PTY session at default ~80 columns and the documented wider geometry with `TERM=xterm-256color`; record observed prompts, ANSI, live output, and any apparent freeze. |
| Per-user systemd daemon behavior | TST-08 | Docker masks the user systemd/logind path | Run the applicable openclaw/hermes scenarios in the QEMU harness when available; otherwise mark them QEMU-gated and do not claim coverage. |
| Human-style creative exploration | TST-08 | Bug-arrival-rate and usability judgments require an observer | Run configurable time-box rounds, reset after each new bug, and record two quiet default rounds or an explicit maintainer hand-off. |

## Validation Sign-Off

- [ ] All tasks have automated verification or an explicit manual-only row
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers the existing PTY/Docker infrastructure references
- [x] No watch-mode flags
- [x] Feedback latency target is explicit
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
