---
phase: 50
slug: integration-qa
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-18
---

# Phase 50 — Validation Strategy

> Per-phase validation contract for the reusable package-QA workflow and its evidence-led integration sweep.

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | shell assertions, Markdown checks, catalog metadata parsing, disposable Docker, genuine PTY |
| **Config file** | `plugin/catalog/catalog.json`, `tests/docker/rc-sandbox.sh`, `tests/docker/run-smoke.sh`, `tests/bats/helpers/tty-driver.py` |
| **Quick run command** | `bash .planning/phases/50-integration-qa/verify-skill.sh` |
| **Full suite command** | The Phase 50 QA skill's scenario ledger executed in fresh Ubuntu 24.04 RC containers, followed by targeted Ubuntu 22.04 and 26.04 ideas; this is intentionally not `tests/docker/run.sh`. |
| **Estimated runtime** | Static checks <10s; package ideas vary; stop requires 30 productive minutes and 10 latest clean-by-novelty ideas. |

## Sampling Rate

- **After each skill/report task:** Run `bash .planning/phases/50-integration-qa/verify-skill.sh` and the relevant ledger/schema check.
- **After each QA wave:** Persist the current ledger and finding records; run a fresh-container cleanup check for the scenarios in that wave.
- **Before `$gsd-verify-work`:** The skill contract, catalog inventory reconciliation, report evidence, and stop-rule arithmetic must be reviewable. No source fix is required or permitted as part of the QA run.
- **Max feedback latency:** 60 seconds for static/ledger checks; long-running package operations are measured as productive activity and recorded.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 50-01-01 | 01 | 1 | TST-08 | T-50-01 | Skill is discoverable, observation-only, credential-aware, and uses the productive stop rule | static | `bash .planning/phases/50-integration-qa/verify-skill.sh` | Wave 1 | ⬜ pending |
| 50-01-02 | 01 | 1 | TST-08 | T-50-02 | Ledger inventory equals all catalog entries except `openclaw`, `hermes-agent`, and `test-dummy` | static | `node` catalog/ledger comparison command documented in the plan | Wave 1 | ⬜ pending |
| 50-02-01 | 02 | 2 | TST-08 / OPS-01 | T-50-03 | Included packages install, operate beyond help/version, and remove cleanly in fresh Ubuntu 24.04 containers | disposable integration | Scenario-ledger commands and post-remove assertions | Wave 2 | ⬜ pending |
| 50-03-01 | 03 | 2 | TST-08 | T-50-04 | Workflow-based co-install permutations converge, preserve siblings/unrelated config, and leave no forbidden shims | disposable integration | Fresh-container scenario commands recorded per idea | Wave 2 | ⬜ pending |
| 50-04-01 | 04 | 3 | TST-08 | T-50-05 | Targeted Ubuntu 22.04/26.04 checks and a genuine PTY session are recorded without overclaiming daemon coverage | manual/integration | PTY driver plus targeted Docker ideas | Wave 3 | ⬜ pending |
| 50-05-01 | 05 | 4 | TST-08 | T-50-06 | Report proves productive-time and latest-10 clean-by-novelty stop arithmetic, or records an explicit block | report verification | `test -s .planning/phases/50-integration-qa/50-QA-REPORT.md` plus report consistency checks | Wave 4 | ⬜ pending |

## Wave 0 Requirements

- [ ] A deterministic self-check for the revised skill contract.
- [ ] A catalog-to-ledger comparison that detects omitted or silently newly included entries.
- [x] Existing Docker RC and PTY primitives are available; no new test framework is needed.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Realistic package operations and creative edge cases | TST-08 / OPS-01 | The high-value behavior is user observation across many tools and cannot be reduced to static text checks | Execute the ledger in fresh containers; run category-specific operations, lifecycle permutations, and cleanup; record exact commands and redacted evidence. |
| Credentialed operation | TST-08 / OPS-01 | Credentials are supplied by the user at runtime and must not enter fixtures/reports | Ask for the inventory's credentials before the relevant ideas; if an unexpected credential is requested, mark the idea blocked and ask rather than skipping. |
| Genuine terminal UX | TST-08 | PTY geometry, ANSI, live output, and apparent freezes require observation through a real terminal | Use `TERM=xterm-256color`, color enabled, default 80 columns plus a wider case; capture redacted output and timing. |
| Productive stop decision | TST-08 | Productive activity and novelty are session observations, not wall-clock chat time | Log active intervals only; reset both measures for each new reproducible issue; stop only when active time ≥30 minutes and the latest 10 distinct ideas are clean for new-issue discovery. |
| Systemd daemon behavior | TST-08 | Docker does not provide the requested systemd service environment | Keep `openclaw` and `hermes-agent` excluded from this campaign and state the boundary; do not infer a pass. |

## Validation Sign-Off

- [ ] All plan tasks have automated evidence or an explicit manual-only row
- [ ] Catalog inventory is reconciled before execution
- [ ] No source fixes are made while findings are being gathered
- [ ] The final report contains the ledger, findings, blocked ideas, exclusions, active-time log, and stop arithmetic
- [ ] `nyquist_compliant: true` set after execution evidence is complete

**Approval:** pending
