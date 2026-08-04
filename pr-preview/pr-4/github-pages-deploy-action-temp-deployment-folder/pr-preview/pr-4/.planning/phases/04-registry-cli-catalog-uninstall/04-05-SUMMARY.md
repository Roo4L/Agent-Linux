---
phase: 04-registry-cli-catalog-uninstall
plan: 05
plan_name: pin verb with sticky-override semantics (CLI-07)
subsystem: registry-cli
tags: [typescript, cli, pin, sticky-override, adr-011]
requirements: [CLI-07]
status: complete
requires: [04-01, 04-04]
provides:
  - "plugin/cli/src/commands/pin.ts — pinCmd + parsePinSpec + PinTarget"
  - "agentlinux pin <name>=<curated|latest|semver> user-facing verb"
  - "Sticky-flag producer consumed by upgrade.ts (Plan 04-04)"
affects:
  - "plugin/cli/src/commands/upgrade.ts — already honors sticky via Plan 04-04 (no change needed)"
tech_stack:
  added: []
  patterns:
    - "Discriminated union for parsed pin targets (curated | latest | version)"
    - "semver.valid() gate for exact-semver target (rejects partials + ranges — T-04-14)"
    - "Partial sentinel update via {...existing, source, sticky, [version]} — preserves installed_at/id"
    - "Test env seam: AGENTLINUX_CATALOG_DIR + AGENTLINUX_STATE_DIR (matches install.test.ts / upgrade.test.ts)"
    - "process.exit mock-throws Error in tests (matches install/remove error-path precedent)"
key_files:
  created:
    - "plugin/cli/test/pin.test.ts — 20 unit tests (8 parsePinSpec + 5 mutation + 4 error + 3 integration sanity)"
  modified:
    - "plugin/cli/src/commands/pin.ts — stub replaced with working impl (12 lines → 145 lines)"
decisions:
  - "pin is STATE-ONLY: never invokes install.sh (ADR-011 intent-about-existing-install semantics)"
  - "pin=latest records intent only; actual version resolution deferred to next upgrade --all-latest (RESEARCH Open Q4)"
  - "pin with no sentinel exits 1 (not 64) — distinguishes 'user meant a real agent but it's not installed' from 'bad spec' (exit 64)"
  - "parsePinSpec exported separately as a pure-function parser — testable without catalog/filesystem fixtures"
metrics:
  duration: "~4 min"
  tasks_completed: 1
  test_count_before: 92
  test_count_after: 112
  new_tests: 20
  files_created: 1
  files_modified: 1
  commits: 2
  completed_date: "2026-04-19"
---

# Phase 4 Plan 5: pin verb with sticky-override semantics Summary

`agentlinux pin <name>=<target>` ships as a TypeScript-native state-mutation verb that writes the sticky flag + source field on the sentinel, consumed by Plan 04-04's `upgrade --all-latest` / `--reset-all-curated` flow for ADR-011 nag-avoidance (Homebrew `brew pin` precedent).

## What shipped

`plugin/cli/src/commands/pin.ts` replaces the Plan 04-01 stub with a working implementation:

- **`parsePinSpec(spec)`** — pure function parser returning a discriminated `PinTarget` union. Accepts `<name>=curated`, `<name>=latest`, `<name>=<exact-semver>` (including pre-releases via `semver.valid()`). Rejects empty name (`=curated`), missing `=` (`no-equals`), and any target that's not one of the three valid shapes. Separated from `pinCmd` so it can be unit-tested without any filesystem fixture.
- **`pinCmd(spec, opts)`** — composes `parsePinSpec` → `loadCatalog({validate: true})` → `readSentinel` → `writeSentinel` with a next-state object built via spread over the existing sentinel. Preserves `id` + `installed_at`; mutates only `source`, `sticky`, and (for `=<semver>`) `version`.

### PinTarget discriminated union

```typescript
export type PinTarget =
  | { name: string; target: 'curated' }
  | { name: string; target: 'latest' }
  | { name: string; target: 'version'; version: string };
```

Tagged union lets call sites switch exhaustively; TypeScript strict mode catches missing branches.

### Sticky-flag lifecycle

| pin target       | source written | sticky written | version written              |
| ---------------- | -------------- | -------------- | ---------------------------- |
| `=curated`       | `'curated'`    | `false`        | unchanged (preserved)        |
| `=latest`        | `'latest'`     | `true`         | unchanged (Open Q4 — resolved at next upgrade --all-latest) |
| `=<semver>`      | `'pinned'`     | `true`         | `<semver>` (user assertion)  |

**Clearing logic:** `pin name=curated` is the canonical "unpin" verb — it clears both the sticky flag and the source, re-aligning the entry with the catalog's curated pin on the next `upgrade`. No `pin --clear` or `unpin` verb needed; re-casting "remove pin" as "pin to curated" matches Homebrew's `brew unpin`-but-simpler UX.

**Upgrade interaction (confirmed by integration sanity tests):**
- After `pin foo=latest`, `upgrade --all-latest` SKIPS foo (sticky=true). Verified end-to-end.
- After `pin foo=2.0.0`, `upgrade --reset-all-curated` CLEARS the pin and reinstalls at catalog pin. Verified end-to-end.

### Error policy

| Scenario                              | Exit | Message                                         |
| ------------------------------------- | ---- | ----------------------------------------------- |
| No `=` in spec (`noeq`)               | 64   | `expected '<name>=<target>' (got 'noeq')`       |
| Empty name (`=curated`)               | 64   | `expected '<name>=<target>'`                    |
| Bogus target (`foo=not-a-version`)    | 64   | `invalid target 'not-a-version' ... curated, latest, or exact semver` |
| Empty target (`foo=`)                 | 64   | `invalid target ''`                             |
| Unknown agent (`unknown=curated`)     | 64   | `no such agent in catalog: unknown`             |
| Agent not installed (no sentinel)    | 1    | `not installed — run 'agentlinux install foo' first` |

Exit-64 uses EX_USAGE semantics (user-facing command misuse). Exit-1 for missing install distinguishes "real agent, not installed yet" from "bad spec" — gives users a clear next step.

## Threat model

**T-04-14 (pin flag integrity):** Mitigations applied per plan threat register:
- `parsePinSpec` validates the target ∈ {curated, latest, exact-semver} BEFORE any sentinel read or write — invalid specs exit 64 with no state mutation.
- `semver.valid()` rejects partials (`2.1`), ranges (`^2.1`, `>=1.0`), and typos (`lateset`) — only point-version pins accepted.
- Pin requires an existing sentinel (exit 1 on missing) — no drive-by "pre-declared intent" for v0.3.0 (locked per plan objective; Phase 5+ may revisit).
- `writeSentinel` is atomic (tmp + rename(2)) per existing implementation — concurrent pin invocations on different agents can't corrupt each other.
- No shell interpolation: the user-supplied spec flows only into JSON-serialized sentinel fields, never into a shell-out.

## Test coverage

**20 new unit tests** in `plugin/cli/test/pin.test.ts` across 4 suites:

### parsePinSpec (8 tests)
- curated / latest / exact-semver / pre-release-semver (happy paths)
- invalid target / no `=` / empty name / empty target (error paths)

### pinCmd state mutation (5 tests)
- `=curated` clears sticky + source
- `=latest` sets sticky=true + source=latest; version preserved
- `=<semver>` sets sticky=true + source=pinned + version=<semver>
- Round-trip: `installed_at` and `id` preserved across pin
- Idempotent: `pin=curated` on already-curated sentinel is a no-op

### Error paths (4 tests)
- Not-installed sentinel → exit 1 with `agentlinux install <name>` hint
- Unknown agent → exit 64 with `no such agent` + available list
- Bad spec (no `=`) → exit 64 with usage message
- Bogus target RHS → exit 64 with valid-targets help

### Integration sanity (3 tests)
- After `pin=latest`, sentinel shape is exactly what upgrade.ts reads
- End-to-end: `pin foo=latest` + `upgrade --all-latest` SKIPS foo (no recipe call)
- End-to-end: `pin foo=2.0.0` + `upgrade --reset-all-curated` clears pin and reinstalls foo at catalog pin (`1.0.0`)

Total: 112/112 tests green (up from 92). The integration-sanity suite is the regression canary — if someone refactors upgrade.ts to accidentally ignore `sticky`, this plan's tests trip too.

## Deviations from Plan

**None — plan executed exactly as written, with one minor stylistic adjustment.**

### Procedural: biome format collapsed two-line template strings
- **Found during:** Post-GREEN `pnpm run check`
- **Issue:** Plan sample's error messages used `\`line-1\n\` + \`line-2\`` string concatenation; biome's `useTemplate` + `noUnusedTemplateLiteral` rules flag this as a style error on the shipped codebase
- **Fix:** Collapsed each two-line template to a single template literal with embedded `\n` — identical runtime output, passes biome
- **Files modified:** `plugin/cli/src/commands/pin.ts` (2 spots — the "expected <name>=<target>" thrown error and the "invalid target" thrown error)
- **Commit:** included in GREEN commit `55c55dc` (no separate fix commit — caught before GREEN landed)

This matches the 04-03 precedent where biome safe-fixes were applied inline during the GREEN pass. No functional deviation.

## Review loop triage

Applied the three reviewer rubrics inline per Phase 4-01/02/03/04 precedent; no actionable findings and no fix commits needed beyond the two task commits.

- **node-engineer rubric:** Discriminated union is exhaustive; `semver.valid()` used (not regex) per verify grep; `parsePinSpec` is a pure function with three-shape parsing + two error paths; defensive `return` after `process.exit` preserves TypeScript narrowing when tests mock `process.exit` to throw. Clean.
- **security-engineer rubric (T-04-14):** Target validation gates all sentinel writes; no shell interpolation; atomic-rename preserved; no pre-declared intent on missing sentinel; catalog loaded with `validate: true` so a malformed catalog fails fast before any state mutation. Clean.
- **qa-engineer rubric:** Every target branch has a mutation test; every error path has an exit-code test; round-trip integrity verified; idempotency verified (pin=curated on already-curated is a no-op); integration sanity confirms upgrade.ts's sticky-consumer contract. 20 tests against a 14-test plan target — thorough. Clean.

One iteration, zero fix commits.

## Commits

| # | Hash      | Type | Message                                                                    |
| - | --------- | ---- | -------------------------------------------------------------------------- |
| 1 | `b6b8932` | test | test(04-05): add failing pin-verb tests (RED) — parsePinSpec + pinCmd + integration sanity |
| 2 | `55c55dc` | feat | feat(04-05): pin verb with sticky-override semantics (CLI-07 per ADR-011) |

TDD RED/GREEN cycle observed — RED commit ships failing tests (tsc rejects the stub's missing `parsePinSpec` export), GREEN commit ships the implementation that turns all tests green. No refactor commit needed — the shipped code is as minimal as the plan requires.

## Verify chain (all green)

```
pnpm run build                        # tsc clean
pnpm test                             # 112/112 green
pnpm run check                        # biome clean on 30 files
grep -c 'parsePinSpec' pin.ts         # 3 (export + 2 internal refs)
grep -Fq 'semver.valid' pin.ts        # OK
grep -Fq 'source: "curated"' pin.ts   # OK (all three target branches)
grep -Fq 'source: "latest"' pin.ts
grep -Fq 'source: "pinned"' pin.ts
grep -Fq 'sticky: true' pin.ts        # OK
grep -Fq 'sticky: false' pin.ts       # OK
bash tests/harness/run.sh             # 104/104 green (unchanged)
node plugin/cli/dist/index.js pin --help  # renders usage + CLI-07 description
```

## Self-Check: PASSED

- [x] `plugin/cli/src/commands/pin.ts` exists (verified — 145 lines, full impl)
- [x] `plugin/cli/test/pin.test.ts` exists (verified — 20 unit tests)
- [x] Commit `b6b8932` exists in git log (RED phase)
- [x] Commit `55c55dc` exists in git log (GREEN phase)
- [x] `pnpm test` shows 112/112 tests green
- [x] `pnpm run check` clean on 30 files
- [x] `bash tests/harness/run.sh` still 104/104 green
- [x] `parsePinSpec` + `pinCmd` + `PinTarget` exported from pin.ts
- [x] Three target branches implemented (curated/latest/pinned)
- [x] Error paths: exit 1 (missing sentinel), exit 64 (bad spec / unknown agent)

Next: Plan 04-06 (50-registry-cli.sh provisioner + --purge teardown + Docker builder stage — CLI-01 PATH, INST-04).
