---
phase: quick
plan: 260525-nv0
subsystem: tests
tags: [tests, secrets, ci, docs, internals]
requires:
  - .gitignore .env.* rule (existing)
  - SEC-05 gitleaks pre-commit + full-history gate (existing)
  - bats helpers/assertions.bash invariants (style template)
provides:
  - require_secret <VAR> bats helper (yellow-skip on unset)
  - SECRET_ALLOWLIST contract in tests/docker/run.sh
  - .env.local -> docker -e VAR forwarding path
  - GH Actions secrets -> nightly-qemu workflow env path
  - docs/internals/test-secrets.md (four-section internals doc)
affects:
  - tests/docker/run.sh (Docker runner extended with secret forwarding)
  - .github/workflows/nightly-qemu.yml (step-level env block added)
  - docs/internals/README.md (Test infrastructure subsection added)
  - .gitignore (!.env.local.example exception added)
tech-stack:
  added: []
  patterns:
    - "bash indirect expansion ${!var-} for safe param lookup under set -u"
    - "docker run -e VAR (no =value) to keep secrets out of ps argv"
    - "set -a / set +a bracketing for .env.local sourcing"
    - "step-level env: block in GH Actions (vs job-level) for narrower blast radius"
    - "four-section internals doc contract (problem -> answer -> value -> related)"
key-files:
  created:
    - .env.local.example
    - tests/bats/helpers/secrets.bash
    - tests/bats/00-secrets-smoke.bats
    - docs/internals/test-secrets.md
    - .planning/quick/260525-nv0-al-53-test-secrets-infrastructure/260525-nv0-SUMMARY.md
  modified:
    - .gitignore
    - tests/docker/run.sh
    - .github/workflows/nightly-qemu.yml
    - docs/internals/README.md
decisions:
  - "Step-level env: block on nightly-qemu.yml's QEMU boot step (NOT job-level): narrower blast radius. Only the one step that needs the key sees it."
  - "Bats smoke file uses 00- filename prefix: sorts before behavioral suites so the convention example is the first test discovered."
  - "Explicit SECRET_ALLOWLIST bash array (rejected dotenv-file blanket forward): the allowlist is grep-able in PR review and trivially auditable; a blanket forward leaks anything in the calling shell."
  - "${!var_name-} (dash-default) indirect expansion in require_secret (rejected eval and plain ${!var_name}): the dash form returns empty under set -u; eval would be a code-injection vector if the var name ever came from untrusted input."
  - ".env.local.example committed as commented-only template (no uncommented KEY=value pairs): defence in depth alongside .gitignore + gitleaks; a future placeholder = pair would degrade gitleaks signal-to-noise."
  - "Per-PR test.yml deliberately untouched: per-PR jobs never see the release-gate sandbox key; require_secret skips yellow there. PR authors cannot exfiltrate the secret via a malicious test because the per-PR jobs never see it."
metrics:
  duration: ~25min
  tasks: 3
  files_modified: 8
  completed: 2026-05-25
ticket: AL-53
---

# Quick Plan 260525-nv0: AL-53 test-secrets infrastructure Summary

One-liner: Lands the four-layer test-secrets pipeline (`.env.local` ->
`SECRET_ALLOWLIST` -> docker `-e VAR` -> bats `require_secret`, plus the
parallel GH-secrets-to-nightly-qemu path) so AL-54 and any future
secret-bearing bats spec have a single, documented, gitleaks-safe path
from a sandbox key to a `@test` body.

## What was built

Three commits, eight files. The deliverables fall into three layers:

### Layer 1 — Local feedback loop (Task 1, commit 2d7d31b)

- `tests/bats/helpers/secrets.bash` — single function `require_secret <VAR>`.
  Uses `${!var_name-}` indirect expansion (safe under `set -u`); calls
  bats's `skip` builtin to yellow-skip when the var is unset/empty.
  Mirrors `helpers/assertions.bash` invariants: no `set -euo` at top
  (sourced library), explicit `local $1`, no `eval`.
- `tests/bats/00-secrets-smoke.bats` — convention example with the
  `AL-53:` test-name prefix so `behavior-coverage-auditor`'s TST-07 grep
  finds the trace. Calls `require_secret FOO`, asserts `FOO=bar`. `00-`
  filename prefix makes it the first test discovered.
- `.env.local.example` — committed template; two commented rows
  (ANTHROPIC_API_KEY, FOO). No uncommented KEY=value pairs.
- `.gitignore` — `!.env.local.example` negation rule added (since
  `.env.*` would have ignored the template otherwise).

### Layer 2 — Transport (Task 2, commit 16693fd)

- `tests/docker/run.sh` — `SECRET_ALLOWLIST` bash array near the top
  (two rows today). Sources `.env.local` (if present) via `set -a` /
  `set +a` bracketing. Builds `DOCKER_ENV_FLAGS` array; forwards only
  allowlisted, non-empty vars via `docker run -e VAR` (no `=value`).
- `.github/workflows/nightly-qemu.yml` — step-level `env:` block on the
  `QEMU boot + installer + bats` step declares
  `ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}`. `test.yml`
  deliberately untouched.

### Layer 3 — Documentation (Task 3, commit 181996b)

- `docs/internals/test-secrets.md` — four-section internals doc
  (`## The problem`, `## What AgentLinux does`, `## Value vs the naive
  approach`, `## Related`) per the dev-docs SKILL.md contract. Plus a
  `## Worked example` carrying the four-step add-a-secret checklist,
  the 90-day sandbox rotation procedure, and the three-step
  leak-response runbook (revoke -> rotate -> post-mortem). 192 lines,
  product-perspective tone, no GSD vocabulary.
- `docs/internals/README.md` — new `## Test infrastructure` subsection
  between the agent-catalog list and `## Audience`. Single bullet linking
  `test-secrets.md`; the subsection is a hook for future cross-cutting
  test docs.

## Verification gates

All Task-level `<verify>` gates passed before each commit:

- `bash -n tests/bats/helpers/secrets.bash` — syntax clean.
- `bash -n tests/docker/run.sh` — syntax clean.
- `shellcheck --severity=warning --shell=bash --external-sources
  tests/docker/run.sh` — clean.
- `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/nightly-qemu.yml'))"`
  — well-formed.
- `git diff .github/workflows/test.yml` — zero changes (per-PR isolation
  preserved).
- `! grep -q 'ANTHROPIC_API_KEY' .github/workflows/test.yml` — confirmed.
- `! grep -q '--env-file' tests/docker/run.sh` — confirmed (initial
  comment containing the literal `--env-file` string was reworded to
  `blanket dotenv-file forward` to avoid the grep-gate false positive).
- All four mandatory H2 headings + `## Worked example` present in
  `test-secrets.md`; `rotation` and `leak response` both present.
- `pre-commit run --files docs/internals/test-secrets.md
  docs/internals/README.md` — clean (end-of-files, trailing whitespace,
  gitleaks, all passed).

The local end-to-end smoke (`echo FOO=bar > .env.local && bash
tests/docker/run.sh ubuntu-24.04`) and shellcheck of the whole runner
are queued for the post-execute review-loop pass (this executor cannot
spin up Docker in a worktree sandbox).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `.env.local.example` initially gitignored by `.env.*`**
- **Found during:** Task 1 verification — `git status` did not show
  the newly-created `.env.local.example`.
- **Issue:** The plan's `<interfaces>` block noted that the existing
  `!.env.example` exception does NOT auto-allow `.env.local.example`
  (different filename) and instructed verifying with `git check-ignore`.
  Verification confirmed `.env.local.example` was ignored; an explicit
  negation was required (as the plan anticipated).
- **Fix:** Added `!.env.local.example` (with a leading comment block
  explaining the AL-53 origin) to `.gitignore` after the `.env.*` line
  and the existing `!.env.example` exception.
- **Files modified:** `.gitignore`
- **Commit:** 2d7d31b (folded into Task 1).

**2. [Rule 3 - Blocking] Verification grep `! grep -q '--env-file'` tripped on the explanatory comment**
- **Found during:** Task 2 verification.
- **Issue:** The original Task 2 comment block in `tests/docker/run.sh`
  contained the phrase `a blanket forward (e.g. --env-file) would leak`
  to motivate the allowlist design. The literal string `--env-file`
  matched the negative grep gate in the plan's `<verify>` block, which
  was intended to catch the actual `--env-file` flag in a `docker run`
  invocation.
- **Fix:** Reworded the comment to `a blanket dotenv-file forward would
  leak` — same prose intent, no literal flag. The plan's gate now passes
  cleanly; the rationale is preserved.
- **Files modified:** `tests/docker/run.sh`
- **Commit:** 16693fd (folded into Task 2 before commit).

### Architectural decisions deferred

None. The QEMU-guest secret-forwarding (boot.sh -> ssh -> bats inside
the VM) is documented as AL-54's scope per the plan's hard-constraint
note; AL-53 ships only the workflow-env injection half.

## Out-of-scope (called out in the plan)

- `.env.local` sourcing inside the QEMU guest's bats process — deferred
  to AL-54 (boot.sh ssh forwarding).
- Gitleaks rule additions — already shipped under SEC-05 (defence in
  depth covers AL-53's leak path).
- Per-PR CI receiving the sandbox key — explicitly NOT done. `test.yml`
  unchanged; `require_secret` yellow-skips per-PR.
- Calendar reminder for the 90-day rotation — avoid-ceremony rule
  (single developer, single key today). Future ticket can add it.

## Threat-model coverage

All mitigate-disposition threats in the plan's STRIDE register are
addressed by the shipped code:

| Threat | Mitigation landed |
|--------|-------------------|
| T-AL53-01 (`.env.local` committed) | `.env.*` gitignore + `!.env.local.example` exception; SEC-05 gitleaks gate; `.env.local.example` audit (no uncommented KEY=value pairs). |
| T-AL53-02 (`docker run -e "VAR=$VAR"` interpolation) | `-e VAR` form only — verified by `! grep -E '-e "[A-Z_]+=\$' tests/docker/run.sh`. |
| T-AL53-03 (`--env-file` blanket forward) | Explicit `SECRET_ALLOWLIST` array; `! grep -q '--env-file' tests/docker/run.sh` clean. |
| T-AL53-04 (per-PR CI receives release-gate secret) | `test.yml` untouched; `! grep -q 'ANTHROPIC_API_KEY' .github/workflows/test.yml` clean. |
| T-AL53-05 (job-level `env:` over-broadcasts) | Step-level `env:` on the boot step only; not the job. |
| T-AL53-06 (variable-name injection in `require_secret`) | `${!var_name-}` indirect expansion; no `eval`, no command substitution on the var name. |

Accept-disposition threats (T-AL53-07/08/09) are documented in
`test-secrets.md` and the plan's `<threat_model>`.

## Commits

| # | Hash    | Title |
|---|---------|-------|
| 1 | 2d7d31b | feat(tests): bats require_secret helper + .env.local template (AL-53) |
| 2 | 16693fd | feat(tests): docker secret-forwarding + nightly QEMU env injection (AL-53) |
| 3 | 181996b | docs(internals): test-secrets.md (AL-53) |

## Self-Check: PASSED

- `.env.local.example`: FOUND
- `tests/bats/helpers/secrets.bash`: FOUND
- `tests/bats/00-secrets-smoke.bats`: FOUND
- `tests/docker/run.sh`: MODIFIED (SECRET_ALLOWLIST + DOCKER_ENV_FLAGS array)
- `.github/workflows/nightly-qemu.yml`: MODIFIED (step-level env block)
- `.github/workflows/test.yml`: UNCHANGED (verified clean with `git diff`)
- `docs/internals/test-secrets.md`: FOUND (192 lines, all four mandatory H2 sections present)
- `docs/internals/README.md`: MODIFIED (## Test infrastructure subsection added)
- `.gitignore`: MODIFIED (`!.env.local.example` exception)
- Commit 2d7d31b: FOUND
- Commit 16693fd: FOUND
- Commit 181996b: FOUND
