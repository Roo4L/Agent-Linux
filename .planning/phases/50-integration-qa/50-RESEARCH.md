# Phase 50: Integration QA — Research

**Researched:** 2026-07-18
**Question:** What must be known to plan a reusable, black-box package-QA campaign that finds emergent AgentLinux catalog defects?

## Findings

### Authoritative scope and package inventory

Phase 50 is a user-oriented QA sweep of the AgentLinux catalog, not a repository-quality audit, GSD-file audit, behavior-suite rerun, QEMU-host-capability test, or implementation exercise. The execution must test these 23 real catalog entries:

| Category | Entries | Representative operation beyond help/version |
|---|---|---|
| Coding agents | `claude-code`, `codex`, `gemini-cli`, `opencode`, `qwen-code` | Run a tiny non-interactive prompt against a local fixture; for interactive clients, observe a genuine PTY prompt and streamed output. Provider credentials are required for a real model reply; absence blocks that path rather than silently downgrading it. |
| Workflow/browser | `gsd`, `playwright-cli`, `ccusage`, `spec-kit` | Run a local GSD/skill discovery or temporary-project workflow; exercise Playwright against a local page; parse seeded Claude usage data; scaffold and inspect a temporary spec project. |
| Cross-agent proxy/devops | `rtk`, `gh`, `glab`, `trivy`, `gitleaks`, `sentry-cli` | Run RTK against representative commands and inspect hook behavior; scan local files/repositories with Trivy and Gitleaks; perform read-only authenticated GitHub/GitLab/Sentry operations where credentials are available. |
| MCP | `chrome-devtools-mcp`, `context7`, `github-mcp`, `sentry-mcp`, `firecrawl-mcp`, `slack-mcp`, `linear-mcp`, `jira-atlassian-mcp` | Install and inspect registration in each installed MCP-capable agent; exercise keyless/local capability where the service supports it; authenticate and make a minimal read-only tool call when required. OAuth/API credentials are execution-time inputs; a newly encountered credential requirement blocks the idea and is reported. |
| Excluded | `openclaw`, `hermes-agent`, `test-dummy` | `openclaw` and `hermes-agent` require systemd services unavailable in the requested Docker environment; they are a declared coverage boundary, not a pass/fail result. `test-dummy` is a fixture, not a product package. |

The inventory is derived from `plugin/catalog/catalog.json`; the plan should re-read it at execution time so package pins and recipe metadata cannot silently drift from the ledger.

### Container and harness seams

- Use fresh RC Docker containers for every order-sensitive scenario. Ubuntu 24.04 receives the complete included-package campaign; Ubuntu 22.04 and Ubuntu 26.04 receive targeted distro-sensitive checks selected from the risk ledger. Do not reuse the stale containers left by earlier exploratory work as fresh evidence.
- `tests/docker/rc-sandbox.sh` is the closest existing AgentLinux installation seam and can provide a persistent interactive container, but its documented systemd/logind limitation means it cannot establish daemon correctness.
- `tests/docker/run-smoke.sh` demonstrates disposable provisioning and credential forwarding by named environment variables. It is a pattern for safe setup, not a substitute for package-specific user workflows.
- `tests/bats/helpers/tty-driver.py` allocates a real PTY, gates input on observed output, and bounds waits. Reuse that primitive or an equivalent implementation for interactive-agent checks; a pipe transcript is not evidence of real terminal behavior.
- Existing Bats, CLI unit, and harness suites are supporting evidence only. They answer repository regression questions, whereas this phase must drive installed user-facing commands and record observations. Running `tests/docker/run.sh` alone does not satisfy this phase.

### Scenarios that provide high signal

Every included entry needs an install → verify ownership/path/version → realistic operation → remove flow. Each flow should also probe sensible negative and lifecycle cases when applicable: repeated install, reinstall or upgrade-like invocation, malformed/empty local input, retry after a failed operation, interrupted/partial progress, and cleanup after removal. The QA agent records behavior; it does not fix source, recipes, tests, or documentation during the sweep. Fixes are a separate follow-up after the report.

High-value co-install workflows are based on real shared surfaces rather than an arbitrary pairwise matrix:

1. Install the coding-agent fleet in both orders where the workflow needs it, then install/remove `rtk` and assert hook/config convergence, unrelated user entries preserved, sibling hooks surviving removal, and no `/usr/local/bin` shims.
2. Install `gsd` and `playwright-cli` with coding agents, then exercise the skill/command files from the agents that should consume them; repeat provider-first and consumer-first order and remove one provider while siblings remain.
3. Install every MCP fan-out provider against the compatible installed coding-agent fleet, in provider-first and agent-first order. Check each agent’s own config, duplicate registration behavior, removal symmetry, preservation of unrelated configuration, and a surviving sibling provider. Do not claim a server operation passed merely because registration JSON exists.
4. Combine one binary scanner or VCS CLI, one npm tool, and one workflow/coding agent around a temporary repository/fixture. Exercise PATH resolution, ownership, local data, output composition, and removal without corrupting the remaining tools.
5. Include reinstall/retry/removal permutations for the highest-risk shared config surfaces (`rtk`, GSD, Playwright, and MCP fan-out), and make each idea one ledger unit with a clear clean/new-known/blocked outcome.

### Credential inventory and blocking behavior

The execution plan must begin with a credential inventory and ask the user for the credentials needed by the selected scenarios. Likely inputs include model/provider credentials for coding-agent replies, GitHub token/OAuth, GitLab token, Sentry token, and OAuth/API access for GitHub MCP, Sentry MCP, Slack MCP, Linear MCP, and Atlassian Rovo MCP. Keyless Context7/Firecrawl/registration paths and local scanner/fixture paths should run without credentials when their documented contract allows it; optional credentials should not be invented.

Secrets must be injected only at runtime, never committed, embedded in fixtures, printed in reports, or copied into generated config. If an operation asks for a credential not in the inventory, the test is blocked and the user is asked for that credential. The plan must not silently skip, fake, downgrade, or treat an unauthenticated help/version path as equivalent coverage.

### Productive stop protocol

The reusable skill and report must use defaults of **30 minutes of productive QA activity** and **10 latest distinct test ideas without a new issue**. These are not script environment variables and not a fixed rounds counter; a user may override them in free-form text when invoking the skill.

- Productive time is active execution, observation, result analysis, and issue reproduction. Chat idle time, usage-limit pauses, user-input waiting, and external blocks do not count.
- A long-running test contributes productive time while it is executing, but contributes one clean idea only when it completes without surfacing a new issue.
- A newly reproducible issue resets both the productive timer and the consecutive clean-by-novelty sequence.
- Reproducing an already-known issue does not reset either measure and counts as clean for discovery; link it to the existing finding instead of creating a duplicate.
- An expected negative result is clean when it matches the contract. A blocked or incomplete idea is neither clean nor productive while blocked.
- Stop only after both thresholds are true since the latest new finding. A report must show active intervals, test-idea IDs, novelty classification, resets, and the final stop decision.

## Planning implications

1. Rewrite the reusable `.claude/skills/qa-testing/SKILL.md` around the package inventory, operation scenarios, credential gate, workflow-based co-install matrix, observation-only rule, and productive stop protocol. Remove the old `QA_ROUND_MINUTES`/`QA_QUIET_ROUNDS` round-counter contract rather than retaining it as a competing method.
2. Create an execution plan that separates preparation/credential request, 24.04 package campaign, 22.04/26.04 targeted checks, and report/verification. It must provide a scenario ledger instead of a checklist-only claim.
3. The report needs per-idea evidence: package(s), distro/container, install order, operation, command/output artifact location, credential class (not secret), duration of productive activity, novelty result, finding ID if any, and cleanup result. It must separately list known-issue reproductions, blocked ideas, exclusions, and residual coverage.
4. The phase is observation-only. Do not make source fixes as findings appear; record severity, reproduction, scope, evidence, and recommended follow-up. The later fix work can be a separate phase or ticket.
5. Docker results must be described as Docker results. `openclaw` and `hermes-agent` remain explicitly excluded until a systemd-capable environment is available; no local QEMU capability claim is needed to justify that boundary.

## Validation Architecture

### Observable truths

- The skill is discoverable from `CLAUDE.md`, has one canonical `.claude/skills/qa-testing/SKILL.md`, and is linked for Codex according to project convention.
- The skill names the 23 included entries, the three exclusions, realistic operations beyond help/version, credential blocking, workflow-based co-install coverage, and the exact productive-stop semantics.
- The QA report is an evidence ledger, not a pass-by-checklist assertion: every attempted idea has a clean/new-known/blocked/incomplete classification, and every new issue has reproducible evidence and a disposition.
- The report distinguishes active productive time from waiting/blocked time and proves the final 30-minute + latest-10 clean-by-novelty stop decision, or explains why execution is blocked before it can be reached.
- Removal and co-install observations verify sibling preservation, unrelated-config preservation, path/ownership behavior, and absence of forbidden `/usr/local` shims for included packages.

### Verification levels

| Level | Method | What it proves |
|---|---|---|
| Static skill contract | `test`, `grep`, `bash -n`, symlink resolution | The reusable workflow is discoverable and contains the required scope, credential, ledger, and stop-rule language. |
| Catalog inventory | Parse `plugin/catalog/catalog.json` and compare against the scenario ledger | No included real entry is silently omitted and only the three declared exclusions are out of scope. |
| Package integration | Fresh Ubuntu 24.04 RC containers and targeted 22.04/26.04 containers | Install, operation, lifecycle, co-install, configuration, and removal behavior as a user observes it. |
| Interactive UX | Real PTY with `TERM=xterm-256color`, color enabled, 80-column default plus wider case | Prompt gating, streamed output, terminal geometry, and apparent-freeze behavior are actually exercised. |
| Credentialed operation | User-provided runtime credentials, with redacted evidence | Authenticated read-only/minimal workflows are exercised without secret leakage; missing/unexpected credentials remain explicit blockers. |
| Coverage boundary | Report and verification artifact | Docker-only and systemd/QEMU-only reachability are not conflated; excluded daemon packages are visible. |

### Risks and mitigations

- **False confidence from help/version:** require category-specific operations and lifecycle evidence for every included package.
- **State contamination:** use fresh containers per order-sensitive idea and assert post-remove residue/sibling state.
- **Credential leakage:** use named runtime inputs, redact outputs, and reject secrets in repository artifacts.
- **Checklist theater:** maintain the test-idea ledger and novelty counter; no fixed number of packages or commands alone declares completion.
- **Idle time mistaken for QA:** log productive intervals separately from chat/user/external waits and exclude the latter from the timer.
- **Docker overclaim:** mark daemon packages and systemd-user behavior outside this campaign; do not infer QEMU results.

## Sources

- `AGENTS.md` — project contracts and review/session rules
- `.planning/phases/50-integration-qa/50-CONTEXT.md` — locked Phase 50 scope and decisions
- `.planning/ROADMAP.md` and `.planning/REQUIREMENTS.md` — TST-08, OPS-01, catalog and cross-agent contracts
- `.claude/skills/qa-testing/SKILL.md` — prior reusable workflow, used only to identify stale round-counter language
- `tests/docker/rc-sandbox.sh` and `tests/docker/run-smoke.sh` — Docker setup seams
- `tests/bats/helpers/tty-driver.py` — genuine PTY interaction primitive
- `plugin/catalog/catalog.json`, `plugin/catalog/schema.json`, and `plugin/catalog/agents/` — package inventory and recipe contracts
