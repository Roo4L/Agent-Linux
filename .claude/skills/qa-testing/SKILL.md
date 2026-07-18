---
name: qa-testing
description: Run black-box, user-oriented QA against AgentLinux catalog packages and realistic co-install workflows.
---

# AgentLinux catalog-package QA

Use this skill for a curious, evidence-driven QA session against the installed
AgentLinux product. The subject is the catalog packages and the workflows users
build with them. It is not a GSD-file audit, a repository-quality audit, a
replacement for the behavior suite, or a claim that the host can run QEMU.

The campaign is observation-only: reproduce behavior, analyze it, preserve
redacted evidence, classify findings, and hand them back for later follow-up.
Keep product, recipe, test, and documentation changes out of the discovery
campaign.

## Invocation and defaults

At invocation, state in free-form text:

- the unit or package scope (release candidate, milestone, package, or workflow);
- any Ubuntu distribution or workflow focus;
- credentials already authorized for this session and their intended minimal use;
- optional changes to the default productive window or clean-idea threshold.

The normal stop defaults are **30 minutes of productive QA activity** and the
**latest 10 distinct completed test ideas** with no newly discovered issue.
These are agent-orchestrated conditions, not environment variables, a scripted
timer, or a round counter. A free-form invocation may request different
thresholds; record the override in the report and apply it consistently.

## Scope and inventory

The included catalog inventory is:

`claude-code`, `gsd`, `playwright-cli`, `codex`, `gemini-cli`, `opencode`,
`qwen-code`, `ccusage`, `rtk`, `gh`, `glab`, `trivy`, `gitleaks`, `sentry-cli`,
`chrome-devtools-mcp`, `context7`, `github-mcp`, `sentry-mcp`, `firecrawl-mcp`,
`slack-mcp`, `linear-mcp`, `jira-atlassian-mcp`, and `spec-kit`.

The explicit exclusions are:

- `openclaw` — its primary systemd service is unavailable in the requested
  Docker environment;
- `hermes-agent` — its primary systemd service is unavailable in that Docker
  environment;
- `test-dummy` — a fixture, not a product package.

The two daemon exclusions are coverage boundaries, not passing results. Do not
start a fake daemon or infer systemd/QEMU behavior from Docker. QEMU remains
the authority for those paths.

Derive the scenario ledger from `plugin/catalog/catalog.json` at session start.
Do not silently omit an included entry because its operation is inconvenient.

## Per-package evidence contract

For every included package, record one materially distinct lifecycle idea with:

1. fresh-container install through the user-facing AgentLinux path;
2. canonical command, version, path, agent ownership, and absence of a forbidden
   `/usr/local/bin/` wrapper shim;
3. a realistic primary operation beyond `--help` or `--version`;
4. removal, post-removal residue, preserved user content, sibling state, and an
   idempotent second removal where meaningful.

Record the exact distro/container, package pin, install order, operation, output
artifact, productive interval, novelty result, finding ID, and cleanup result.
Use fresh disposable containers for order-sensitive ideas. Set
`TERM=xterm-256color`, keep ANSI/color enabled where relevant, and capture both
an 80-column default terminal and a wider documented geometry for at least one
real PTY flow. Gate input on observed prompts and distinguish live work from an
apparent freeze.

Category-specific operation examples:

- coding agents: an authenticated tiny prompt and, where relevant, a genuine PTY
  prompt/streaming exchange;
- `gsd`: create or inspect a temporary user workflow and exercise its installed
  skill/command surfaces;
- `playwright-cli`: launch a local page and perform a meaningful interaction;
- `ccusage`: parse a seeded local usage record and inspect the reported result;
- `spec-kit`: scaffold a temporary project and inspect the generated workflow;
- `rtk`: run representative commands through its hook/rewire flow and inspect
  the resulting command behavior;
- `trivy` and `gitleaks`: scan a small fixture with both a finding and an empty or
  malformed input case;
- `gh`, `glab`, and `sentry-cli`: perform the smallest useful read-only operation
  with the authorized account;
- MCP entries: register the server, verify it is visible to a compatible client,
  and make a keyless or authenticated read-only tool call as the service allows.

Help/version output can establish identity, but never establishes operational
coverage by itself.

## Workflow combinations

Choose combinations from real shared workflows rather than an arbitrary pairwise
matrix. At minimum cover:

- coding-agent consumers with `gsd` and `playwright-cli`, including provider-first
  and consumer-first installation where the shared skill/config surface matters;
- every compatible cross-agent MCP fan-out provider against each compatible
  installed coding agent (`claude-code`, `codex`, `gemini-cli`, `opencode`, and
  `qwen-code` as applicable), in both installation orders;
- repeated MCP reconciliation, duplicate registration, remove-one-keep-sibling,
  unrelated user-config preservation, and clean final removal;
- `rtk` with the installed coding-agent fleet, unrelated hook entries, repeated
  wiring, and sibling-preserving removal;
- one realistic npm-plus-binary-plus-workflow composition, checking PATH,
  ownership, configuration, update-like behavior, and cleanup together.

For a shared surface, add a retry after failed or interrupted progress, repeated
install/reinstall or upgrade-like behavior, empty/malformed input, and partial
cleanup. Add these only where the state transition can expose a user-visible
defect; do not inflate coverage with meaningless pairs.

## Credential checkpoint and blocking

Before package operations, inventory the credential classes required by the
selected real scenarios and ask the user for runtime authorization. Likely
classes are:

- model/provider access for authenticated coding-agent prompts;
- GitHub and GitLab read-only access;
- Sentry read-only access;
- Slack, Linear, and Atlassian/Rovo MCP access;
- any other provider or account that a selected operation explicitly requires.

Ask only for the classes needed by the chosen ideas and explain the minimal
operation. Never request secrets be committed, written to a recipe, pasted into
the report, or copied into a persistent fixture. Inject authorized values only at
runtime and redact command output, transcripts, screenshots, and config diffs.
Record only credential class plus requested/provided/blocked status.

If the user does not provide a needed credential, mark the affected idea
`blocked` and stop that path. Continue only with genuinely independent local or
keyless ideas; a help/version launch is not a substitute. If a package requests
an unexpected credential, pause that idea, record the unexpected requirement as a
block, and ask the user before continuing it. Do not silently downgrade coverage.

## Finding and novelty rules

Each finding records:

| Field | Required content |
|---|---|
| ID | Stable finding identifier |
| Severity | blocker, high, medium, low, or observation |
| Scope | direct package defect or adjacent workflow impact |
| Affected surface | package(s), workflow, distro, and install order |
| Reproduction | exact repeatable user-facing steps |
| Evidence | redacted output, transcript, config diff, or artifact path |
| First seen | test-idea ID and productive interval |
| Classification | known reproduction or newly discovered/reproducible issue |
| Disposition | deferred follow-up, ticket/phase handback, or maintainer decision |
| Residual risk | what remains unproven |

Only a newly reproducible issue is new. Reproducing an already-known issue does
not reset the stop measures and counts clean for new-issue discovery; link its
existing finding and preserve the additional evidence. Expected negative behavior
is clean when it matches the contract. A blocked or incomplete idea counts as
neither clean nor productive while the block prevents progress.

## Productive stop gate

Maintain two auditable records throughout the session:

1. an activity log with active execution, observation, analysis, and reproduction
   intervals; and
2. an idea ledger where each materially different user-facing hypothesis ends as
   `clean`, `known`, `new`, `blocked`, or `incomplete`.

Productive time excludes chat idle time, waiting for user input, usage-limit
pauses, and external blocks that prevent QA work. A long-running install or
operation contributes active time while it runs, but contributes one clean idea
only after it completes cleanly. A newly discovered reproducible issue resets
both measures. Continue until both the configured productive-time threshold and
the configured latest-clean-idea threshold hold since the latest new issue. If
the gate is not met, hand back the unmet arithmetic instead of declaring success.

## Handback template

End with a report containing:

```markdown
## Session outcome
- Unit under test:
- Thresholds and free-form overrides:
- Stop arithmetic since the latest new issue:
- Productive result: active minutes / excluded intervals / latest clean ideas:

## Scenario ledger
| Idea | Packages | Distro | Install order | Operation | Credential class | Active interval | Novelty | Finding | Cleanup | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|

## Findings
| ID | Severity | Scope | Affected surface | Reproduction | Evidence | First seen | Classification | Disposition | Residual risk |
|---|---|---|---|---|---|---|---|---|---|

## Known-issue links
- Finding and additional reproductions:

## Blocked ideas and credentials
- Credential class, requested/provided/blocked status, affected idea IDs:
- Unexpected credential requests and user checkpoints:

## Exclusions
- `openclaw`: Docker has no usable primary systemd service.
- `hermes-agent`: Docker has no usable primary systemd service.
- `test-dummy`: fixture, not a product package.

## Coverage limits
- Docker distros and fresh-container boundaries:
- QEMU/systemd paths not covered:
- PTY setup: TERM, geometry, ANSI/color, prompt gating, live output:
- Invocation modes and workflows not exercised:
- Residue, sibling-preservation, and `/usr/local` checks:
```

Never claim that unexecuted credentialed operations, excluded daemon services,
or QEMU-only behavior passed.
