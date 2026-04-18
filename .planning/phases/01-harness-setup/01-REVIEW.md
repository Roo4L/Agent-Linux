---
phase: 01-harness-setup
created: 2026-04-18T11:09:35Z
reviewed: 2026-04-18T12:30:00Z
iteration: 2
depth: standard
files_reviewed: 4
files_reviewed_list:
  - .github/workflows/release.yml
  - tests/harness/10-claude-md.bats
  - plugin/cli/scripts/validate-catalog.mjs
  - tests/harness/run.sh
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: clean
---

# Phase 1: Code Review Report (Iteration 2)

**Reviewed:** 2026-04-18T12:30:00Z
**Depth:** standard
**Files Reviewed:** 4 (re-review of iteration-1 fixes)
**Status:** clean

## Summary

Iteration-2 re-review of the four files changed by `gsd-code-fixer` to resolve
CR-01, WR-01, WR-02, WR-03, and WR-04 from the iteration-1 REVIEW. All five
findings are fully addressed. No new issues were introduced. Syntax, YAML
parse, and Node parse checks pass; each fix was additionally exercised with
targeted empirical tests (see verification notes below).

Phase 1 scaffolding guarantees (stubs are intentional, advisory-mutation is
intentional, placeholder tarballs are intentional *only on non-tag dry-runs*)
are preserved. The release workflow now fails closed on a tag push without a
build script rather than publishing a bogus artifact; shell injection sinks
via `${{ inputs.tag }}` have been eliminated; the CLAUDE.md prohibition test
anchors on forbidding phrasing; `validate-catalog.mjs` uses a stable
positional identifier when `a.name` is absent; and `run.sh` guards the empty
`.bats` glob with `nullglob` + array-length check.

## Verification of Iteration-1 Findings

### CR-01 — Shell injection via `${{ inputs.tag }}` — FIXED

**File:** `.github/workflows/release.yml`

- Line 26: `INPUT_TAG: ${{ inputs.tag }}` moved to `env:` block. The
  `workflow_dispatch` input is now consumed as a regular shell variable
  (`$INPUT_TAG`) at lines 28-31, which GH Actions escapes safely — no
  template interpolation into `run:` bash anywhere.
- Line 36: `TAG: ${{ steps.tag.outputs.value }}` also confined to `env:`,
  sourced from `$INPUT_TAG` via `$GITHUB_OUTPUT` (newlines in output values
  are blocked by GH Actions' output parser in single-line form).
- Lines 38-41: Tag-shape regex `^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$`
  gates the build step. Empirically verified to accept `v0.3.0`, `v10.20.30`,
  `v1.2.3-alpha`, `v1.2.3-rc.1`, `v1.2.3-alpha.beta`, and reject `0.3.0`,
  `v1.2`, `v1.2.3; rm -rf /`, `v1.2.3-`, `v1.2.3"; curl evil`, `v1.2.3-a/b`.
- `grep -nE '\$\{\{[^}]*inputs\.tag[^}]*\}\}' release.yml` shows a single
  match on line 26 (the `env:` line), confirming no other unsanitized
  interpolation of `inputs.tag` into shell scripts.
- YAML parses cleanly (`python3 -c "import yaml; yaml.safe_load(...)"`).

### WR-01 — Placeholder-tarball publish — FIXED

**File:** `.github/workflows/release.yml:42-52`

The missing-build-script branch now has three-way logic:

1. If `scripts/build-release.sh` is executable → run it with `"$TAG"`.
2. Else if `$GITHUB_REF` starts with `refs/tags/` → `::error::` and `exit 1`
   (refuses to publish a placeholder on a real tag push).
3. Else (non-tag dry-run) → emit an empty file via `: >` (intentional
   placeholder for local/workflow_dispatch preview only).

The `Publish GitHub Release` step remains guarded by
`if: startsWith(github.ref, 'refs/tags/v')`, so a non-tag dry-run cannot
reach the publish step regardless — but the hard-fail gate on branch 2
provides defence-in-depth against future refactors that might relax the
publish guard.

### WR-02 — Anchored grep in 10-claude-md.bats — FIXED

**File:** `tests/harness/10-claude-md.bats:18-23`

New pattern: `grep -qEi "(never|avoid|do not|don't).{0,40}sudo npm install -g" CLAUDE.md`.
Empirically verified:

- Matches "Never sudo npm install -g", "Avoid ...", "Do not ...", "don't ..."
- Matches the live CLAUDE.md line 27 ("Never `sudo npm install -g` anywhere.")
- Does NOT match "Always use sudo npm install -g" or "Please sudo npm install -g"

The inline comment (lines 20-22) clearly documents the rationale, so a future
refactor of CLAUDE.md that drops the prohibiting prefix will trip the test.

### WR-03 — Stable identifier in validate-catalog error messages — FIXED

**File:** `plugin/cli/scripts/validate-catalog.mjs:29-38`

The loop now computes `const id = a.name || `<agents[${i}]>`` before running
any checks, and all three `fail()` calls reference `${id}` (lines 34, 36,
37). Empirically verified:

- Catalog with missing `name` → `agent <agents[0]>: name fails pattern ...`
  (no more "agent undefined: ..." message).
- Catalog with valid `name` but missing `description` → `agent goodname:
  missing description`.

Node parse check (`node --check`) passes. The TODO for the ajv swap in
Phase 4 is preserved (line 3).

### WR-04 — nullglob + empty-array guard in run.sh — FIXED

**File:** `tests/harness/run.sh:43-51`

Correctly implemented:

```bash
shopt -s nullglob
bats_files=("$HERE"/*.bats)
shopt -u nullglob
if [[ ${#bats_files[@]} -eq 0 ]]; then
  echo "tests/harness/run.sh: no .bats files found in $HERE" >&2
  exit 2
fi
```

Empirically verified under `set -euo pipefail`: an empty directory causes
`exit 2` with the expected message. The `shopt -u nullglob` restoration
(line 47) avoids leaking the setting into later pre-commit invocation.

The bats-missing path (lines 25-40) is preserved and still exits 127 before
the glob expansion is reached — confirmed by inspection of control flow:
the `if [[ -z "$BATS_BIN" ]]` branch terminates with `exit 127` at line 39,
ahead of any `shopt` call.

Additionally, the `"$BATS_BIN" "${bats_files[@]}"` call at line 53 uses the
quoted array expansion (not the legacy bare-glob form), which correctly
handles paths with spaces and avoids re-introducing the original bug.

## Critical Issues

None.

## Warnings

None.

## Info

None. The iteration-1 info items (IN-01..IN-06) remain on files outside the
iteration-2 scope (`test.yml`, `nightly-mutation.yml`, `bash-mutator.sh`,
`plugin/bin/agentlinux-install`) and were not re-evaluated; they are tracked
on the iteration-1 REVIEW for future consideration. The iteration-2 scope
(4 files) is clean.

---

_Reviewed: 2026-04-18T12:30:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 2 (re-review)_
