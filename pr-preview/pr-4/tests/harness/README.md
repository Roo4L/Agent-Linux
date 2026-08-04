# Harness Meta-Test Suite (`tests/harness/`)

The Phase 1 **acceptance gate** for AgentLinux v0.3.0.

## Purpose

Assert that every HRN-XX, TST-06, and TST-07 deliverable from `.planning/ROADMAP.md` §Phase 1 is on disk, loadable, and correctly shaped. If `bash tests/harness/run.sh` exits 0, Phase 1 is done.

These are **meta-tests** — they verify the harness itself is well-formed (files exist, YAML parses, frontmatter matches slugs, non-negotiable rules are codified). They are distinct from Phase 2's behavior-test suite under `tests/bats/`, which runs inside a target environment (Docker / QEMU) to assert runtime behavior of the installed plugin.

## How to run

```bash
bash tests/harness/run.sh
```

Exit code 0 iff every harness bats file passes. The runner also invokes `pre-commit run --all-files` as an optional smoke test when `pre-commit` is on PATH.

## Prerequisites

`bats` (bats-core) must be available. The runner searches in this order:

1. `bats` on PATH (install: `sudo apt install bats` / `brew install bats-core` / `npm install -g bats`)
2. `./node_modules/.bin/bats` (install: `npm install --no-save bats` from repo root)
3. `./tests/bats/bin/bats` (vendored: clone `bats-core` into `tests/bats/`)

Docker fallback:

```bash
docker run --rm -v "$PWD":/code -w /code bats/bats:latest tests/harness/
```

`python3` and `node` are used inline for YAML / JSON parse checks — both ship in the base CI image. `pre-commit` is optional locally; CI installs it in `test.yml`.

## What each `.bats` file covers

| File | Requirement group |
|------|-------------------|
| `00-layout.bats` | HRN-01 — project layout matches `docs/HARNESS.md` §1.1 |
| `10-claude-md.bats` | HRN-03 — CLAUDE.md at repo root, < 150 lines, §6 sections |
| `20-precommit.bats` | HRN-02 — pre-commit config + catalog-schema validator |
| `30-workflows.bats` | HRN-08 — four GH Actions workflows parse + empty-plugin-pass |
| `40-adrs-and-research.bats` | HRN-04 + HRN-05 — ADR-001..010 seeded + research migrated |
| `50-agents-and-skills.bats` | HRN-06 + HRN-07 + HRN-09 + TST-07 scaffolding — six review subagents + /review skill + four project-scoped skill skeletons |
| `60-mutation-scaffolding.bats` | TST-06 — stryker config + bash-mutator runnable + advisory |

## What a failure means

Each `@test` names the requirement it enforces (`HRN-XX:` or `TST-XX:` prefix). A failing test means the listed deliverable is missing, malformed, or regressed — **fix the underlying artifact**, do not silence the test. The bats suite is the mechanism that prevents Phase 1 from silently decaying as later phases land.

## Gate semantics

Phase 1 closes when `bash tests/harness/run.sh` exits 0. Phase 2+ plans are gated on that signal — `.planning/ROADMAP.md` §Phase 1 lists the six success criteria and every one has at least one bats assertion behind it.
