# Phase 44: spec-kit — Summary

**Status:** ✓ COMPLETE (Docker 3/3 green, ubuntu-24.04) — 2026-07-14
**Requirements:** WORK-03, ENABLE-03 (+ OPS-01 real-op gate)
**Jira:** AL-91

## What shipped

- **ENABLE-03 Python+uv bootstrap** — `plugin/catalog/lib/uv-bootstrap.sh`: a shared
  helper that installs a per-user static-musl `uv` (pin 0.11.28) through the ENABLE-01
  checksum-verified fetch, `uv tool install`s a git-pinned Python CLI with a uv-managed
  CPython, and removes symmetrically. Ownership is marker-gated: a user-brought uv is
  reused untouched and never removed; the managed uv is torn down only if AgentLinux
  installed it AND no uv tools remain.
- **spec-kit catalog entry** (`source_kind: script`, pin `0.12.11`, MIT) + recipe pair.
  No new `source_kind` enum: the CLI runs script/binary/mcp recipes identically
  (per-kind logic is npm-only), so `script` fully models a uv-bootstrapped tool.
- `tests/bats/66-catalog-spec-kit.bats` — 3 @tests (full ENABLE-03 lifecycle + OPS-01
  `specify init` real op + offline trust-boundary guard + entry-shape).
- `docs/internals/catalog.md` "The uv bootstrap" section; `git` added to the three
  Docker test images (uv installs from a git ref).

## Corrections made during the phase (verified before building)

- **Install mechanic**: the roadmap's PyPI-style pin `specify-cli@0.11.9` was stale and
  wrong-shaped. Spec Kit installs from a **git tag**: `uv tool install specify-cli
  --from git+https://github.com/github/spec-kit.git@v0.12.11` (verified vs the upstream
  README and a real end-to-end smoke). Pinned to **v0.12.11** (docs-cited, stable).
- **git prerequisite**: uv's `git+` source needs system git; the recipe preflights it
  with an actionable error, and CI images now include git.

## OPS-01 real-operation smoke (phase-close gate)

`specify init specdemo --integration claude --ignore-agent-tools --script sh` runs as
the agent user and scaffolds a real `.specify/` work tree (integrations/memory/scripts/
templates/workflows). Asserted exit 0 + `.specify/` created by the tool, and preserved
across `agentlinux remove spec-kit`. **Passed** (Docker 3/3, no credential — offline op
per Appendix C). Recorded here per the OPS-01 phase-close requirement.

## Review loop

8 reviewers (catalog-auditor, bash-engineer, security-engineer, qa-engineer,
behavior-coverage-auditor, ai-deslop, fact-checker, dev-docs). Actionable findings all
fixed: uv checksum-file format (per-asset `.sha256`, not the BSD-tagged combined file),
robust `uv tool list` parsing (NO_COLOR + ANSI-strip + capture-once), OPS-01 upgraded
from `specify check` to the spec-mandated `specify init`, added the trust-boundary test,
plus ownership-asymmetry / mutable-tag / hash-r comments and a git-prereq doc note.
