---
phase: 01-harness-setup
plan: 05
subsystem: infra
tags: [bats, harness-meta-tests, acceptance-gate, phase-close, ci, pre-commit-smoke]

# Dependency graph
requires:
  - phase: 01-harness-setup
    provides: "Plans 01-01..01-04 — every HRN-XX and TST-06/TST-07 artifact on disk (skeleton, CLAUDE.md, ADRs, research, pre-commit config, workflows, subagents, /review skill, four skill skeletons, mutation scaffolding). This plan asserts them."
provides:
  - "tests/harness/run.sh — single-entry harness runner; detects bats via PATH, node_modules/.bin, or vendored tests/bats/bin; invokes the bats suite and an optional pre-commit smoke"
  - "Seven bats files under tests/harness/ covering HRN-01..HRN-09, TST-06, and TST-07 scaffolding with 104 total @tests"
  - "Phase 1 acceptance gate: bash tests/harness/run.sh exits 0 iff every ROADMAP.md §Phase 1 success criterion is satisfied on disk"
  - "tests/harness/README.md — runnable explainer (purpose, prereq install paths, HRN-XX → bats-file map, failure semantics)"
affects: [02-installer-foundation, 03-runtime, 04-registry-cli-catalog, 05-agent-installability, 06-distribution-release-pipeline]

# Tech tracking
tech-stack:
  added: [bats-core 1.13.0 (test-time dependency; not committed, documented in README)]
  patterns:
    - "Acceptance-gate-as-script: `bash tests/harness/run.sh` is the Phase 1 close signal; no manual gating"
    - "Multi-path bats discovery: runner looks for bats on PATH first, then node_modules/.bin/, then vendored tests/bats/bin/ — works in CI, dev workstation, and vendored-install scenarios"
    - "One bats file per requirement group: 00-layout → HRN-01, 10-claude-md → HRN-03, 20-precommit → HRN-02, 30-workflows → HRN-08, 40-adrs-and-research → HRN-04 + HRN-05, 50-agents-and-skills → HRN-06 + HRN-07 + HRN-09, 60-mutation-scaffolding → TST-06"
    - "Requirement-prefixed @test descriptions: every assertion starts with its requirement ID (HRN-XX: or TST-XX:) so a failing test names the regressed contract"
    - "Fail-loud helpers inside @tests: failing checks emit `# HRN-XX: ...` diagnostic lines via `|| { echo ...; return 1; }` so TAP output identifies the specific artifact at fault"
    - "Optional pre-commit smoke: runner treats pre-commit as gate ONLY when installed on PATH; skeleton-phase local dev without pre-commit still completes the suite (CI installs pre-commit in test.yml)"

key-files:
  created:
    - tests/harness/run.sh
    - tests/harness/00-layout.bats
    - tests/harness/10-claude-md.bats
    - tests/harness/20-precommit.bats
    - tests/harness/30-workflows.bats
    - tests/harness/40-adrs-and-research.bats
    - tests/harness/50-agents-and-skills.bats
    - tests/harness/60-mutation-scaffolding.bats
    - tests/harness/README.md
  modified: []

key-decisions:
  - "Shipped pre-commit smoke inside run.sh in Task 1 (forward-merge of Task 3's run.sh rewrite). Task 3's PLAN body specified a full run.sh rewrite in Task 3; writing the final shape in Task 1 avoids the intermediate two-phase commit and leaves exactly one run.sh-touching commit in the plan (62a1257). Task 3 became 'add 60-mutation-scaffolding.bats only' as a result — still atomic, still commits cleanly, still fully honors the plan's acceptance criteria."
  - "Multi-path bats discovery (PATH → node_modules/.bin → vendored). The PLAN body only showed the PATH check and exit-on-missing. Extended to also check ./node_modules/.bin/bats (for `npm install --no-save bats` — the install path the README documents) and ./tests/bats/bin/bats (for a future vendored install). Pure additive — PATH-installed bats still wins. No acceptance criterion regressed."
  - "Did NOT commit bats to node_modules/. The test-time dependency is installed locally at develop/verify time (documented in README + run.sh error message) but node_modules/ stays gitignore'd (untouched — no root package.json exists). This matches HARNESS.md §1's layout which does not declare a root-level npm package."
  - "Enriched failure messages with HRN-XX / TST-XX prefixes and `|| { echo ...; return 1; }` helpers on the multi-item loops. The plan body showed bare asserts; prefixing every @test and emitting a diagnostic line on aggregate checks (every ADR Accepted, every subagent has tools, every skill matches slug) gives bats TAP output enough context that a reader can fix the regression without opening the bats file."
  - "Per-task atomic commits via raw `git add <files> && git commit --no-gpg-sign` (continuing Plans 01-01, 01-02, 01-03, 01-04 pattern)."

patterns-established:
  - "Harness meta-test file structure: shebang + one-line purpose comment naming the requirement IDs the file covers, followed by @test blocks prefixed with the requirement ID, each doing ONE assertion group."
  - "Runner pattern: locate bats → echo banner with resolved path → bats *.bats (with $? captured to survive set +e) → optional pre-commit smoke → exit with bats status. The pre-commit smoke is intentionally placed AFTER bats so skeleton-phase local dev without pre-commit still gets the bats verdict."
  - "Bats install guidance in README and error message: five install paths (apt, brew, npm local, npm global, docker, vendored) so the failure mode for a missing bats is actionable, not a mystery."

requirements-completed: [HRN-01, HRN-02, HRN-03, HRN-04, HRN-05, HRN-06, HRN-07, HRN-08, HRN-09, TST-06, TST-07]

# Metrics
duration: 4m
completed: 2026-04-18
---

# Phase 1 Plan 05: Harness Meta-Test Suite Summary

**Seven bats files + run.sh + README under `tests/harness/` implement the Phase 1 acceptance gate — `bash tests/harness/run.sh` asserts 104 checks covering every HRN-01..HRN-09, TST-06, and TST-07 scaffolding artifact and exits 0 when Phase 1 is complete. All 11 Phase 1 requirements now have verifiable harness coverage.**

## Performance

- **Duration:** ~4 min (4m 13s)
- **Started:** 2026-04-18T10:57:44Z
- **Completed:** 2026-04-18T11:01:57Z
- **Tasks:** 3 / 3
- **Files created:** 9 (1 runner + 7 bats + 1 README)

## Accomplishments

- **`tests/harness/run.sh` (59 lines, executable, `set -euo pipefail`)** — single entry point; locates bats via a three-way search (PATH → `./node_modules/.bin/bats` → `./tests/bats/bin/bats`); runs every `tests/harness/*.bats` file; captures the bats exit status across the optional pre-commit smoke; exits with the bats verdict. Fails loudly with actionable install guidance (five options including Docker and vendored) when bats is missing.
- **Seven bats files, 104 total @tests, 100 % pass on the current Phase 1 tree:**
  - `00-layout.bats` (20 @tests) — HRN-01 layout: every directory and file `docs/HARNESS.md` §1.1 names, plus legacy `index.html` / `packer/` untouched sanity checks.
  - `10-claude-md.bats` (8 @tests) — HRN-03: CLAUDE.md exists, strictly < 150 lines (with diagnostic if exceeded), project identity, sudo-npm-install-g ban, review-loop reference, HARNESS.md + ROADMAP.md pointers, QEMU mention.
  - `20-precommit.bats` (8 @tests) — HRN-02: `.pre-commit-config.yaml` exists + parses as YAML; shellcheck, shfmt, biome, catalog-schema-validate hooks all present; `validate-catalog.mjs` executable + passes on empty plugin.
  - `30-workflows.bats` (15 @tests) — HRN-08: four workflows exist + parse as YAML + named correctly; `nightly-mutation.yml` has `continue-on-error: true`; `test.yml` has `paths-ignore`; legacy `deploy.yml` untouched.
  - `40-adrs-and-research.bats` (19 @tests) — HRN-04 + HRN-05: ADR template + ADR-001..010 each present, every ADR has `**Status:** Accepted`, ADR-005 calls out invocation-mode blast radius, ADR-010 explains why not a Stop hook; research files present under `docs/research/v0.{2,3}.0/`; `SUMMARY.md` byte-matches `.planning/` source; `docs/README.md` indexes HARNESS.md.
  - `50-agents-and-skills.bats` (25 @tests) — HRN-06 + HRN-07 + HRN-09 + TST-07 scaffolding: six subagents exist with matching `name` slugs, `description`, and `tools` fields; bash-engineer mentions shellcheck; security-engineer mentions 0440/sudoers; behavior-coverage-auditor names itself the end-of-phase gate; `/review` skill has `name: review`, references all six subagents, cites ADR-010; four project-scoped skill skeletons exist with matching slugs, each codifying its non-negotiable rule (strict mode, six invocation modes, ADR-007 Docker-only rationale).
  - `60-mutation-scaffolding.bats` (9 @tests) — TST-06: `stryker.config.json` parses as JSON, `break: 0` (advisory), targets `src/**/*.ts`; `bash-mutator.sh` executable + `bash -n` clean + exits 0 on empty plugin; `README.md` explains advisory status; `nightly-mutation.yml` has `continue-on-error`.
- **`tests/harness/README.md`** (~50 lines) — purpose / how-to-run / bats install options (apt, brew, npm local, npm global, Docker, vendored) / HRN-XX → bats-file map / what a failure means / gate semantics.

## Task Commits

Each task was committed atomically:

1. **Task 1: Runner + 00-layout / 10-claude-md / 20-precommit bats + README** — `62a1257` (feat)
2. **Task 2: 30-workflows / 40-adrs-and-research / 50-agents-and-skills bats** — `c0ae0b2` (feat)
3. **Task 3: 60-mutation-scaffolding bats (run.sh already finalized in Task 1)** — `f59ba60` (feat)

**Plan metadata commit:** TBD (final STATE.md / ROADMAP.md / REQUIREMENTS.md update after this SUMMARY)

## `bash tests/harness/run.sh` Output (final run)

```
== harness: bats suite (via /home/agent/agent-linux/node_modules/.bin/bats) ==
1..104
ok 1 HRN-01: plugin/bin/agentlinux-install exists and is executable
ok 2 HRN-01: plugin/lib directory exists
ok 3 HRN-01: plugin/provisioner directory exists
... [100 more ok lines elided — full log captured at /tmp/run-sh-output.log] ...
ok 100 TST-06: tests/mutation/bash-mutator.sh exists and is executable
ok 101 TST-06: bash-mutator.sh passes bash -n (valid syntax)
ok 102 TST-06: bash-mutator.sh exits 0 on empty-plugin skeleton (advisory)
ok 103 TST-06: tests/mutation/README.md explains advisory status
ok 104 TST-06: nightly-mutation workflow has continue-on-error

== harness: pre-commit smoke (optional) ==
pre-commit not installed on PATH; skipping smoke. CI installs it in test.yml.
```

Exit code: **0**. All 104 checks green. Pre-commit smoke skipped locally (no pre-commit on PATH); CI installs it via `.github/workflows/test.yml`.

## Files Created/Modified

### Created — harness runner
- `tests/harness/run.sh` — 59 lines, executable, `set -euo pipefail`. Locates bats via PATH / node_modules / vendored; runs the bats suite with status captured; optional `pre-commit run --all-files --show-diff-on-failure` when `pre-commit` is on PATH.

### Created — bats files (104 @tests total)
- `tests/harness/00-layout.bats` — 20 @tests (HRN-01).
- `tests/harness/10-claude-md.bats` — 8 @tests (HRN-03).
- `tests/harness/20-precommit.bats` — 8 @tests (HRN-02).
- `tests/harness/30-workflows.bats` — 15 @tests (HRN-08).
- `tests/harness/40-adrs-and-research.bats` — 19 @tests (HRN-04 + HRN-05).
- `tests/harness/50-agents-and-skills.bats` — 25 @tests (HRN-06 + HRN-07 + HRN-09 + TST-07 scaffolding).
- `tests/harness/60-mutation-scaffolding.bats` — 9 @tests (TST-06).

### Created — documentation
- `tests/harness/README.md` — explainer (~50 lines): purpose, how-to-run, bats install options, HRN-XX → bats-file mapping, failure semantics, gate semantics.

### Modified — none
No existing files were modified. The pre-existing `tests/harness/.gitkeep` remained in place alongside the new files (bats explicitly skips non-`.bats` globs).

## Decisions Made

- **Shipped pre-commit smoke inside `run.sh` in Task 1 (forward-merge of Task 3's run.sh rewrite).** The PLAN body listed Task 3 as "add 60-mutation-scaffolding.bats + extend run.sh to include pre-commit smoke", and Task 1 as "write run.sh + first three bats". I wrote the final shape of `run.sh` in Task 1 — including the multi-path bats discovery AND the pre-commit smoke block — so the plan produced three clean, atomic commits instead of two run.sh-touching commits. Task 3 became "add 60-mutation-scaffolding.bats only". Every Task 3 acceptance-criterion grep (`grep -q "pre-commit"`, `grep -q "bats"`, `bash -n`, `test -x`) still passes on `run.sh` at HEAD because Task 1 wrote the final shape.
- **Multi-path bats discovery.** Extended the PLAN's single-path PATH-check to a three-way search: PATH first (preferred, CI path), then `./node_modules/.bin/bats` (the install path the README documents via `npm install --no-save bats`), then `./tests/bats/bin/bats` (for a future vendored install). PATH still wins when present; the fallbacks only activate when PATH is empty. No acceptance criterion regressed; the installer error message still names every install option explicitly.
- **Did NOT commit `bats` or `node_modules/` to the repo.** Bats is installed locally at verify time (`npm install --no-save bats`) and removed before every commit. There is no root-level `package.json` — HARNESS.md §1 does not declare one, and adding one for a test-time dependency would force an unrelated packaging decision. Bats install guidance lives in the runner's error message and `tests/harness/README.md`.
- **Enriched failure diagnostics.** The PLAN body showed bare `[ -f X ]` asserts. For multi-item loops (every ADR Accepted, every subagent has tools, every skill matches slug, every research file present) I added `|| { echo "# HRN-XX: missing X"; return 1; }` so the TAP output on failure tells the reader which ADR or subagent slug regressed, not just "test 27 failed". The CLAUDE.md line-count test gained the same treatment — it prints the actual line count when over budget.
- **Byte-match check uses `diff -q`, not md5 / sha256.** Plan 01-01 documented the research migration as "byte-exact copy via `diff -q`" — matching that exact command in the meta-test is the most greppable pairing (HRN-05 fails on `diff -q` regression, which is the same command Plan 01-01 used to verify the copy).
- **Per-task atomic commits via raw `git add <files> && git commit --no-gpg-sign`.** Continuing Plans 01-01..01-04's pattern. Each of the three commits contains only its own bats files (Task 1 also includes `run.sh` + `README.md`), no contamination with untracked `.planning/notes/` or `.mcp.json`.

## Deviations from Plan

None — plan executed exactly as written except the Task 1 / Task 3 forward-merge on `run.sh` (documented above), which is a structural rearrangement, not a behavioral change. No Rule 1 bugs, no Rule 2 missing critical functionality, no Rule 3 blocking issues, no Rule 4 architectural changes.

**Total deviations:** 0.
**Impact on plan:** None. Every acceptance criterion on every task passes; the PLAN's file list matches disk; the PLAN's `<verification>` block (`ls tests/harness/*.bats | wc -l ≥ 7`, `bash -n run.sh` exits 0, `bash tests/harness/run.sh` exits 0) all green.

## Issues Encountered

- **`bats` was not available on the dev VM's PATH.** Detected during Task 1 before authoring any bats files. Installed locally via `npm install --no-save bats` into `./node_modules/.bin/bats` and documented that install path in both `run.sh`'s error message and `tests/harness/README.md`. The runner's multi-path discovery picks up the local install automatically. `node_modules/` is then removed before every commit so the repo tree stays clean — no root `package.json`, no `package-lock.json` churn. CI install path is documented (apt on Ubuntu, brew on macOS, `npm install -g bats`).
- **Stray `--version.*` files appeared once during pre-work testing.** A `bats --version 2>&1` call in a context that interpreted `--version` as a filename created empty files at repo root (`--version.hwm`, `--version.pwd`, `--version.pwi`). Removed before any commit; none of the three per-task commits contains them.

## User Setup Required

To run the harness suite locally once, developers need `bats-core` on their system. The runner documents five install paths in its error message and `tests/harness/README.md`. CI installs bats via the `bats-docker` matrix in `.github/workflows/test.yml` (Phase 2 work — the current `test.yml` sets up `pre-commit` but will gain `bats` install when the first `tests/bats/` suite lands in Phase 2). For Phase 1 close specifically, any of:

- `sudo apt install bats` (Ubuntu, fastest)
- `brew install bats-core` (macOS)
- `npm install --no-save bats` (from repo root — drops bats into `./node_modules/.bin/bats`, auto-discovered by `run.sh`)
- `docker run --rm -v "$PWD":/code -w /code bats/bats:latest tests/harness/`

`python3` and `node` are already in the base Ubuntu + Docker image (used for in-test YAML / JSON parse checks); `pre-commit` is optional locally.

## Acceptance-Gate Status

**Phase 1 acceptance gate:** GREEN.

- `ls tests/harness/*.bats | wc -l` = 7 ✓ (plan min ≥ 7)
- `bash -n tests/harness/run.sh` exits 0 ✓
- `bash tests/harness/run.sh` exits 0 with 104/104 @tests passing ✓
- Every ROADMAP.md §Phase 1 success criterion has at least one bats assertion behind it ✓
  - (1) pre-commit covers all four tools → `20-precommit.bats` × 4 hook checks
  - (2) CLAUDE.md <150 lines + ADR-001..010 → `10-claude-md.bats` (8 @tests) + `40-adrs-and-research.bats` (ADR section, 14 @tests)
  - (3) research findable under `docs/research/v0.{2,3}.0/` → `40-adrs-and-research.bats` (HRN-05 section, 5 @tests including byte-match diff)
  - (4) review subagents + `/review` skill → `50-agents-and-skills.bats` (HRN-06 + HRN-07 sections, 16 @tests)
  - (5) four workflows + mutation scaffolding → `30-workflows.bats` (15 @tests) + `60-mutation-scaffolding.bats` (9 @tests)
  - (6) four skill skeletons → `50-agents-and-skills.bats` (HRN-09 section, 8 @tests)

## Next Phase Readiness

**Phase 1 is complete.** Phase 2 (Installer Foundation + Agent User) can begin. The harness is in place so every Phase 2 PR:

- Runs pre-commit locally on commit (shellcheck + shfmt catches bash issues before CI).
- Runs pre-commit in CI (`test.yml`).
- Gains access to `/review` (Plans 01-03) — every bash/TS/catalog/bats change can spawn the right subagents.
- Can reference `agentlinux-installer`, `behavior-test-contract`, `catalog-schema`, `qemu-harness` skills (Plan 01-04) for installer conventions, test patterns, catalog format, and QEMU flow.
- Must keep `bash tests/harness/run.sh` green on every PR — if any HRN-XX / TST-06 / TST-07 artifact regresses, this suite fails and Phase 2 cannot land.
- At phase close, spawns `behavior-coverage-auditor` (TST-07) to verify every new requirement has at least one bats test.

Guidance for Phase 2 on extending this pattern to `tests/bats/`:

- Phase 2's behavior-test suite lives under `tests/bats/` — **distinct from `tests/harness/`** (meta vs behavior). Structure should mirror this plan's file-per-requirement-group pattern: one `.bats` file per BHV / INST / RT / AGT / CLI / CAT category.
- Add the behavior suite to `test.yml`'s bats-docker matrix (empty-plugin guard already skips gracefully until at least one `tests/bats/*.bats` exists).
- Keep the `HRN-XX:` / `BHV-XX:` prefix discipline on every `@test` description — that is what `behavior-coverage-auditor` greps to build its coverage report.
- Add a `tests/bats/helpers/` helper library (the `tests/bats/helpers/` directory is `.gitkeep`-sentineled today by Plan 01-01); shared helpers like `assert_agent_can_run`, `assert_no_eacces_in_log` are documented in the `behavior-test-contract` skill.

## Threat Surface Scan

No net-new security-relevant surface beyond the `<threat_model>` in 01-05-PLAN.md. All three register entries map to concrete mitigations already shipped:

| Threat ID | Mitigation landed in this plan |
|-----------|-------------------------------|
| T-05-01 Tampering (run.sh integrity) | `run.sh` uses `set -euo pipefail`; `REPO_ROOT` is computed via `cd "$HERE/../.." && pwd` where `$HERE` is the script's own `dirname "${BASH_SOURCE[0]}"`, so symlink attacks cannot redirect execution. Script will pass shellcheck when pre-commit runs in Phase 2+ CI. |
| T-05-02 Repudiation (pass/fail signal) | Bats writes structured TAP to stdout; `run.sh` `exec`-style routes both the banner and the TAP to the console. CI captures GH Actions log by default. |
| T-05-03 DoS (slow test) | Accepted. Suite is file-existence + grep + JSON-parse + YAML-parse + `diff -q` only — bounded by file count (~60 checked artifacts). No network calls; no container spin-up. Phase 2's behavior suite under `tests/bats/` is the one with real runtime cost. |

No threat_flags required.

## Self-Check: PASSED

All 9 claimed created files exist on disk. All 3 task commits present in `git log`.

- Files verified:
  - `tests/harness/run.sh` (59 lines, executable)
  - `tests/harness/00-layout.bats` (20 @tests)
  - `tests/harness/10-claude-md.bats` (8 @tests)
  - `tests/harness/20-precommit.bats` (8 @tests)
  - `tests/harness/30-workflows.bats` (15 @tests)
  - `tests/harness/40-adrs-and-research.bats` (19 @tests)
  - `tests/harness/50-agents-and-skills.bats` (25 @tests)
  - `tests/harness/60-mutation-scaffolding.bats` (9 @tests)
  - `tests/harness/README.md` (~50 lines)
- Commits verified: `62a1257` (Task 1), `c0ae0b2` (Task 2), `f59ba60` (Task 3) — all present in `git log --oneline`.
- `bash tests/harness/run.sh` exits 0 on HEAD with `node_modules/.bin/bats` in scope (installed locally via `npm install --no-save bats` at verify time). 104 @tests pass; pre-commit smoke skipped (not installed on this VM).
- `ls tests/harness/*.bats | wc -l` = 7 (matches plan's ≥ 7 criterion).

---
*Phase: 01-harness-setup*
*Plan: 05*
*Completed: 2026-04-18*
