---
phase: 59-full-validation-gate
plan: 01
subsystem: validation-gate
tags: [bats, harness, schema-drift, hrn-05, hrn-06, gate-01]
requires:
  - "Phases 53-58 complete at HEAD (338 cargo tests; musl bin = default provisioner + shipped artifact)"
provides:
  - "13-reuse 32/32 on the Rust build (behavior matrix red-free) on ubuntu-24.04 + almalinux-9"
  - "tests/harness/run.sh 118/118 green (HRN-05 + HRN-06 resolved)"
  - "GATE-01 precondition (no red / no newly-skipped) genuinely met for Wave 2/3"
affects:
  - "59-02 (Wave 2 QEMU re-wire) — now runs on a red-free suite"
  - "59-03 (Wave 3 coverage audit + AGT-02 + declare-ready) — truly-green gate"
tech-stack:
  added: []
  patterns:
    - "spec-tracks-the-authoritative-schema: bats assertion corrected to match the schemars-generated + drift-locked schema, never vice-versa"
    - "restore-beats-re-scope: durable ALLOWED planning dir source restored to preserve a byte-match invariant"
key-files:
  created:
    - .planning/research/SUMMARY.md
  modified:
    - tests/bats/13-reuse.bats
    - .claude/agents/security-engineer.md
    - .codex/agents/security-engineer.toml
decisions:
  - "Fixed the TEST (13-reuse.bats:552), not the schema — the schemars-generated schema.json is byte-locked by schema_is_not_drifted and is the TEST-03 source-of-truth; changing the Rust type to satisfy the stale bare-scalar check would fail the drift-check AND make the field required."
  - "Resolved HRN-05 by RESTORING the durable .planning/research/SUMMARY.md (byte-copy of docs/research/v0.3.0/SUMMARY.md), not by re-scoping the byte-match test — research/ is a durable ALLOWED dir (check-planning-clean.sh:44) so the restore survives merge."
  - "Regenerating .codex/agents/security-engineer.toml via scripts/sync-codex-agents.sh was required after editing security-engineer.md (HRN-07 codex-sync test + AGENTS.md sync contract)."
metrics:
  duration: "~15m"
  completed: "2026-07-29"
status: complete
---

# Phase 59 Plan 01: Wave 1 — Resolve the 3 Carried Reds Summary

Cleared the three carried, non-environment reds so the Phase 59 validation gate
is genuinely green: corrected the stale `13-reuse` #29 schema-type assertion to
track the schemars nullable union (fix the test, not the drift-locked schema),
restored the durable `.planning/research/SUMMARY.md` byte-source for HRN-05, and
added a real sudoers-`0440` review line to the security-engineer reviewer role
for HRN-06 (with its Codex `.toml` mirror re-synced).

## Tasks Completed

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Fix stale 13-reuse #29 assertion (accept schemars nullable union) | bc16b03 | tests/bats/13-reuse.bats |
| 2 | HRN-05 (restore research SUMMARY) + HRN-06 (sudoers-0440 review line) + codex sync | 8d40531 | .planning/research/SUMMARY.md, .claude/agents/security-engineer.md, .codex/agents/security-engineer.toml |

## Verification Results

- **13-reuse 32/32 on both distros (Rust build):**
  - `./tests/docker/run.sh ubuntu-24.04 13-reuse` → `ok count: 32`, `== PASS ==`
  - `./tests/docker/run.sh almalinux-9 13-reuse` → `ok count: 32`, `== PASS ==`
  - The #29 `compatibility_window` red (was 31/32) is cleared.
- **`bash tests/harness/run.sh` fully green:** `1..118`, 118 ok, 0 not-ok, exit 0.
  - `ok 67 HRN-05: v0.3.0 SUMMARY.md byte-matches the planning/ source`
  - `ok 81 HRN-06: security-engineer rubric mentions sudoers mode 0440`
  - `ok 91 HRN-07: .codex/agents/ is in sync with .claude/agents/`
- **`cargo test --workspace` (in `rust/`):** `338 passed (3 suites, 2.81s)` — unaffected.
- **On-disk schema confirms the fix tracks reality:** `.compatibility_window.type`
  is `["string","null"]` with `minLength:1` (schemars from `Option<String>`).

### The 13-reuse hunk (spec-tracks-the-authoritative-schema)

The stale assertion `jq -e '...compatibility_window.type == "string"'` was
replaced with a predicate that accepts the schemars nullable union
`["string","null"]` (or a bare `"string"`, or any array containing `"string"`),
with an inline comment documenting WHY:

- `schema_gen.rs:79` declares `compatibility_window: Option<String>`.
- schemars canonically serializes `Option<String>` to `type: ["string","null"]`.
- `schema_is_not_drifted` (schema_gen.rs:143-158) byte-locks the generated
  `schema.json`, enforced by the rust + cli-unit CI jobs — the schema is the
  TEST-03 source-of-truth.
- Editing the schema (or changing the Rust type to `String`) to satisfy the old
  bare-scalar check would (a) fail the drift-check and (b) make the field
  required, breaking the `test_only`-entries-omit-it invariant at
  `13-reuse.bats:521-543`.

The corrected `__fail` diagnostic still asserts the field is the nullable-string
union — the check remains meaningful; the verify runs the REAL schema through the
predicate, so a truly-wrong type would still fail.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Regenerated the Codex reviewer-role mirror after editing `security-engineer.md`**
- **Found during:** Task 2 (first `tests/harness/run.sh` run showed `not ok 91 HRN-07: .codex/agents/ is in sync with .claude/agents/`).
- **Issue:** `AGENTS.md` documents that `.codex/agents/*.toml` are generated from `.claude/agents/` by `scripts/sync-codex-agents.sh`, and `50-agents-and-skills.bats:155` (HRN-07) asserts the two stay in sync. Editing `security-engineer.md` without regenerating its `.toml` projection made the harness go red.
- **Fix:** Ran `scripts/sync-codex-agents.sh` (wrote 15 agents; only `security-engineer.toml` changed) and committed the regenerated mirror alongside the doc edit.
- **Files modified:** `.codex/agents/security-engineer.toml`
- **Commit:** 8d40531

This is the correct, mandated companion change (not a scope creep) — the pre-commit `Check .codex/agents/ is in sync` hook also enforces it, and it passed on the Task 2 commit.

## Scope Confirmation

- `git diff --stat` (tracked): only `tests/bats/13-reuse.bats`, `.claude/agents/security-engineer.md`, `.codex/agents/security-engineer.toml`, plus the restored (previously untracked) `.planning/research/SUMMARY.md`.
- **No schema, Rust source, or `tests/harness/*.bats` spec was changed.** The only bats edit is the single stale-assertion fix in `13-reuse.bats`.
- **TS/Bash retained:** no changes under `plugin/cli/` or the Bash entrypoint (GATE-05 rollback surface untouched); `agentlinux-core` untouched.
- Pre-existing untracked `.planning/phases/58-.../58-VERIFICATION.md` was not touched (out of scope).

## Self-Check: PASSED

- `tests/bats/13-reuse.bats` — FOUND (modified, 32/32 on both distros)
- `.planning/research/SUMMARY.md` — FOUND (byte-matches docs source)
- `.claude/agents/security-engineer.md` — FOUND (sudoers-0440 line present)
- `.codex/agents/security-engineer.toml` — FOUND (in sync)
- Commit bc16b03 — FOUND
- Commit 8d40531 — FOUND
