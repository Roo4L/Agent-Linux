# AgentLinux — Project Context

> Shared, tool-neutral project context. Read by every coding agent working in
> this repo: Codex CLI reads this file natively as `AGENTS.md`; Claude Code reads
> it via `@AGENTS.md` at the top of `CLAUDE.md`. Agent-specific mechanics live in
> each tool's own file (`CLAUDE.md` for Claude Code; `.codex/` for Codex — see
> `docs/codex.md`). Keep this file agent-neutral, and under 32 KiB — Codex
> truncates project docs beyond that. Note: the `@`-prefixed paths below are
> Claude Code import markers; Codex reads them as plain path references (it does
> not expand imports), so they resolve either way.

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
- `docs/` — reference documentation (`HARNESS.md`, `codex.md`, `decisions/`, `research/`, `proposals/`, `reviews/`)
- `.planning/` — GSD workflow state (PLAN.md, STATE.md, ROADMAP.md) — not documentation
- `.claude/agents/` — project-scoped review subagents (Claude Code)
- `.claude/skills/` — project-scoped skills (canonical copy; Codex loads the same
  skills via symlinks under `.codex/skills/`)
- `.github/workflows/` — CI (test, nightly-qemu, nightly-mutation, release)
- `agents/software-engineer/AGENTS.md` — Paperclip SoftwareEngineer agent type
  contract (per-issue lifecycle, back-pressure checklist, GSD reconciliation
  rules). Read by every engineer worktree on wake. Edits ride in normal PRs.
  Note: this is a *nested* AGENTS.md — Codex only applies it when the working
  directory is under `agents/software-engineer/`; it does not override this
  root file for the rest of the repo.

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
files per `@docs/HARNESS.md` §4. The loop applies reviewers matched to the changed
file types (bash, TS/JS, bats spec, catalog recipes, docs, externally-facing
copy), then the main agent triages: fix what's valid, skip noise, iterate until
the remaining comments are not actionable. Reviewer-invoking hooks are rejected;
the loop is triggered by this instruction (primary) plus a one-shot reminder hook
(backstop) — see ADR-010 (refined 2026-05-02).

How each agent runs the loop:

- **Claude Code** spawns the project-scoped reviewer subagents matched by file
  type via the `/review` skill. The full file-type → reviewer dispatch table
  lives in `CLAUDE.md`.
- **Codex** runs `codex review` for a built-in review pass, using the same
  file-type → concern mapping as its checklist. (Codex has no equivalent to the
  project reviewer subagents; the deep multi-agent loop is Claude Code's.)

Before opening an MR, run a self-review pass to strip AI slop — the
`pre-delivery-cleanup` skill (Claude Code) or `codex review` (Codex).

## Session Tracking

Concrete deliverables (MR, doc, decision artifact, ticket in another project) get
tracked in Jira project **AL** (copiedwonder.atlassian.net, board 2) via the
`session-tracker` skill. Skip for research-only / Q&A / `.planning/`-only
sessions. Each agent carries a one-shot Stop-hook reminder that nudges this
before stopping — `.claude/hooks/session-tracker-reminder.sh` for Claude Code,
`.codex/hooks/session-tracker-reminder.sh` for Codex.

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
- `@docs/codex.md` — Codex CLI support (install, AGENTS.md, skills, Stop hooks)
- `@docs/research/v0.3.0/SUMMARY.md` — v0.3.0 research synthesis
- `@docs/decisions/` — ADR-001..ADR-016 (ADR-016: developer internals docs)
- `@docs/internals/` — developer documentation (what each AgentLinux component
  does and why; product-perspective lens; insight source for blog/email/website)
- Skills: `.claude/skills/agentlinux-installer/`,
  `.claude/skills/behavior-test-contract/`, `.claude/skills/catalog-schema/`,
  `.claude/skills/dev-docs/`, `.claude/skills/planning-workflow/`,
  `.claude/skills/qemu-harness/`, `.claude/skills/review/`,
  `.claude/skills/qa-testing/`, `.claude/skills/workspace-cleanup/`

---
*Last updated: 2026-07-18 — added Codex CLI support alongside Claude Code.*
