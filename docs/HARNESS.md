# Harness Engineering: Agent-Driven AgentLinux Plugin Development

## Purpose

This document specifies the project structure, tooling, and review processes required to run AgentLinux v0.3.0 development through supported coding-agent hosts, including Claude Code and Codex. Goal: agents run longer, produce better results, and ship faster — while humans retain decision authority over irreversible actions (releases, destructive migrations, schema breaks).

**Scope:** Project organization, code quality infrastructure, documentation structure, and the automated review feedback loop. Not the installer design itself (that's the per-milestone behavior contracts under `.planning/milestones/` + `.planning/ROADMAP.md`).

**Reference template:** Adapted from the ELS-OS-Migration-to-PatchFlow HARNESS.md (Python/API/DB) for AgentLinux's stack (Rust provisioner + registry CLI, bash install recipes, no database, minimal external APIs).

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
├── rust/                               # Cargo workspace — provisioner + registry CLI
│   ├── Cargo.toml                      # Workspace root; Cargo.lock is committed
│   └── crates/
│       ├── agentlinux/                 # The `agentlinux` bin (static x86_64-musl)
│       │   └── src/
│       │       ├── cli.rs              # clap arg definitions
│       │       ├── cmd/                # list / adopt / install / remove / upgrade / pin / provision
│       │       ├── catalog.rs          # JSON Schema-validated catalog reader
│       │       └── dispatcher.rs       # Dispatches to catalog/agents/<name>/install.sh
│       └── agentlinux-core/            # I/O-free logic (classify, divergence, semver shim)
├── plugin/                             # Shippable non-Rust assets
│   ├── bin/agentlinux                  # Build output — staged into the tarball, not in git
│   └── catalog/                        # Agent recipe catalog
│       ├── schema.json                 # JSON Schema 2020-12 contract
│       ├── catalog.json                # Curated catalog entries (none installed by default)
│       └── agents/
│           ├── claude-code/install.sh
│           ├── gsd/install.sh
│           └── playwright-cli/install.sh         # Browser-access tool for agents
├── packaging/                          # Distribution wrapper (sole channel)
│   └── curl-installer/
│       └── install.sh                  # SHA256-verified downloader for the reproducible musl tarball
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
├── index.html, assets/                 # Landing page — agentlinux.org, served from repo root
├── docs/                               # All reference documentation (see §2)
│   ├── README.md                       # Index
│   ├── HARNESS.md                      # This file
│   ├── decisions/                      # ADRs
│   ├── research/                       # Long-lived research — flat, one file per question
│   └── internals/                      # Developer docs, one per component (ADR-015)
├── .planning/                          # GSD operational state (not reference material)
├── .claude/                            # Claude Code project config
│   ├── agents/                         # Portable reviewer role prompts (§4)
│   ├── skills/                         # Project-scoped skills (§5)
│   └── settings.json
├── .github/
│   └── workflows/
│       ├── test.yml                    # Docker test matrix on every PR
│       ├── nightly-qemu.yml            # QEMU release-gate suite
│       └── release.yml                 # Tag → build reproducible musl tarball → GitHub Release
└── packer/                             # (existing v0.2.0 — retired with pivot, keep for reference)
```

**Key decisions:**

- **Root is a workspace, not a single Cargo project.** No `Cargo.toml` at the root; the cargo workspace lives under `rust/`. This keeps the root clean for peer repos we may clone during development (Claude Code repo, example installers, scratch Ubuntu test images).
- **`plugin/` is the shippable artifact.** Everything in `plugin/` is what goes into the release tarball. `packaging/curl-installer/install.sh` downloads that tarball and execs `plugin/bin/agentlinux provision`.
- **`tests/` is separate from `plugin/`.** Tests never ship. Black-box: they run against an *installed* `plugin/`, not against source.
- **`docs/` for reference, `.planning/` for workflow state.** Identical routing rule to the reference: if the output of a task is a document intended to be read later (ADR, research report, design proposal, review summary), it goes in `docs/`, even as a draft. `.planning/` holds PLAN.md, STATE.md, config — workflow machinery, not documentation.
- **Existing `packer/` stays in-tree as read-only reference** until v0.3.1 when we can decide whether to delete it. It documents the retired distro path and contains provisioner scripts that inform the plugin's installer logic.

### 1.2 Code Quality: Pre-commit

Three languages in this project: **Rust** (provisioner + registry CLI), **bash** (per-agent install recipes), and **JSON** (catalog + config). One toolchain per language.

| Language | Lint | Format | Notes |
|---------|------|--------|-------|
| Rust | `cargo clippy` | `cargo fmt` | Enforced in the `rust` CI job, a required status check |
| Bash | `shellcheck` | `shfmt` | `--shell=bash` (not POSIX); `-i 2` for 2-space indent |
| JSON | jq structural gate | — | Pre-commit checks catalog shape; full JSON-Schema validation is the schemars drift-check in `cargo test -p agentlinux-core schema` |
| Bats | (bats-core has no lint) | `shfmt` | Treat `.bats` files as bash for formatting |

```yaml
# .pre-commit-config.yaml
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

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks:
      - id: gitleaks

  - repo: local
    hooks:
      - id: catalog-schema-validate
        name: Validate catalog.json against schema
        entry: scripts/check-catalog-schema.sh
        language: system
        files: ^plugin/catalog/catalog\.json$
        pass_filenames: false
      # plus: check-version-lockstep, check-distro-leak, and
      # sync-codex-agents --check — see the real file for their filters.
```

### 1.3 Testing

Four test layers. Each answers a different question. Mutation testing is the meta-layer that validates the others are doing real work, not just executing.

| Layer | Tool | Question Answered | Run When |
|-------|------|-------------------|----------|
| Unit + property | `cargo test` (incl. `proptest`) | "Does the CLI parse args, read the catalog, and dispatch correctly? Does the pure core hold under generated input?" | The `rust` CI job on every PR |
| Behavior (bats) | `bats-core` (the distro package; 22.04 ships 1.2.1) | "Does an installed AgentLinux meet every BHV/RT/AGT/CLI/CAT/INST requirement?" | Docker matrix on every PR; QEMU nightly + release gate |
| Release smoke | Shell script over SSH | "Does a fresh install on a fresh Ubuntu cloud image succeed?" | Release-gate job only |
| **Mutation** | `cargo-mutants` (the pure core only) | **"Are our tests actually testing something? Would they catch a real regression?"** | `--in-diff` gate on every PR; full-crate score nightly |

**Why mutation testing.** Without it, "100% behavior-test coverage" can be a green-bar lie: tests that execute every line but assert nothing meaningful. Mutation testing introduces small intentional faults into the source (`>` → `>=`, `&&` → `||`, delete a `set -e`, flip a sudoers permission bit) and checks that *the test suite catches the mutation*. Mutation score (mutants killed / mutants generated) is the truth-meter for test quality.

**Scope: the pure core only.** Both mutation jobs run `--package agentlinux-core`. On every PR the `rust` job adds `--in-diff` against the diff of `crates/agentlinux-core/**` — only mutants introduced by that diff must be killed, which keeps the gate fast enough to be *blocking*. Nightly, `nightly-mutation.yml` scores the whole core crate and is advisory. Both pin the same `cargo-mutants` version so the merge gate and the nightly score share one mutant set.

**Nothing outside `agentlinux-core` is mutation-tested.** The `agentlinux` bin crate — the I/O adapters, the dispatcher, the provisioner — yields zero mutants, so new logic there passes the gate untested. That is the price of keeping the gate fast; the bats behavior suite is what covers it.

**The per-agent Bash recipes are not mutation-tested.** Mature mutation tooling for bash does not exist, and the in-house scaffold that once stood in was removed along with the Bash provisioner. The recipes are covered by the bats behavior suite instead.

**Running the unit + property suite:**
```bash
cd rust && cargo test --workspace          # all crates
cargo test -p agentlinux-core parity       # the node-semver parity goldens
```

Proptest counterexample seeds under `rust/**/proptest-regressions/` are **committed** — a failure found once must replay on every future run, so that directory is deliberately not gitignored.

**Bats assertions:** one file per requirement category (see layout above). Tests execute inside the target environment (a container or a QEMU guest), not on the developer's host. A shared `tests/bats/helpers/` provides assertion helpers (`assert_agent_can_run`, `assert_no_eacces_in_log`, `assert_self_update_succeeds`, etc.) so individual tests stay short and readable.

**Docker harness:** `tests/docker/run.sh` builds a clean image per Ubuntu version, copies in the plugin tarball, executes the installer, then runs the bats suite inside the container. Defaults to running inside a non-root user to avoid Docker's most common false-positive category. ~90s per Ubuntu version on GitHub Actions' free tier.

**QEMU harness:** `tests/qemu/boot.sh` downloads a fresh Ubuntu cloud image, boots it under QEMU, waits for SSH, scps the plugin in, runs the installer, runs bats over SSH, shuts down. ~5min per run. Must be green before every release. Catches issues Docker can't (systemd, locale generation, real cloud-init paths, non-trivial UID allocation).

### 1.4 Build Configuration

- **Catalog Bash recipes:** no build step. `plugin/catalog/agents/*/{install,uninstall}.sh` + `plugin/catalog/lib/` ship as-is (after `shfmt` check).
- **Provisioner + registry CLI:** the Rust workspace under `rust/` (built to a static x86_64-musl `agentlinux` bin). The TypeScript CLI + Bash provisioner/entrypoint were retired at the cutover; the shipped `agentlinux` is the Rust musl bin and `cargo test` is the unit-test oracle alongside the bats behavior suite.
- **Release tarball:** `scripts/build-release.sh` builds the static `x86_64-unknown-linux-musl` `agentlinux` bin and assembles `plugin/bin/agentlinux` (the bin) + `plugin/catalog/` (catalog.json + the ~25 Bash recipes) + a generated `VERSION` file into `agentlinux-vX.Y.Z.tar.gz`, then emits a sibling `.sha256`. The tarball is byte-reproducible (SOURCE_DATE_EPOCH-pinned tar + `strip`/`--remap-path-prefix`/`--build-id=none` on the bin).
- **Distribution channel:** the reproducible musl tarball + `.sha256` is the **sole** channel. The optional fpm `.deb` wrapper was removed at the Rust cutover (ADR-006 is flagged superseded-in-part).
- **GitHub Releases workflow:** tag `vX.Y.Z` → build tarball → upload tarball + sha256 + catalog snapshot to the release.

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
└── research/                       # Long-lived research — flat, one file per question
    ├── stack-reconsideration.md
    ├── stability-model-reconsideration.md
    └── cli-vs-apt-advisor.md
```

**Routing rule:** If the output of a task is a document (analysis, decision, proposal, review, any reference material), it goes in `docs/` from the start — draft or finished. `.planning/` retains only GSD operational artifacts: phase plans (PLAN.md), execution state (STATE.md), config, todos, notes.

**Promoting research into `docs/research/`.** Most research is scaffolding for one decision; it stays in `.planning/research/`. Promote only when the document holds what the ADR drops — the options that were rejected and why they lost. If the document's content *is* the conclusion, the ADR is the record. Unsure: ask, don't promote.

A promoted document must be usable by someone with no access to `.planning/`:

- **Flat.** `docs/research/<question>.md`. No milestone or version subdirectories.
- **Header:** `Date`, `Question`, `Scope`, `Outcome`. `Outcome` names the decision, links the ADR if there is one, and says what actually shipped — including where the implementation diverged from the design.
- **No workspace vocabulary.** No phase numbers, plan filenames, requirement IDs, GSD terms, or "what to do next" lists. Name the behavior instead of citing its ID. A dated document's option-comparison table may keep the IDs it was argued with — rewriting those cells rewrites the argument — but its prose may not.

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

**Superseding.** When a later ADR replaces this one, `Status` is `Superseded by NNN`. When a decision is overtaken by something that is *not* a numbered ADR — a rewrite, a dropped channel — `Status` reads `Accepted (DATE) — Superseded[-in-part] (VERSION):` followed by what changed, and a closing `## Superseded[-in-part] (VERSION)` section carries the detail: what replaced it, which parts of the original reasoning survive, and where the real record lives. ADR-006 and ADR-008 are the worked examples. Never edit the original Context/Decision — an ADR is a record of what was decided then, not a description of the system now.

The current, authoritative ADR index is [`decisions/README.md`](decisions/README.md) — statuses and supersessions live there, not here. The list below is the original seed set as it was written, recorded for the §7 checklist item that produced it; several of these have since been superseded in whole or in part:

- ADR-001: Pivot from custom distro to installable Ubuntu plugin (v0.2.0 → v0.3.0)
- ADR-002: Behavior-contract framing — requirements are BHV-XX, not INST-XX; tests are the spec
- ADR-003: No default agents installed in v0.3.0
- ADR-004: Per-user npm prefix (`~/.npm-global`) as the keystone ownership decision
- ADR-005: System Node.js (NodeSource) over version managers (nvm/fnm/volta)
- ADR-006: curl-pipe-bash distribution + optional `.deb`
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
  - Run Rust unit tests: `cd rust && cargo test --workspace`
  - Lint bash + catalog: `pre-commit run --all-files`
  - Build release tarball: `./scripts/build-release.sh vX.Y.Z`
  - Preview docs: (none yet; docs are plain markdown)
- **Pointers:** `@.planning/ROADMAP.md`, `@.planning/milestones/`, `@docs/HARNESS.md` (this file), `@docs/research/`, relevant skills (§5).

Everything else — installer internals, schema details, historical v0.2.0 lessons — stays in skills and docs where it loads on demand.

**Shared context lives in `AGENTS.md`.** To serve both Claude Code and Codex CLI from one source, the agent-neutral context above lives in the root `AGENTS.md`. `CLAUDE.md` starts with `@AGENTS.md` and adds only Claude-Code-specific host mechanics. Codex reads `AGENTS.md` natively and uses its own host adapter. Keep the review workflow and role mapping in the shared `/review` skill; keep only dispatch mechanics in each tool's own file. See `docs/codex.md`.

---

## 7. Implementation Checklist

Ordered by dependency. Each item a concrete deliverable. Maps cleanly onto a "Harness Setup" phase at the front of the v0.3.0 roadmap.

### Phase A: Project Infrastructure (do first)

- [ ] Create directory skeleton: `plugin/`, `tests/`, `packaging/`, `docs/` (structure only, empty files or READMEs)
- [ ] Create the `rust/` cargo workspace — `agentlinux` bin + `agentlinux-core` lib, no real logic yet
- [ ] Create `.pre-commit-config.yaml` covering shellcheck, shfmt, catalog-schema-validate; run `pre-commit install`
- [x] Create `CLAUDE.md` (< 150 lines) per §6
- [ ] Create `docs/README.md` index + `docs/decisions/000-template.md` ADR template
- [x] Flatten `docs/research/` and promote the three keepers (§2.2)
- [ ] Seed ADR-001 through ADR-010 from the list in §2.3
- [ ] Set up `.github/workflows/test.yml` — run pre-commit + `cargo test` + Docker bats matrix on every PR
- [ ] Wire `cargo-mutants --in-diff` into the `rust` CI job as a blocking gate
- [ ] Create `.github/workflows/nightly-mutation.yml` — full-crate `cargo-mutants` score on the pure core, advisory, warning-annotated on survivors

### Phase B: Review Infrastructure

- [x] Write portable `bash-engineer` role definition (`.claude/agents/bash-engineer.md`)
- [x] Write portable `node-engineer` role definition
- [x] Write portable `security-engineer` role definition
- [x] Write portable `qa-engineer` role definition
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
| Behavior-test coverage | Every behavior the product promises has at least one bats test | `qa-engineer` review on any change under `tests/` |
| Mutation score (Rust core) | Zero surviving mutants in the diff — proves new pure-core code is covered by assertions, not just executed | `cargo-mutants --in-diff --package agentlinux-core` on every PR; full-crate score nightly |
| CI green rate on first push | > 85% of PRs pass CI on first push | GitHub Actions pass/fail on `pr-opened` event |
| Release-gate QEMU pass rate | 100% — any red QEMU run blocks release | Release workflow dashboard |

The harness improves iteratively. After each milestone, audit which review loops caught real problems (keep), which produced only noise (tune), which agent errors reached human review that should have been caught earlier (add a new reviewer or rule), and which skills grew stale vs. which earned their place.

---

*Created: 2026-04-18 — adapted from ELS-OS-Migration HARNESS.md v3 template; retargeted to the Rust provisioner + CLI at the v0.4.0 cutover*
*Next review: After Phase A implementation*
