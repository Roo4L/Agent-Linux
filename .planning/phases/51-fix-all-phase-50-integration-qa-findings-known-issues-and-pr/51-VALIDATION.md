---
phase: 51-fix-all-phase-50-integration-qa-findings-known-issues-and-pr
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-19
---

# Phase 51 — Validation Strategy

> Per-phase validation contract for remediation feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bats behavior suite, shellcheck/shfmt, catalog schema validator, Node/TypeScript CLI tests, Docker RC harness |
| **Config file** | `tests/docker/run.sh`, `plugin/cli/package.json`, `tests/bats/helpers/` |
| **Quick run command** | `bash tests/harness/run.sh` plus the targeted Bats file(s) named by the current plan |
| **Full suite command** | `./tests/docker/run.sh ubuntu-24.04` |
| **Estimated runtime** | ~5–15 minutes for targeted checks; full Docker suite varies with package/network operations |

---

## Sampling Rate

- **After every task commit:** Run the task's targeted shell/Node/Bats check and `git diff --check`.
- **After every plan wave:** Run the affected targeted Bats files and catalog validation; run the CLI test suite when `plugin/cli` changes.
- **Before `$gsd-verify-work`:** Full targeted Docker regression must be green, and the follow-up `qa-testing` report must be recorded.
- **Max feedback latency:** 30 seconds for local static/unit checks; Docker and live-auth checks are long-running evidence tasks.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 51-01-01 | 01 | 1 | MCP-03 / MCP-07 / OPS-01 | T-51-01 | Runtime-only credentials; Firecrawl auth contract and OpenCode OAuth root cause are redacted and explicit | integration | `51-OAUTH-DIAGNOSTICS.md` + targeted MCP Bats | ✅ | ⬜ pending |
| 51-01-02 | 01 | 1 | MCP-03 / MCP-07 | T-51-02 | Firecrawl guidance is truthful and five-client registration remains credential-free/symmetric | behavior | `tests/bats/60-catalog-github-mcp.bats tests/bats/62-catalog-firecrawl-mcp.bats tests/bats/71-phase51-hosted-mcp.bats` | ✅ | ⬜ pending |
| 51-02-01 | 02 | 1 | WIRE-01 / OPS-01 | T-51-03 | Failed Playwright target returns nonzero; valid action remains zero | behavior | `tests/bats/72-phase51-prerequisites.bats` + local fixture | ✅ | ⬜ pending |
| 51-02-02 | 02 | 1 | MCP-01 / WORK-03 / OPS-01 | T-51-04 | git, Chrome, and browser libraries are installed or fail with explicit escalation | integration | fresh Ubuntu 22.04/24.04/26.04 Docker checks | ✅ | ⬜ pending |
| 51-03-01 | 03 | 2 | WIRE-01 / AGT-01 / AGT-04 / OPS-01 | T-51-05 | Open GSD installs at an exact pin and wires Codex without invalid TOML | behavior | `tests/bats/73-phase51-gsd-codex.bats` + CLI unit tests | ✅ | ⬜ pending |
| 51-04-01 | 04 | 3 | TST-08 / OPS-01 | T-51-06 | Follow-up QA records all affected workflows, limits, and new findings honestly | integration | `./tests/docker/run.sh ubuntu-24.04` + QA report audit | ✅ | ⬜ pending |

*The planner may refine task IDs while preserving coverage of every approved decision and the Phase 51 exit gate.*

---

## Wave 0 Requirements

- [ ] Add or extend targeted Bats fixtures: `tests/bats/71-phase51-hosted-mcp.bats`, `tests/bats/72-phase51-prerequisites.bats`, and `tests/bats/73-phase51-gsd-codex.bats` for Firecrawl/OpenCode OAuth metadata, Playwright status, dependency ownership/escalation, and Open GSD/Codex wiring before implementation tasks rely on them.
- [ ] Add any disposable RC fixture scripts needed for clean temporary homes, redacted credentials, and deterministic cleanup.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Firecrawl OAuth browser consent and API-key fallback | MCP-07 / OPS-01 | Requires user-controlled runtime credential/browser authorization | Run the documented OAuth flow and API-key URL flow in a disposable RC environment; record only redacted success/failure and cleanup. |
| OpenCode GitHub MCP browser authorization | MCP-03 / OPS-01 | OAuth consent and redirect behavior cannot be safely automated with repository credentials | Run `opencode mcp debug github-mcp`, `opencode mcp auth github-mcp`, and one read-only tool call with user-provided access; redact tokens and remove auth state afterward. |
| Final available-scope integration QA | TST-08 | Judgment-driven workflows and productive-time/latest-10 stop rule | Invoke the reusable QA skill, repeat representative co-installed workflows, and record every known/blocked/new/clean idea until the exit gate is met or explicitly handed back. |

---

## Validation Sign-Off

- [ ] All tasks have an automated verify or a documented manual gate.
- [ ] Sampling continuity: no three consecutive tasks without automated verification.
- [ ] Wave 0 covers all missing regression references before implementation.
- [ ] No watch-mode flags.
- [ ] Feedback latency is within the stated limits for local checks.
- [ ] `nyquist_compliant: true` set after plan execution and verification evidence is complete.

**Approval:** pending
