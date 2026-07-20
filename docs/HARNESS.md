# Harness Engineering: Agent-Driven AgentLinux Plugin Development

## Purpose

This document specifies the project structure, tooling, and review processes required to run AgentLinux v0.3.0 development through supported coding-agent hosts, including Claude Code and Codex. Goal: agents run longer, produce better results, and ship faster — while humans retain decision authority over irreversible actions (releases, destructive migrations, schema breaks).

**Scope:** Project organization, code quality infrastructure, documentation structure, and the automated review feedback loop. Not the installer design itself (that's `.planning/REQUIREMENTS.md` + `.planning/ROADMAP.md`).

**Reference template:** Adapted from the ELS-OS-Migration-to-PatchFlow HARNESS.md (Python/API/DB) for AgentLinux's stack (bash installer + Node.js/TypeScript registry CLI, no database, minimal external APIs).

---

## 1. Project Organization

### 1.1 Repository Structure

The repo root is a **workspace** — an umbrella for the plugin code, distribution wrappers, docs, tests, and any peer repos we clone during development (e.g. the Claude Code repo for reference, GSD for catalog-recipe inspiration, a scratch Ubuntu base image for local debugging). The plugin itself is the top-level subject; tests, packaging, docs, and planning state all live as peer concerns.

**Target layout:**

```
agent-linux/                            # Workspace root
├── AGENTS.md                           # Shared project context and critical rules
├── CLAUDE.md                           # Claude Code host adapter (< 150 lines)
├── README.md                           # User-facing README
├── plugin/                             # The installable plugin — bash installer + Node CLI
│   ├── bin/
│   │   └── agentlinux-install          # Installer entrypoint (bash)
│   ├── lib/                            # Shared bash helpers (logging, idempotency, as_user)
│   │   ├── log.sh
│   │   ├── idempotency.sh
│   │   ├── as_user.sh
│   │   └── distro_detect.sh
│   ├── provisioner/                    # Ordered installer steps (bash)
│   │   ├── 10-agent-user.sh
│   │   ├── 30-nodejs.sh
│   │   ├── 40-path-wiring.sh
│   │   └── 50-registry-cli.sh
│   ├── cli/                            # Node.js/TS registry CLI — `agentlinux`
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   ├── src/
│   │   │   ├── index.ts                # Entry — Commander.js setup
│   │   │   ├── commands/               # list / adopt / install / remove / upgrade / pin
│   │   │   ├── catalog.ts              # JSON Schema-validated catalog reader
│   │   │   └── runner.ts               # Dispatches to catalog/agents/<name>/install.sh
│   │   └── test/                       # node:test unit tests for the CLI
│   └── catalog/                        # Agent recipe catalog
│       ├── schema.json                 # JSON Schema 2020-12 contract
│       ├── catalog.json                # Curated catalog entries (none installed by default)
│       └── agents/
│           ├── claude-code/install.sh
│           ├── gsd/install.sh
│           └── playwright-cli/install.sh         # Browser-access tool for agents
├── packaging/                          # Distribution wrappers
│   ├── curl-installer/
│   │   └── install.sh                  # SHA256-verified downloader; execs plugin/bin/agentlinux-install
│   └── deb/                            # Optional fpm wrapper for .deb distribution
├── tests/                              # Behavior-contract test suite (primary v0.3.0 deliverable)
│   ├── bats/                           # Behavior-contract files (IDs in test names)
│   │   └── helpers/                    # Shared assertions and fixtures
│   ├── docker/                         # Fast CI harness — Dockerfile per Ubuntu version
│   │   ├── Dockerfile.ubuntu-22.04
│   │   ├── Dockerfile.ubuntu-24.04
│   │   ├── Dockerfile.ubuntu-26.04
│   │   └── run.sh                      # Orchestrates: build image → run installer → run bats
│   └── qemu/                           # Definitive release-gate harness — cloud-image VMs
│       ├── boot.sh                     # Fresh Ubuntu cloud image → SSH → install → bats
│       └── cloud-init/
├── website/                            # (existing v0.1.0) Landing page — agentlinux.org
│   ├── index.html
│   └── assets/
├── docs/                               # All reference documentation (see §2)
│   ├── README.md                       # Index
│   ├── HARNESS.md                      # This file
│   ├── decisions/                      # ADRs
│   ├── research/                       # Archived + active research outputs
│   ├── proposals/                      # Design proposals pre-ADR
│   ├── analysis/                       # SUMMARY.md, gap analyses
│   └── reviews/                        # Review-loop outputs worth preserving
├── .planning/                          # GSD operational state (not reference material)
├── .claude/                            # Claude Code project config
│   ├── agents/                         # Portable reviewer role prompts (§4)
│   ├── skills/                         # Project-scoped skills (§5)
│   └── settings.json
├── .github/
│   └── workflows/
│       ├── test.yml                    # Docker test matrix on every PR
│       ├── nightly-qemu.yml            # QEMU release-gate suite
│       └── release.yml                 # Tag → build tarball + .deb → GitHub Release
└── packer/                             # (existing v0.2.0 — retired with pivot, keep for reference)
```

**Key decisions:**

- **Root is a workspace, not a single Node project.** No `package.json` or `tsconfig.json` at the root. Those live inside `plugin/cli/` so `pnpm install` in that directory only touches the CLI. This keeps the root clean for peer repos we may clone during development (Claude Code repo, example installers, scratch Ubuntu test images).
- **`plugin/` is the shippable artifact.** Everything in `plugin/` is what goes into the release tarball. `packaging/curl-installer/install.sh` downloads that tarball and execs `plugin/bin/agentlinux-install`.
- **`tests/` is separate from `plugin/`.** Tests never ship. Black-box: they run against an *installed* `plugin/`, not against source.
- **`docs/` for reference, `.planning/` for workflow state.** Identical routing rule to the reference: if the output of a task is a document intended to be read later (ADR, research report, design proposal, review summary), it goes in `docs/`, even as a draft. `.planning/` holds PLAN.md, STATE.md, config — workflow machinery, not documentation.
- **Existing `packer/` stays in-tree as read-only reference** until v0.3.1 when we can decide whether to delete it. It documents the retired distro path and contains provisioner scripts that inform the plugin's installer logic.

### 1.2 Code Quality: Pre-commit

Three languages in this project: **bash** (installer + provisioner scripts), **TypeScript/JavaScript** (registry CLI), and **JSON** (catalog + config). One toolchain per language.

| Language | Lint | Format | Notes |
|---------|------|--------|-------|
| Bash | `shellcheck` | `shfmt` | `--language-dialect bash` (not POSIX); `-i 2` for 2-space indent |
| TS/JS | `biome` | `biome` | One tool instead of eslint+prettier; fast; Rust-based |
| JSON | `biome` + JSON Schema validation | `biome` | Catalog entries validated against `plugin/catalog/schema.json` in pre-commit |
| Bats | (bats-core has no lint) | `shfmt` | Treat `.bats` files as bash for formatting |

```yaml
# .pre-commit-config.yaml
default_language_version:
  node: '22'

repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-added-large-files
      - id: check-merge-conflict
      - id: check-json
      - id: check-yaml
      - id: detect-private-key
      - id: end-of-file-fixer
      - id: trailing-whitespace

  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.10.0
    hooks:
      - id: shellcheck
        args: [--severity=warning, --shell=bash, --external-sources]

  - repo: https://github.com/scop/pre-commit-shfmt
    rev: v3.9.0-1
    hooks:
      - id: shfmt
        args: [-i, '2', -ci, -bn]

  - repo: https://github.com/biomejs/pre-commit
    rev: v1.9.4
    hooks:
      - id: biome-check
        files: ^plugin/cli/

  - repo: local
    hooks:
      - id: catalog-schema-validate
        name: Validate catalog.json against schema
        entry: node plugin/cli/scripts/validate-catalog.mjs
        language: system
        files: ^plugin/catalog/(catalog|agents/.*/recipe)\.json$
        pass_filenames: false
```

### 1.3 Testing

Four test layers. Each answers a different question. Mutation testing is the meta-layer that validates the others are doing real work, not just executing.

| Layer | Tool | Question Answered | Run When |
|-------|------|-------------------|----------|
| CLI unit | `node:test` (built-in, no deps) | "Does the registry CLI parse args, read the catalog, and dispatch correctly?" | Pre-commit, every PR |
| Behavior (bats) | `bats-core` 1.11.x | "Does an installed AgentLinux meet every BHV/RT/AGT/CLI/CAT/INST requirement?" | Docker matrix on every PR; QEMU nightly + release gate |
| Release smoke | Shell script over SSH | "Does a fresh install on a fresh Ubuntu cloud image succeed?" | Release-gate job only |
| **Mutation** | `stryker-mutator` (Node CLI) + custom bash mutator (installer) | **"Are our tests actually testing something? Would they catch a real regression?"** | Nightly + before any release branch is cut |

**Why mutation testing.** Without it, "100% behavior-test coverage" can be a green-bar lie: tests that execute every line but assert nothing meaningful. Mutation testing introduces small intentional faults into the source (`>` → `>=`, `&&` → `||`, delete a `set -e`, flip a sudoers permission bit) and checks that *the test suite catches the mutation*. Mutation score (mutants killed / mutants generated) is the truth-meter for test quality.

**For the Node.js CLI:** [`stryker-mutator`](https://stryker-mutator.io/) is mature and well-supported. Target: **mutation score ≥ 75%** for `plugin/cli/src/`. Equivalent mutants (mutations that produce identical behavior) are reviewed manually and excluded.

**For bash (installer + provisioner + bats helpers):** mature mutation tooling for bash does not exist. We ship a minimal in-house mutator at `tests/mutation/bash-mutator.sh` that performs a small, audit-friendly set of mutations (negation flip, comparison-operator swap, `set -e` removal, sudoers mode bit flip, `as_user` → direct invocation) and runs the bats suite against each mutant. Target: **mutation score ≥ 60%** for `plugin/lib/`, `plugin/provisioner/`, `plugin/bin/`. Lower target than the CLI because the mutator is intentionally narrow — false-negatives are expected and acceptable; the value is catching the high-impact mutations (security-relevant flips, idempotency breaks) early.

**Mutation results are advisory, not blocking, in v0.3.0.** A regression that drops the mutation score significantly opens a follow-up issue; it does not block the release. We promote mutation score to a release gate in v0.4 once we have a baseline and false-positive rate.

**CLI unit tests:**
```json
// plugin/cli/package.json (excerpt)
{
  "scripts": {
    "test": "node --test --experimental-test-coverage test/",
    "lint": "biome check src/ test/",
    "format": "biome format --write src/ test/"
  }
}
```

**Bats assertions:** one file per requirement category (see layout above). Tests execute inside the target environment (a container or a QEMU guest), not on the developer's host. A shared `tests/bats/helpers/` provides assertion helpers (`assert_agent_can_run`, `assert_no_eacces_in_log`, `assert_self_update_succeeds`, etc.) so individual tests stay short and readable.

**Docker harness:** `tests/docker/run.sh` builds a clean image per Ubuntu version, copies in the plugin tarball, executes the installer, then runs the bats suite inside the container. Defaults to running inside a non-root user to avoid Docker's most common false-positive category. ~90s per Ubuntu version on GitHub Actions' free tier.

**QEMU harness:** `tests/qemu/boot.sh` downloads a fresh Ubuntu cloud image, boots it under QEMU, waits for SSH, scps the plugin in, runs the installer, runs bats over SSH, shuts down. ~5min per run. Must be green before every release. Catches issues Docker can't (systemd, locale generation, real cloud-init paths, non-trivial UID allocation).

### 1.4 Build Configuration

- **Plugin bash scripts:** no build step. `plugin/bin/` and `plugin/lib/` ship as-is (after `shfmt` check).
- **Registry CLI:** `plugin/cli/` builds to a single JS bundle via `esbuild --bundle --platform=node --target=node22`. Output goes to `plugin/cli/dist/index.cjs`. The release tarball includes `dist/`, not `src/` — no `node_modules/` ships.
- **Release tarball:** `scripts/build-release.sh` assembles `plugin/bin/`, `plugin/lib/`, `plugin/provisioner/`, `plugin/catalog/`, `plugin/cli/dist/`, and a generated `VERSION` file into `agentlinux-vX.Y.Z.tar.gz`, then emits a sibling `.sha256`.
- **.deb (optional):** `packaging/deb/build.sh` wraps the same tarball with `fpm -s dir -t deb` (carries forward from v0.2.0).
- **GitHub Releases workflow:** tag `vX.Y.Z` → build tarball + .deb → upload both + sha256 to the release.

---

## 2. Documentation Structure

### 2.1 The Problem

Existing project documentation is scattered: research lives in `.planning/milestones/*/research/`, decisions live in `.planning/PROJECT.md` under "Key Decisions," and there's no canonical location for design proposals or review outputs. This works for GSD workflow state but fails for reference documentation — readers can't find decision records, research outputs are buried in milestone archives, and cross-cutting design docs have no home.

### 2.2 The `docs/` Directory

`docs/` is the **default destination for all reference documentation** — ADRs, design proposals, analyses, research reports, and review outputs worth preserving. If a task produces a document whose purpose is to be read later, it goes in `docs/`, even as a draft.

```
docs/
├── README.md                       # Index: what's here, how to navigate
├── HARNESS.md                      # This file
├── decisions/                      # Architecture Decision Records (ADR format)
│   ├── 001-pivot-distro-to-plugin.md
│   ├── 002-behavior-contract-framing.md
│   ├── 003-no-default-agents-installed.md
│   └── ...
├── research/                       # Research outputs (active + promoted from .planning)
│   ├── v0.3.0/
│   │   ├── STACK.md
│   │   ├── FEATURES.md
│   │   ├── ARCHITECTURE.md
│   │   ├── PITFALLS.md
│   │   └── SUMMARY.md
│   └── v0.2.0/                     # Archived for carry-forward reference
├── proposals/                      # Design proposals in flight (pre-ADR)
├── analysis/                       # Gap analyses, comparison studies
└── reviews/                        # Review-loop outputs worth preserving across sessions
```

**Routing rule:** If the output of a task is a document (analysis, decision, proposal, review, any reference material), it goes in `docs/` from the start — draft or finished. `.planning/` retains only GSD operational artifacts: phase plans (PLAN.md), execution state (STATE.md), config, todos, notes. Research outputs produced by GSD's research phase may start under `.planning/research/` but should graduate into `docs/research/` once the milestone locks.

### 2.3 Decision Records (ADRs)

Each non-trivial decision gets a lightweight ADR in `docs/decisions/`:

```markdown
# NNN: [Title]

**Status:** Accepted | Proposed | Superseded by NNN
**Date:** YYYY-MM-DD
**Context:** Why this decision was needed (2–3 sentences)
**Decision:** What we decided (1–2 sentences)
**Consequences:** What changes as a result; what trade-off was accepted
```

Decisions to seed immediately (already captured in `.planning/PROJECT.md` Key Decisions table or implicit from the v0.2.0 retrospective):

- ADR-001: Pivot from custom distro to installable Ubuntu plugin (v0.2.0 → v0.3.0)
- ADR-002: Behavior-contract framing — requirements are BHV-XX, not INST-XX; tests are the spec
- ADR-003: No default agents installed in v0.3.0
- ADR-004: Per-user npm prefix (`~/.npm-global`) as the keystone ownership decision
- ADR-005: System Node.js (NodeSource) over version managers (nvm/fnm/volta)
- ADR-006: curl-pipe-bash primary + optional `.deb` distribution
- ADR-007: Docker (fast) + QEMU (release gate) test harness; Docker-only is disqualified
- ADR-008: Commander.js for the registry CLI
- ADR-009: Snap is structurally disqualified as a distribution mechanism
- ADR-010: Review loop triggered by shared project instructions, not by a
  reviewer-invoking Stop hook; one-shot reminder hooks are allowed

As new decisions resolve during execution, each gets a new ADR. PROJECT.md's Key Decisions table continues to exist but becomes a one-line index pointing to the authoritative ADR file.

---

## 3. Systems Access Inventory

External systems that agents interact with during AgentLinux development. Compared to ELS-OS, the list is short — AgentLinux is a self-contained product with few upstream dependencies.

| System | Current Tooling | Coverage | Priority Gap |
|--------|-----------------|----------|--------------|
| GitHub (repo, PRs, issues, actions, releases) | `gh` CLI + global auth | Full | — |
| npm registry (read) | `npm view` via CLI during catalog research | Full | — |
| Anthropic Claude Code docs | `WebFetch` + Context7 | Full | — |
| Playwright (browser-access tool for agents) | `npm view playwright` + Playwright docs | Full | — |
| Open GSD npm package | Local Open GSD install + `npm view @opengsd/gsd-core` | Full | — |
| Ubuntu cloud images (QEMU test harness) | Cloud-images.ubuntu.com download + QEMU local | Partial | **P1:** cache downloaded images, boot helper skill |
| Docker Hub (ubuntu:22.04, ubuntu:24.04, ubuntu:26.04) | `docker pull` via GH Actions | Full | — |
| agentlinux.org (website + releases host) | GitHub Pages deploy via Actions | Full | — |
| Context7 MCP (library docs lookup) | Configured via `.mcp.json` | Full | — |

**P1 actions:**

1. Build a `qemu-harness` skill: documented boot flow, cache of downloaded cloud images, SSH-into-guest pattern. Makes the QEMU test harness reproducible across developers' machines without everyone figuring it out from scratch.

---

## 4. Review Feedback Loop

Core backpressure mechanism. At the end of every task — code, documents, or both — the main agent spawns reviewers, reads their feedback, fixes what it agrees with, and re-runs reviewers until it's satisfied the output is good enough.

### 4.1 How It Works

```
Main agent completes task
  │
  ├─ Look at what was produced (bash, TS, bats, docs, or mix)
  │
  ├─ Dispatch the reviewer roles mapped by the shared `.claude/skills/review/SKILL.md`
  │   through the host agent's native subagent mechanism
  │
  ├─ Each reviewer returns a free-form summary (comments, action points, observations)
  │
  ├─ Main agent reads all feedback and decides:
  │   ├── Which points are valid and worth fixing
  │   ├── Which points are irrelevant, already addressed, or contradictory
  │   └── Whether the output is good enough to deliver
  │
  ├─ If fixes needed: apply, re-spawn reviewers
  │
  └─ Repeat until remaining comments are not actionable (fixed, contradictory, or not valuable)
```

Main agent owns the triage decision. Reviewers provide input — they don't dictate what's blocking. No artificial iteration cap.

### 4.2 Reviewer roles

The shared `.claude/skills/review/SKILL.md` is the authoritative role registry,
file-pattern dispatch table, read-only contract, and triage procedure. The
portable role prompts are currently stored under `.claude/agents/` for
repository compatibility; Claude Code and Codex load the same prompts through
their native subagent mechanisms. This document intentionally does not repeat
the mapping, so the two hosts cannot drift.

Every reviewer receives a changed-file allowlist and an enforced read-only
capability profile. Read/search and safe deterministic checks are allowed;
editing, commits, pushes, PR creation, Jira writes, package installation, and
other external mutations are denied.

### 4.3 Reviewer Principles

1. **Free-form output.** Reviewers produce a summary with comments, action points, and observations. No rigid BLOCK/FLAG/PASS structure — the main agent interprets relevance and severity.
2. **Scoped context.** Each reviewer loads only the files relevant to its review, not the full conversation history.
3. **Main agent owns triage.** Decides what to fix, what to skip, when the output is good enough. Avoids infinite loops from subjective disagreements.

### 4.4 How It's Triggered

**Primary mechanism: host project instructions.** `AGENTS.md` and the host-specific
guidance tell the agent to run the shared review skill before reporting any task
complete. Each host uses its native subagent mechanism; the skill itself does
not call a particular agent CLI.

**Why not a reviewer-invoking Stop hook?** Stop hooks fire on every stop — user
interrupts, context limits, and errors — not just task completion. Putting
subjective LLM review in a Stop hook wastes tokens and confuses the user when
they hit Ctrl+C. The ELS-OS reference concluded the same; so does Spotify's
Honk architecture. The current Claude and Codex hooks are reminder-only and
never dispatch reviewers or run deterministic checks.

Deterministic lint/test hooks remain a future improvement, not current behavior.

**Implementation path:**

1. Keep the review instruction in shared project context and the workflow in
   the shared `/review` skill.
2. If deterministic Stop-hook checks are added later, document them separately
   and keep subjective reviewer dispatch out of the hook.

---

## 5. Skill Organization

### 5.1 Current State

```
.claude/skills/                 (project-scoped skills, including shared review)
~/.claude/skills/               (global — existing GSD skills, /review, etc.)
```

### 5.2 Target State

Project-scoped skills that encode AgentLinux-specific knowledge:

| Skill | Domain | Key Content | Source |
|-------|--------|-------------|--------|
| `agentlinux-installer` | Bash installer conventions | `set -euo pipefail`, idempotency primitives (`ensure_user`, `ensure_line_in_file`, `ensure_npm_prefix`), `as_user` pattern, distro-detection helpers, logging pattern, error propagation | Codify from installer code as it stabilizes |
| `behavior-test-contract` | Bats test authoring | How to write a BHV-XX test, shared assertion helpers, how to test non-interactive invocation modes (cron, systemd, sudo-u, non-interactive SSH), how to assert no-EACCES | Codify from `tests/bats/` as the first suite ships |
| `catalog-schema` | Agent recipe format | JSON Schema layout, required fields, install.sh/uninstall.sh contract, how to add a new agent | Codify once `plugin/catalog/schema.json` is final |
| `qemu-harness` | QEMU test harness operation | Download + cache cloud image, boot, SSH, teardown; how to add a new Ubuntu version | P1 — needed for local dev parity with CI |

**Scope rule:** If a skill references AgentLinux-specific patterns (installer internals, catalog schema, bats helpers, plugin layout), it's project-scoped. Generic tool interactions (Context7 usage, gh CLI patterns, GSD commands) stay global.

### 5.3 Cross-agent (Codex CLI)

`SKILL.md` is a cross-agent standard, so the same project skills serve both Claude Code and Codex CLI. Codex discovers project skills from `.codex/skills/`, which holds symlinks back to the canonical `.claude/skills/*` — one source, zero drift. Codex reads project context from the root `AGENTS.md` (Claude Code imports the same file via `@AGENTS.md` in `CLAUDE.md`), and fires the same two end-of-session reminders via Stop hooks declared in `.codex/config.toml` (backed by scripts in `.codex/hooks/`). See `docs/codex.md` for the full Codex setup, and §6 for the `AGENTS.md` / `CLAUDE.md` split.

---

## 6. CLAUDE.md (+ AGENTS.md)

> **Update (2026-07-18):** the repo now has both a root `CLAUDE.md` and a shared
> `AGENTS.md` (see the note at the end of this section). The original guidance
> below described the CLAUDE.md this section prescribed, written before either
> file existed; it still captures what belongs in the shared context.

This section originally noted the project had no CLAUDE.md at the repo root — every agent session started without project context. The context file must be under 150 lines and contain only what agents cannot infer from reading code:

- **Project identity:** "AgentLinux v0.3.0 — installable Ubuntu plugin. Provisions an agent user with correctly-owned Node.js runtime + a registry CLI for installing agent tools. Pivoted from custom distro (v0.2.0) on 2026-04-18."
- **Where things live:** `plugin/` for shippable code; `tests/bats/` for the behavior contract; `docs/` for reference; `.planning/` for GSD workflow state.
- **Critical rules (non-obvious):**
  - Never `sudo npm install -g` anywhere in installer code. Always `sudo -u agent -H npm install -g`. This is the bug class AgentLinux exists to eliminate.
  - Behavior tests (`tests/bats/`) are the spec. Implementation may change freely as long as the suite stays green. Do not pin implementation choices (npm vs native installer; sudo vs no-sudo) as requirements.
  - **No agent is installed by default.** Claude Code, GSD, and Playwright are available in the catalog; users opt in via `agentlinux install <name>`. Playwright is the canonical browser-access tool for agents (replaces Chrome DevTools MCP).
  - Docker-only test runs are insufficient. Before any release, QEMU suite must be green.
  - Every release tarball ships with a sibling `.sha256`. `packaging/curl-installer/install.sh` must verify.
  - No wrapper shims at `/usr/local/bin/` pointing to agent-owned binaries (the exact anti-pattern that breaks Claude Code self-update).
- **Review loop rule:** "Before reporting any task complete, run the review feedback loop on all changed files" (link to `/review` skill and §4 of this file).
- **Commands:**
  - Run bats locally inside Docker: `./tests/docker/run.sh ubuntu-24.04`
  - Run CLI unit tests: `cd plugin/cli && pnpm test`
  - Lint bash + TS: `pre-commit run --all-files`
  - Build release tarball: `./scripts/build-release.sh vX.Y.Z`
  - Preview docs: (none yet; docs are plain markdown)
- **Pointers:** `@.planning/ROADMAP.md`, `@.planning/REQUIREMENTS.md`, `@docs/HARNESS.md` (this file), `@docs/research/v0.3.0/SUMMARY.md`, relevant skills (§5).

Everything else — installer internals, schema details, historical v0.2.0 lessons — stays in skills and docs where it loads on demand.

**Shared context lives in `AGENTS.md`.** To serve both Claude Code and Codex CLI from one source, the agent-neutral context above lives in the root `AGENTS.md`. `CLAUDE.md` starts with `@AGENTS.md` and adds only Claude-Code-specific host mechanics. Codex reads `AGENTS.md` natively and uses its own host adapter. Keep the review workflow and role mapping in the shared `/review` skill; keep only dispatch mechanics in each tool's own file. See `docs/codex.md`.

---

## 7. Implementation Checklist

Ordered by dependency. Each item a concrete deliverable. Maps cleanly onto a "Harness Setup" phase at the front of the v0.3.0 roadmap.

### Phase A: Project Infrastructure (do first)

- [ ] Create directory skeleton: `plugin/`, `tests/`, `packaging/`, `docs/` (structure only, empty files or READMEs)
- [ ] Create `plugin/cli/package.json`, `plugin/cli/tsconfig.json`, `plugin/cli/biome.json` — Commander.js + node:test baseline, no real CLI code yet
- [ ] Create `.pre-commit-config.yaml` covering shellcheck, shfmt, biome, catalog-schema-validate; run `pre-commit install`
- [x] Create `CLAUDE.md` (< 150 lines) per §6
- [ ] Create `docs/README.md` index + `docs/decisions/000-template.md` ADR template
- [ ] Move `.planning/research/` → `docs/research/v0.3.0/` (and archive v0.2.0 research already sitting in `.planning/milestones/v0.2.0-research/` into `docs/research/v0.2.0/`)
- [ ] Seed ADR-001 through ADR-010 from the list in §2.3
- [ ] Set up `.github/workflows/test.yml` — run pre-commit + CLI unit tests + Docker bats matrix on every PR
- [ ] Add stryker-mutator config to `plugin/cli/` (`stryker.config.json`) targeting `src/` with mutation score threshold of 75 (warning, non-blocking in v0.3.0)
- [ ] Create `tests/mutation/bash-mutator.sh` (minimal in-house mutator) + `.github/workflows/nightly-mutation.yml` — runs both stryker and bash-mutator nightly, posts a report to Actions summary

### Phase B: Review Infrastructure

- [x] Write portable `bash-engineer` role definition (`.claude/agents/bash-engineer.md`)
- [x] Write portable `node-engineer` role definition
- [x] Write portable `security-engineer` role definition
- [x] Write portable `qa-engineer` role definition
- [x] Write portable `behavior-coverage-auditor` role definition
- [x] Write portable `catalog-auditor` role definition
- [x] Write portable `ai-deslop`, `dev-docs-auditor`, `technical-writer`,
  `fact-checker`, and `external-audience-auditor` role definitions
- [x] Create the shared `/review` skill (`.claude/skills/review/SKILL.md`, symlinked for Codex) documenting the review-loop convention
- [ ] Verify the loop on a dry-run: a trivial change to a sample bash script spawns `bash-engineer` + `security-engineer`, returns feedback, main agent triages

### Phase C: Skill Seeding

- [ ] Create `agentlinux-installer` skill skeleton (filled in as installer stabilizes)
- [ ] Create `behavior-test-contract` skill skeleton (filled in as first bats tests ship)
- [ ] Create `catalog-schema` skill skeleton (filled in once schema is final)
- [ ] Create `qemu-harness` skill with boot/SSH/teardown recipe

### Phase D: Ongoing (alongside v0.3.0 phase execution)

- [ ] New ADRs as decisions resolve during execution
- [ ] Tune reviewer agents based on observed false-positive rates after the first two phases
- [ ] Grow `agentlinux-installer`, `behavior-test-contract`, and `catalog-schema` skills as patterns stabilize in real code
- [ ] Retrospective at milestone close: which reviewers caught real bugs, which produced noise

---

## 8. Success Criteria

Measurable signals that the harness is working.

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Agent autonomy rate | > 70% of tasks complete without human mid-task redirect | Count of "stop, you're going wrong" interventions per completed phase |
| First-pass review accuracy | > 80% of outputs pass reviewers on first attempt | Review-loop iterations before the agent triages "good enough" |
| Review catch rate | > 90% of errors caught before reaching human review | Count of errors caught by automated review vs. errors human reviewer flags on the PR |
| Pre-commit pass rate | > 95% on first commit attempt | Pre-commit hook failure rate from git history |
| Behavior-test coverage | 100% of BHV/RT/AGT/CLI/CAT/INST requirements have at least one bats test | `behavior-coverage-auditor` report across every phase end |
| Mutation score (Node CLI) | ≥ 75% — proves CLI tests assert real behavior, not just execute lines | `stryker-mutator` nightly report on `plugin/cli/src/` |
| Mutation score (bash) | ≥ 60% — proves bats tests catch real installer regressions | Custom `tests/mutation/bash-mutator.sh` nightly report |
| CI green rate on first push | > 85% of PRs pass CI on first push | GitHub Actions pass/fail on `pr-opened` event |
| Release-gate QEMU pass rate | 100% — any red QEMU run blocks release | Release workflow dashboard |

The harness improves iteratively. After each milestone, audit which review loops caught real problems (keep), which produced only noise (tune), which agent errors reached human review that should have been caught earlier (add a new reviewer or rule), and which skills grew stale vs. which earned their place.

---

*Created: 2026-04-18 — adapted from ELS-OS-Migration HARNESS.md v3 template for AgentLinux's bash + Node.js stack*
*Next review: After Phase A implementation*
