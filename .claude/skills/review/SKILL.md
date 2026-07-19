---
name: review
description: Runs the AgentLinux review feedback loop on changed files before declaring a task complete. Dispatches portable project-scoped reviewer roles through the host agent's native subagent facility (Claude Code, Codex, or another supported host), aggregates free-form feedback, and iterates until remaining comments are not actionable. Invoke after substantive changes to plugin/, tests/, packaging/, or docs/.
---

# AgentLinux Review Feedback Loop

This is an agent-neutral workflow. A reviewer is a role and a rubric, not a
specific CLI. The host agent dispatches the matching roles, reads their
feedback, owns triage, and repeats the relevant passes after valid fixes.

## When to use

Use after any non-trivial change to:

- `plugin/` or `packaging/`
- `tests/`
- durable `docs/`
- project instructions, skills, hooks, or reviewer-role definitions
- the end of every phase (always run `behavior-coverage-auditor` for TST-07)

Skip typo/formatting-only changes, `.planning/` workflow state, and
`.planning/notes/` scratch files unless the task also changes a reviewable
surface.

## Loop

```text
Main agent identifies changed files
  -> dispatch matching reviewer roles in parallel, read-only
  -> collect free-form findings
  -> triage: fix / skip / defer
  -> re-dispatch roles whose domain changed
  -> stop when remaining comments are not actionable
```

Inspect both tracked and untracked changes. `git diff --name-only` alone omits
untracked files; combine it with `git status --short` or an equivalent
worktree inventory.

## Dispatch

The table maps file patterns to portable reviewer roles. Dispatch the
intersection of the changed-file set and the table; do not invoke every role
for every change.

| Changed file pattern | Reviewer roles |
|---|---|
| `^plugin/(bin|lib|provisioner)/.+\.sh$` | `bash-engineer`, `security-engineer`, `qa-engineer`, `ai-deslop`, `dev-docs-auditor` |
| `^plugin/catalog/lib/.+\.sh$` | `bash-engineer`, `security-engineer`, `qa-engineer`, `ai-deslop`, `dev-docs-auditor` |
| `^packaging/curl-installer/.+\.sh$` | `bash-engineer`, `security-engineer`, `ai-deslop` |
| `^plugin/cli/(src|test|scripts)/.+\.(ts|mjs|js)$` | `node-engineer`, `security-engineer`, `qa-engineer`, `ai-deslop`, `dev-docs-auditor` |
| `^plugin/cli/(package\.json|tsconfig\.json|biome\.json|stryker\.config\.json)$` | `node-engineer` |
| `^tests/bats/.+\.bats$` | `qa-engineer`, `behavior-coverage-auditor` |
| `^tests/bats/helpers/.+$` | `qa-engineer`, `bash-engineer`, `ai-deslop` |
| `^tests/(docker|qemu|harness)/.+$` | `qa-engineer`, `bash-engineer`, `ai-deslop` |
| `^plugin/catalog/(agents/.+/.+\.(sh|json)|catalog\.json|schema\.json)$` | `catalog-auditor`, `security-engineer`, `ai-deslop`, `dev-docs-auditor` (add `bash-engineer` for shell recipes) |
| `^plugin/catalog/agents/.+/.+\.(js|mjs|ts)$` | `node-engineer`, `catalog-auditor`, `security-engineer`, `ai-deslop`, `dev-docs-auditor` |
| `^docs/.+\.md$` (not ADRs/research summaries) | `technical-writer`, `fact-checker`, `ai-deslop` |
| `^docs/decisions/.+\.md$` or `^docs/research/.+/SUMMARY\.md$` | `technical-writer`, `fact-checker` |
| `^(AGENTS\.md|CLAUDE\.md|CONTRIBUTING\.md)$` | `technical-writer`, `fact-checker` (add `external-audience-auditor` for contributor/public copy) |
| `^README\.md$` | `technical-writer`, `fact-checker`, `ai-deslop`, `external-audience-auditor` |
| `^\.(claude|codex)/(hooks|skills)/.+$` | `technical-writer`, `fact-checker`, `ai-deslop` (add `bash-engineer` and `security-engineer` for hooks) |
| `^\.claude/agents/.+\.md$` | `technical-writer`, `fact-checker`, `ai-deslop` (add the role's domain reviewer when its rubric changes) |
| `^\.planning/REQUIREMENTS\.md$` | `behavior-coverage-auditor` |
| phase close | `behavior-coverage-auditor` always |

For externally-facing copy, also dispatch `external-audience-auditor`.
This includes top-level README/contribution copy, `docs/internals/`,
`docs/HARNESS.md`, `docs/STABILITY-MODEL.md`, release notes, and user-visible
packaging strings. Skip it for `.planning/`, ADRs, research, internal source
comments, and other explicitly internal material.

## Host dispatch contract

Use the host agent's native subagent mechanism and run independent reviewers in
parallel when possible. The dispatch record must include the changed-file
allowlist, the reviewer role, and a read-only capability profile:

- allow reading/searching and safe deterministic checks;
- deny editing, patching, deleting, committing, pushing, opening PRs, Jira
  writes, package installation, and other external state changes;
- permit shell only for checks that do not mutate the repository or external
  systems, preferably in a disposable temporary directory.

- **Claude Code:** dispatch the named roles through its native project-agent
  mechanism (the `.claude/agents/*.md` role registry).
- **Codex:** dispatch the same roles through Codex's native multi-agent feature
  (`multi_agent`). Call `spawn_agent` once per matched role with `agent_type`
  set to the role name (e.g. `bash-engineer`); run independent roles as parallel
  spawns and collect their results. Codex resolves those `agent_type` values
  from `.codex/agents/*.toml`, which `scripts/sync-codex-agents.sh` generates
  from `.claude/agents/` with `sandbox_mode = "read-only"` (see `docs/codex.md`
  for the generator, the `--check` gate, and the older-schema fallback).
  Do not invoke the Claude CLI, and
  do not substitute the built-in `codex review` command for this project skill.
- **Other hosts:** use their native subagent mechanism and preserve the same
  role names, scopes, and read-only contract.

The canonical role prompts live under `.claude/agents/` for repository
compatibility. They are portable review contracts, not instructions to launch
Claude Code. For role `R`, resolve the repository root and load
`.claude/agents/R.md` as reviewer context (Codex reads the projected
`.codex/agents/R.toml` instead), then pass the changed-file allowlist plus the
read-only profile to the host's native subagent call. A host may expose the
same roles through another registry, but must not fork the rubrics or silently
substitute another agent's CLI.

The read-only capability profile overrides any broader tool declaration in a
role prompt. Hosts must select an explorer/read-only subagent where available,
or explicitly deny write-capable tools before dispatch. A reviewer prompt that
says it may rewrite or edit does not override this contract.

Reviewers are read-only: they may inspect files and run safe deterministic
checks, but must not edit, commit, open a PR, alter Jira, or invoke this skill
recursively. If the host cannot enforce the read-only profile, the main agent
must not dispatch that reviewer with write-capable tools. If the host exposes
no usable subagent facility, the main agent may run the role rubrics itself and
must report a limited pass rather than silently switching to another agent's
CLI.

Every review run records one result per dispatched role: `completed`,
`skipped` with rationale, `unavailable`, or `failed`. An unavailable or failed
`behavior-coverage-auditor` means the TST-07 gate is not GREEN.

## Reviewer output

Each reviewer returns a free-form summary containing:

- concrete findings with `path:line` citations and a failure mode;
- suggested verification or fix where useful;
- clean observations and limitations.

The main agent reads all results before editing. Reviewers are advisors, not
gatekeepers.

## Triage

- **Fix:** concrete, verifiable problems such as shellcheck warnings, missing
  idempotency, swallowed errors, uncovered requirement IDs, unsafe privilege
  boundaries, `sudo npm install -g`, schema failures, asymmetric uninstall, or
  `/usr/local/bin/` shims to agent-owned binaries.
- **Skip:** stylistic preferences, duplicate advice, already-addressed points,
  or comments without a concrete failure mode.
- **Defer:** valid work outside the current task; record it in the phase's
  `deferred-items.md` when appropriate.

After a valid fix, re-dispatch only the roles whose review domain changed.
Completion requires every finding to be fixed, explicitly skipped with a
rationale, or recorded as deferred in the phase artifact. The canonical
deferred record is `.planning/phases/<phase>/deferred-items.md`; if that phase
directory is not in scope, record the item in the task's durable change log or
Jira issue with at least: finding, file/line, reason for deferral, owner or
follow-up phase, and re-check condition. Continue until no untriaged actionable
findings remain; there is no artificial iteration cap.

## TST-07 phase gate

At phase close, run `behavior-coverage-auditor` unconditionally. It must map
every requirement ID and requirement family present in
`.planning/REQUIREMENTS.md`—including newly added families, not only the
original `BHV`, `RT`, `AGT`, `CLI`, `CAT`, and `INST` prefixes—to appropriate
behavior-test, harness, smoke, or artifact evidence. Extract canonical IDs
from requirement declaration lines/headings and traceability entries, not from
incidental prose. Ignore references such as `ADR-###`, version numbers, and
examples that are not declared requirements.

- `TST-07 gate: RED`: add coverage or document a deliberate deferral before
  closing the phase.
- `TST-07 gate: GREEN`: the phase may close; preserve the report when useful.

## References

- `docs/HARNESS.md` §4 — high-level project review contract
- `AGENTS.md` — shared project instructions
- `CLAUDE.md` — Claude Code host adapter
- `docs/codex.md` — Codex host adapter
- `.claude/agents/` — canonical portable reviewer role prompts
- `.codex/agents/` — Codex-format projection of those roles (generated by
  `scripts/sync-codex-agents.sh`)
