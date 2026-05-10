# AgentLinux — Project Context

## Project Identity

AgentLinux v0.3.0 — installable Ubuntu plugin. Provisions an agent user with a
correctly-owned Node.js runtime + a registry CLI for installing agent tools.
Pivoted from custom distro (v0.2.0) on 2026-04-18. See
`@.planning/PROJECT.md` for full scope.

## Where Things Live

- `plugin/` — shippable installer code (bash entrypoint, lib helpers, provisioner
  steps, catalog, registry CLI in `plugin/cli/`)
- `tests/bats/` — behavior-contract suite (BHV-XX / RT-XX / AGT-XX / CLI-XX / CAT-XX / INST-XX)
- `tests/harness/` — harness meta-tests (Phase 1 acceptance gate)
- `tests/docker/` — fast CI harness (Ubuntu 22.04 + 24.04 + 26.04 matrix, every PR)
- `tests/qemu/` — release-gate harness (fresh cloud images, nightly + release)
- `packaging/` — curl-pipe-bash installer + optional fpm .deb wrapper
- `docs/` — reference documentation (`HARNESS.md`, `decisions/`, `research/`, `proposals/`, `reviews/`)
- `.planning/` — GSD workflow state (PLAN.md, STATE.md, ROADMAP.md) — not documentation
- `.claude/agents/` — project-scoped review subagents (Plan 01-03)
- `.claude/skills/` — project-scoped skills (Plan 01-04)
- `.github/workflows/` — CI (test, nightly-qemu, nightly-mutation, release)
- `agents/software-engineer/AGENTS.md` — Paperclip SoftwareEngineer agent type
  contract (per-issue lifecycle, back-pressure checklist, GSD reconciliation
  rules). Read by every engineer worktree on wake. Edits ride in normal PRs.

## Critical Rules (non-obvious)

- **Never `sudo npm install -g` anywhere.** Always `sudo -u agent -H npm install -g`.
  This is the bug class AgentLinux exists to eliminate (EACCES + recursive-shim).
- **Behavior tests in `tests/bats/` are the spec.** Implementation may change freely
  while the suite stays green. Do not pin implementation choices (npm vs native
  installer, sudo vs no-sudo) as requirements.
- **No agent is installed by default.** Claude Code, GSD, and Playwright are
  available in the catalog; users opt in via `agentlinux install <name>`.
- **Docker-only test runs are insufficient.** QEMU suite must be green before any
  release — Docker can't reproduce systemd, locale generation, cloud-init paths.
- **Every release tarball ships with a sibling `.sha256`.** The curl-installer at
  `packaging/curl-installer/install.sh` must verify it before executing.
- **No wrapper shims at `/usr/local/bin/`** pointing to agent-owned binaries — the
  exact anti-pattern that breaks Claude Code self-update.

## Review Loop

Before reporting any task complete, run the review feedback loop on all changed
files per `@docs/HARNESS.md` §4. Triggered by this instruction (primary) plus a
one-shot Stop-hook reminder at `.claude/hooks/review-reminder.sh` (backstop).
ADR-010 (refined 2026-05-02): reviewer-invoking hooks remain rejected; reminder
hooks with a `stop_hook_active` guard are allowed. See
`.claude/skills/review/SKILL.md` for the convention (arrives in Plan 01-03).

Reviewers applied by file type:

- Bash → `bash-engineer`, `security-engineer`, `qa-engineer`, `ai-deslop`, `dev-docs-auditor`
- TS/JS → `node-engineer`, `security-engineer`, `qa-engineer`, `ai-deslop`, `dev-docs-auditor`
- Bats spec (`tests/bats/*.bats`) → `qa-engineer`, `behavior-coverage-auditor`
  (the spec is the spec — no `ai-deslop`)
- Bats helpers + Docker/QEMU harness → `qa-engineer`, `bash-engineer`, `ai-deslop`
- Catalog recipes → `catalog-auditor`, `security-engineer`, `ai-deslop`, `dev-docs-auditor`
- Docs → `technical-writer`, `fact-checker`, `ai-deslop` (skip for ADRs and
  research summaries)

`dev-docs-auditor` keeps `docs/internals/<component>.md` in sync when changes
touch `plugin/bin/`, `plugin/lib/`, `plugin/provisioner/`, `plugin/cli/src/`,
`plugin/catalog/`, or `packaging/curl-installer/`. Skips on pure refactors,
typos, or comment-only changes. See `.claude/skills/dev-docs/SKILL.md` for the
docs contract and the source-path → doc-path dispatch table.

Main agent owns triage: fix what's valid, skip what's noise, iterate until the
remaining comments are not actionable.

Before opening an MR, the global `pre-delivery-cleanup` skill provides a
self-review pass that pairs well with `ai-deslop` — invoke it when the
implementation is finished and tests pass but before the final commit.

## Session Tracking

Concrete deliverables (MR, doc, decision artifact, ticket in another project)
get tracked in Jira project **AL** (copiedwonder.atlassian.net, board 2) per
`@.claude/skills/session-tracker/SKILL.md`. A second one-shot Stop-hook reminder
at `.claude/hooks/session-tracker-reminder.sh` (backstop, same ADR-010 refinement
that allows the review-reminder hook) nudges Claude to invoke the skill before
stopping. Skip for research-only / Q&A / `.planning/`-only sessions — request
stop again to pass through.

## Commands

```bash
./tests/docker/run.sh ubuntu-24.04        # Run bats inside Docker (Ubuntu 24.04)
cd plugin/cli && pnpm test                 # CLI unit tests (node:test)
pre-commit run --all-files                 # Lint bash + TS + catalog schema
./scripts/build-release.sh vX.Y.Z          # Build the release tarball + .sha256
bash tests/harness/run.sh                  # Run harness meta-tests (Phase 1)
```

## Pointers

- `@.planning/ROADMAP.md` — phase plan (1 Harness → 2 Installer → 3 Node → 4 CLI → 5 Agents → 6 Release)
- `@.planning/REQUIREMENTS.md` — behavior contract (BHV/RT/AGT/CLI/CAT/INST/HRN/TST/DOC)
- `@docs/HARNESS.md` — authoritative harness spec (§1 layout, §2 docs, §3 systems, §4 review, §5 skills, §6 this file, §7 checklist, §8 criteria)
- `@docs/research/v0.3.0/SUMMARY.md` — v0.3.0 research synthesis
- `@docs/decisions/` — ADR-001..ADR-015 (ADR-015: developer internals docs)
- `@docs/internals/` — developer documentation (what each AgentLinux component
  does and why; product-perspective lens; insight source for blog/email/website)
- Skills: `.claude/skills/agentlinux-installer/`,
  `.claude/skills/behavior-test-contract/`, `.claude/skills/catalog-schema/`,
  `.claude/skills/dev-docs/`, `.claude/skills/qemu-harness/`,
  `.claude/skills/review/`, `.claude/skills/workspace-cleanup/`

---
*Last updated: 2026-04-18 — Phase 1 Harness Setup (Plan 01-01).*
