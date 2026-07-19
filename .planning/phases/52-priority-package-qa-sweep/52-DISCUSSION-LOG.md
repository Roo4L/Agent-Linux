# Phase 52: priority-package-qa-sweep - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-19
**Phase:** 52-priority-package-qa-sweep
**Areas discussed:** Distro and terminal depth, Finding disposition

---

## Distro and terminal depth

| Option | Description | Selected |
|--------|-------------|----------|
| One representative coding-agent PTY plus one Playwright/TUI flow | Focus PTY coverage on representative interactive surfaces | |
| PTY coverage for Claude, Codex, OpenCode, and Playwright | Cover the named interactive tools | |
| Reuse the existing single-agent PTY baseline | Avoid expanding interactive coverage | |
| Other | Every priority package with a genuinely interactive interface | ✓ |

| Option | Description | Selected |
|--------|-------------|----------|
| Exercise distro-sensitive paths on Ubuntu 22.04 and 26.04 | Target package/runtime differences on both additional distros | |
| Repeat the full matrix on all three Ubuntu versions | Full cross-distro confidence | |
| Limit Ubuntu 22.04 and 26.04 to lifecycle checks | Minimal additional distro coverage | |
| Other | Leave Ubuntu 22.04 and 26.04 aside for this phase | ✓ |

| Option | Description | Selected |
|--------|-------------|----------|
| Redacted PTY transcripts plus terminal metadata | Preserve TERM, dimensions, color mode, prompts, and timing | ✓ |
| Transcripts plus screenshots or terminal recordings | Add visual artifacts | |
| Command output only | Omit terminal-session artifacts | |
| Other | Free-form alternative | |

| Option | Description | Selected |
|--------|-------------|----------|
| Bounded timeout, transcript capture, and one fresh-state retry | Distinguish transient/environmental timeout from reproducible behavior | ✓ |
| Any reproducible timeout is a finding without a second attempt | Classify immediately | |
| Allow extended manual waits before classification | Prefer waiting over bounded retry | |
| Other | Free-form alternative | |

**User's choice:** Every interactive interface; Ubuntu 24.04 only; redacted PTY transcripts with metadata; bounded timeout plus one clean-state retry.
**Notes:** Ubuntu 22.04 and 26.04 must be explicitly reported as not covered.

---

## Finding disposition

| Option | Description | Selected |
|--------|-------------|----------|
| Complete discovery, then allow a separate remediation pass | Reconcile observation-only discovery with later fixes | |
| Keep the phase strictly observation-only | Owner directs all disposition after results | ✓ |
| Fix trivial findings immediately | Remediate during QA | |
| Other | Free-form clarification | |

| Option | Description | Selected |
|--------|-------------|----------|
| Factual findings only | Record severity, scope, reproduction, evidence, classification, and residual risk | ✓ |
| Non-binding remediation ideas | Add suggestions without taking action | |
| Proposed Jira/phase routing | Draft routing without creating it | |
| Other | Free-form alternative | |

| Option | Description | Selected |
|--------|-------------|----------|
| Continue independent ideas and reset counters | Preserve the QA stop rule after a new issue | ✓ |
| Pause for the owner's decision | Stop immediately on each new issue | |
| Finish only the current workflow, then stop | End the active scenario before handback | |
| Other | Free-form alternative | |

| Option | Description | Selected |
|--------|-------------|----------|
| Deliberately replay known findings as regression checks | Allocate explicit replay ideas | |
| Exclude known findings entirely | Avoid known issue paths | |
| Replay only priority-package findings | Narrow deliberate replay | |
| Other | Test naturally; record an organic prior-issue encounter as a regression with ordinary counter handling | ✓ |

**User's choice:** Strictly observation-only; factual report; continue independent QA after new findings; no deliberate known-issue replay.
**Notes:** The owner will decide what to do with all results. Known issues receive no special replay or counter treatment; only natural encounters are marked as regressions.

---

## the agent's Discretion

- Select realistic package operations, co-install combinations, installation
  orders, credential classes, and interactive-interface inventory within the
  fixed Phase 52 scope and the `qa-testing` contract.

## Deferred Ideas

- Website PR preview deployments — unrelated to the priority-package QA
  campaign.
