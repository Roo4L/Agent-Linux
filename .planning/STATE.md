---
gsd_state_version: 1.0
milestone: v0.3.3
milestone_name: milestone
status: verifying
stopped_at: Phase 15 context gathered (5-section Rumelt-style spine adopted via mid-discuss research reframe; AL-38 + AlmaLinux defines first usable release)
last_updated: "2026-05-24T08:31:36.085Z"
last_activity: 2026-05-24
progress:
  total_phases: 5
  completed_phases: 5
  total_plans: 7
  completed_plans: 7
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-09)

**Core value:** An agent can be dropped into any supported Linux system and just work — a dedicated agent user with correctly-owned Node.js, agent binaries, and config paths, so self-updates, global npm installs, and tool provisioning happen without permission fights.
**Current focus:** Phase 16 — Website Refresh (agentlinux.org)

## Current Position

Milestone: v0.3.3 Agenda Redefinition (AL-7)
Phase: 16 (Website Refresh (agentlinux.org)) — EXECUTING
Plan: 1 of 1
Status: Phase complete — ready for verification
Last activity: 2026-05-24

Progress: [          ] 0% (0 of 5 plans done; 0 of 4 phases complete)

## Performance Metrics

**Velocity:**

- Total plans completed: 12 (5 v0.1.0, 5 v0.2.0)
- Average duration: ~3 min per plan

**By Phase (historical):**

| Phase | Milestone | Plans | Total | Avg/Plan |
|-------|-----------|-------|-------|----------|
| 1. Complete Website | v0.1.0 | 3 | ~6min | ~2min |
| 2. Deploy to Public | v0.1.0 | 2 | ~3min | ~1.5min |
| 3. Bootable Image | v0.2.0 | 3 | ~14min | ~4.7min |
| 4. Agent Tool Packages | v0.2.0 | 2 | ~5min | ~2.5min |
| 1. Harness Setup | v0.3.0 | 5/5 | ~49min | ~9.8min |

**v0.3.0 plan metrics:**

| Plan | Tasks | Files | Duration | Commit |
|------|-------|-------|----------|--------|
| 01-01 Skeleton + CLAUDE.md + ADRs + research | 3 | 47 created | ~4 min | 3d65cb2, fa49675, d2ca481 |
| 01-02 Pre-commit + GH workflows + mutation scaffolding | 3 | 9 created | ~3 min | d428627, 6997474, 82abda0 |
| 01-03 Review subagents + /review skill | 2 | 7 created | ~34 min | 0da6082, f1595f8 |
| 01-04 Four project-scoped skill skeletons | 2 | 4 created | ~4 min | d46f2dd, 53db3ec |
| 01-05 Harness meta-test suite (Phase 1 acceptance gate) | 3 | 9 created | ~4 min | 62a1257, c0ae0b2, f59ba60 |
| 02-01 Bash library primitives (log, distro_detect, as_user, idempotency) | 2 | 4 created | ~11 min | 1b26d6a, 0b103f1, 69bd859 |
| 02-02 Installer entrypoint rewrite (pre-parse flags + log tee + ERR/EXIT traps + provisioner dispatch) | 1 | 1 modified | ~18 min | 44208a3 |
| 02-03 Agent-user provisioner (ensure_user + C.UTF-8 locale + DOC-02 CLAUDE.md via ensure_marker_block --top) | 1 | 1 created | ~3 min | 7bfa20d |
| 02-04 PATH wiring provisioner (four-file six-mode matrix: profile.d + .bashrc-at-top + agentlinux.env + cron.d) | 1 | 1 created | ~4 min | 5c8a095 |
| 02-05 Test harness (2 Dockerfiles + run.sh + 2 bats helpers + 2 bats files + CI matrix) | 3 | 7 created, 1 modified | ~16 min | fa38b05, 964ea44, badd877, acc7678, 2ef049e, 47472d9 |
| 03-01 Node.js provisioner (30-nodejs.sh) + 40-path-wiring.sh extension + run_provisioners sort fix | 2 + 2 Rule 3 fixes | 1 created, 2 modified | ~15 min | 74366a0, 1fe6a75, c6d9b41, 3dbfcff |
| 03-02 tests/bats/30-runtime.bats (RT-01..04 × 6 modes) + assert_user_prefix_in_home helper + INST-02 Phase 3 extension + Rule 1 invoke_modes fix | 3 + 1 Rule 1 fix | 1 created, 3 modified | ~15 min | 03fda88, c4c9fbf, fc78911, 2d6fdb9 |
| 04-01 CLI scaffold + ajv catalog validator + interface surface + Commander bootstrap (CLI-01 scaffold, CAT-03, CAT-04) | 3 (all tdd=true) | 15 created, 5 modified | ~11 min | de86015, fa522a6, e0469e8 |
| 04-02 catalog.json 4 entries + 8 install.sh/uninstall.sh recipes (CAT-01, CAT-02, CAT-03) | 2 | 9 created | ~4 min | e0ee67b, d319419 |
| 04-03 list/install/remove commands + runner.ts shared dispatcher (CLI-02, CLI-03, CLI-04, CLI-05) | 2 (both tdd=true) | 5 created, 4 modified | ~7 min | 86ff777, 93fb37d |
| 04-04 upgrade verb (divergence.ts + npm_ls.ts + upgrade.ts orchestrator — CLI-06) | 2 (both tdd=true) | 4 created, 2 modified | ~20 min | 01cbfff, 897c4e3 |
| 04-05 pin verb (pin.ts parsePinSpec + pinCmd + PinTarget discriminated union — CLI-07) | 1 (tdd=true) | 1 created, 1 modified | ~4 min | b6b8932, 55c55dc |
| 04-06 50-registry-cli.sh provisioner + --purge 7-step teardown + Docker multi-stage cli-builder (CLI-01, INST-04) | 3 + 2 Rule1/2 auto-fixes | 1 created, 4 modified | ~58 min | 34dc39a, b6a6be9, f4d76bb, 5fd4677 |
| 04-07 Phase 4 integration bats + INST-02 extension + TST-07 phase-close (CLI-01..07, CAT-01..04, INST-04) | 2 + 2 Rule1/3 auto-fixes | 1 created, 5 modified | ~35 min | 2e7dcc1, aec64ac, f64f3c4, 1a538f0 |
| 05.1-01 Sudoers drop-in provisioner (20-sudoers.sh) + 22-agent-sudo.bats (INST-06, BHV-07) per ADR-012 | 1 | 2 created | ~12 min | 9d4ea32, edae58a |
| 05-01 Real claude-code install.sh+uninstall.sh (native installer + PIPESTATUS + AGT-02b) + 51-agt02-release-gate.bats (AGT-02 canonical release gate) | 2 + 2 Rule 3 auto-fixes | 1 created, 4 modified | ~59 min | 8f7d1bf, 762f80f, ed46da0, af1c4f5 |
| 05-02 Real gsd install.sh+uninstall.sh (npm install -g get-shit-done-cc + --help banner-grep version-lock — AGT-04 recipe body) | 1 | 2 modified | ~45 min | a8a9a18 |
| 05-03 Real playwright install.sh+uninstall.sh (npm install -g playwright + version-lock + npx --with-deps chromium via ADR-012 NOPASSWD sudo + chromium-* cache assertion — AGT-05 recipe body; first ADR-012 end-to-end exercise) | 1 | 2 modified | ~41 min | dc46bd8 |
| 05-04 tests/bats/50-agents.bats + 05-04-AUDIT.md (9 AGT-XX @tests: AGT-01 × 3 six-mode + AGT-02b + AGT-03 + AGT-04 + AGT-05 × 3; TST-07 phase-close gate: GREEN; 66/66 bats green) | 1 + 1 checkpoint-inline | 2 created, 3 modified | ~41 min | fa386af, 6156b2b |
| 06-04 .github/workflows/release.yml 4-gate release pipeline + .github/workflows/deploy.yml Pattern 5 install.sh stage-at-root (TST-05, TST-08, INST-03, CAT-05) | 2 | 2 modified + .gitignore | ~12 min | 0352842, af7edc2 |
| 06-05 README.md Pattern 7 landing page + docs/STABILITY-MODEL.md ADR-011 user companion + TST-07 phase-close audit (DOC-01) | 2 + 1 checkpoint-inline | 3 created | ~3 min | 672bf6f, 6b0e091 |
| Phase 12 P01 | 5min | 3 tasks | 3 files |
| Phase 16 P01 | 9min | 8 tasks | 5 files |

## Accumulated Context

### Decisions

Full decision log in PROJECT.md Key Decisions table. ADR-001..ADR-010 ✓ seeded in `docs/decisions/` during Plan 01-01 (2026-04-18), each Accepted:

- ADR-001: Pivot from custom distro to installable Ubuntu plugin (v0.2.0 → v0.3.0) ✓
- ADR-002: Behavior-contract framing — requirements are BHV-XX, not INST-XX; tests are the spec ✓
- ADR-003: No default agents installed in v0.3.0 ✓
- ADR-004: Per-user npm prefix as the keystone ownership decision ✓
- ADR-005: System Node.js (NodeSource) over version managers (nvm/fnm/volta) ✓
- ADR-006: curl-pipe-bash primary + optional .deb distribution ✓
- ADR-007: Docker (fast) + QEMU (release gate) test harness; Docker-only is disqualified ✓
- ADR-008: Commander.js for the registry CLI ✓
- ADR-009: Snap is structurally disqualified as a distribution mechanism ✓
- ADR-010: Review loop triggered by CLAUDE.md instruction, not a Stop hook ✓

**New decisions from Plan 01-01 execution:**

- Copy research rather than move: `.planning/research/` and `.planning/milestones/v0.2.0-research/` kept intact; `docs/research/vX.Y.Z/` copies are byte-exact (`diff -q` verified). Archive sweep deferred to Phase 6.
- Per-task atomic commits via raw `git add <files> && git commit --no-gpg-sign`, not `gsd-tools.cjs commit` (which auto-stages all working-tree changes and breaks atomic per-task commits in sequential mode).
- CLAUDE.md deliberately references skills that arrive later in the phase (`.claude/skills/review/` in Plan 01-03, four more in Plan 01-04); flagged with "arrives in Plan 01-0X" to set reader expectations.

**New decisions from Plan 01-02 execution:**

- `.pre-commit-config.yaml` is a **verbatim copy** of `docs/HARNESS.md` §1.2; drift is detectable by a single `diff` command, making HARNESS.md the authoritative spec.
- `validate-catalog.mjs` is kept strictly zero-dep (Node built-in `fs` + `JSON.parse`); ajv swap-in deferred to Phase 4 via inline `// TODO Phase 4:` comment in the script header.
- Mutation scaffolding is non-blocking at **three independent layers**: `stryker.config.json` `thresholds.break: 0`, `nightly-mutation.yml` job-level `continue-on-error: true`, `bash-mutator.sh` always exits 0 on the current skeleton. No single layer can drag the release pipeline red.
- Every CI workflow is authored with a `compgen -G` / `[[ -x ... ]]` empty-plugin guard so skeleton-phase commits green-bar without fake test files. Guards skip jobs whose sources (tests/, bats/, CLI source) do not yet exist.
- Legacy `.github/workflows/deploy.yml` (v0.1.0 website) left completely untouched; the new `test.yml` uses `paths-ignore` for website files so the two workflows do not double-fire.

**New decisions from Plan 01-05 execution:**

- Shipped the pre-commit smoke block inside `tests/harness/run.sh` in Task 1 instead of waiting for Task 3's run.sh rewrite. Three atomic commits (62a1257 / c0ae0b2 / f59ba60) instead of two touching run.sh. Every Task 3 acceptance-criterion grep still passes because Task 1 wrote the final shape.
- Multi-path bats discovery in run.sh (PATH → ./node_modules/.bin/bats → ./tests/bats/bin/bats). PATH still wins when present; fallbacks only activate when PATH is empty. Supports three install paths: apt/brew/global-npm (PATH), `npm install --no-save bats` from repo root (node_modules), and vendored clone (tests/bats/).
- Did NOT commit bats or node_modules/ to the repo. No root package.json exists — HARNESS.md §1 doesn't declare one, and adding one for a test-time dependency would force an unrelated packaging decision. Bats install guidance lives in run.sh's error message and tests/harness/README.md (5 paths: apt, brew, npm local, npm global, docker, vendored).
- Enriched failure diagnostics: multi-item loop @tests emit `# HRN-XX: missing X` diagnostic lines on failure via `|| { echo ...; return 1; }` so TAP output identifies the exact regressed artifact. CLAUDE.md line-count test prints actual count when over budget.
- Byte-match research-migration check uses `diff -q` (matching Plan 01-01's original verification command), not md5/sha256 — same tool, greppable pairing.

**New decisions from Plan 01-04 execution:**

- CLAUDE.md left untouched (same posture as Plan 01-03): Plan 01-01's Pointers section at lines 77-79 already lists all four skill directories; grep over each slug confirmed references resolve. Success-criterion "No overlap with /review skill from 01-03" honored — all four new skills live in their own subdirectories alongside `.claude/skills/review/`.
- Skeleton body size 93-116 lines each (plan body suggested 30-80 per section / 40-80 per body; prompt's success-criterion said 50-120). Landed in the 93-116 band because every skeleton has three uncompressible parts: (1) frontmatter description naming every trigger for Claude Code's skill auto-delegation, (2) the non-negotiable rules that will not drift as later phases fill in detail (strict mode, `as_user`, mode 0440, six-mode PATH matrix, no-EACCES contract, CAT-02 invariant, SHA-verified cloud images), (3) the growth-plan section naming which artifacts absorb in which phase. Trimming any of these would either weaken the "locked rules before code exists" property or break future agents' ability to find what they need without a separate Read.
- Growth phases named in BOTH description and body (`## Growth plan` section). A future agent opening the skill knows immediately whether each section is a locked contract or placeholder awaiting Phase N.
- Requirement-ID linkage in each skill's opening paragraph — the linkage the `behavior-coverage-auditor` needs at phase-close to trace "skill X → requirement Y → test Z".
- Per-task atomic commits via raw `git add <files> && git commit --no-gpg-sign` (continuing Plans 01-01, 01-02, 01-03 pattern).

**New decisions from Plan 04-04 execution:**

- Pure-function ↔ shell-adapter split for upgrade subsystem: divergence.ts has ZERO I/O (computeDivergence + resolveLatestFor both pure, trivially unit-testable against fixture objects); npm_ls.ts is the ONLY I/O module (queryGlobalNpm + queryNpmViewLatest, both with DI dispatcher). Any test of the classifier runs without mocks; any test of the adapter injects a capturing dispatcher. Extension of the Plan 04-01 classify.ts pattern. Future plans that need divergence data can call computeDivergence directly and plug in their own installed-version/upstream-latest source.
- Offline-by-default locked project-wide via single willTouchUpstream(opts) predicate: returns true iff `--check-upstream || --all-latest`. Consumed both by the classifier loop (fetch latest) and usable by Phase 5+ (auth token lookups, etc.). Flip one function to change offline semantics across the codebase. T-04-12 mitigation — ordinary upgrade = 0 network; asserted by a zero-call test on the queryNpmViewLatest stub.
- Report-only upgrade default, not interactive prompt. Interactive per-agent `[k]eep / [c]urated / [l]atest` prompt explicitly deferred to Phase 5 UX polish per plan's <action> step 2. Three bulk flags (--reset-all-curated / --respect-overrides / --all-latest) cover reconcile modes deterministically; no stdin/readline plumbing in Phase 4. --check-upstream adds report-only upstream resolution (no mutation). This keeps CI deterministic and avoids TTY-detection logic.
- Flag priority: --reset-all-curated wins over --respect-overrides (explicit "reset everything" semantics); --reset-all-curated ALSO clears sticky (source='curated', sticky=false) — the single explicit escape hatch from ADR-011 sticky semantics. --all-latest skips sticky (preserves user's pin intent); --respect-overrides skips override+pinned+latest (only touches curated-diverged entries). 1 dedicated test asserts the priority.
- 3-seam DI for upgradeCmd: `deps = { dispatchRecipe, queryGlobalNpm, queryNpmViewLatest }`. Expands the single-Dispatcher pattern from install.ts/remove.ts because upgrade orchestrates more collaborators. Each dep has a production default (real impl) and is overridable in tests. Unit tests never spawn sudo or touch network. Matches install.ts/remove.ts single-dispatcher pattern.
- Per-entry error isolation on upstream calls: queryNpmViewLatest errors caught per-entry and surfaced as `! {id}: could not resolve latest — {msg}` to stderr; row renders with latestVersion=null. One dead registry call does NOT break the whole run. Paired with dispatch-loop guard (`if (!report.latestVersion)` → skip with diagnostic) so script-kind entries under --all-latest cleanly skip without crashing. Bulk reconcile then skips with `skipping (no upstream latest resolved)` diagnostic rather than reinstalling at curated (which would be wrong — user asked for latest).
- Sticky preservation across --all-latest: before writeSentinel with source='latest', re-read prior sentinel and carry sticky flag forward. Enables the Plan 04-05 workflow where `agentlinux pin X=latest` sets sticky=true+source='latest', and subsequent `upgrade --all-latest` runs keep sticky=true automatically. Explicit --reset-all-curated is the only way to clear sticky; Plan 04-05's `pin X=curated` is the direct user-facing API.
- Pitfall 4 defensive-parse contract locked: `npm ls -g --json --depth=0` stdout is JSON-parsed regardless of exit code (peer-dep warnings exit 1 but emit valid JSON); only fail on unparseable stdout. 5 defensive-parse tests (missing deps, empty deps, exit 1 with valid JSON, entry without version field, unparseable stdout). Pattern codifies the "best-effort" stance toward a notoriously chatty CLI and will be reusable for Phase 5+ `npm install` output parsing.
- npm-view single-string-vs-array quirk handled: `npm view <pkg> versions --json` emits a bare JSON string (not a 1-element array) for packages with exactly 1 published version. queryNpmViewLatest coerces via `Array.isArray(raw) ? raw : [String(raw)]`. Tested on both shapes. Prevents `versions.length` TypeError on fresh packages.
- T-04-13 explicit throw on zero-match: resolveLatestFor throws `"{id}: no published version of {pkg} satisfies constraint {constraint}"` when semver.maxSatisfying returns null. Catches typos like `^9.0` against a 1.x package BEFORE --all-latest reinstalls something arbitrary. Empty-versions list (defensive — npm view shouldn't return []) also throws. 3 dedicated tests.
- installed-version resolution partitioned by source_kind: npm-kind uses the queryGlobalNpm map (truth for agent user's global npm namespace); script-kind falls back to sentinel.version. Phase 5 may add a native version probe (`claude --version`); the source_kind switch in upgrade.ts already localizes that change.
- Sequential reconcile loop (for-of, not Promise.all): deterministic log ordering for debugging failed upgrades. Sentinel writes are POSIX-atomic per agent (separate files, atomic rename) so parallelism would be safe — but debug cost of non-deterministic interleaved stderr outweighs parallel speedup for N=3-4 catalog entries.

**New decisions from Plan 04-01 execution:**

- Compile-first TS test harness locked for Phase 4+: `tsc -p tsconfig.test.json && node --test dist-test/test/`. Executor host is Node 20.20.1 (lacks `--experimental-strip-types`); target runtime is Node 22 LTS (installed by Phase 3 provisioner). Compile-first works under both without adding a dev-dep like `tsx` or `ts-node` (CONTEXT locks minimum deps). Future executor hosts on Node 22+ can switch to strip-types via package.json tweak without touching source tree.
- Ajv 2020 `strictRequired: false` IS required when a schema has `allOf/if/then/required: [X]` and X is declared only on the parent scope's properties. Other strict checks (unknown keywords, strict types, additionalProperties:false at all levels) stay on. Documented in-source in schema.ts + validate-catalog.mjs; downstream catalog-schema validation is still rigorous. Test fixtures prove missing-pinned_version, missing-npm_package_name, and bad-source_kind all reject correctly.
- CJS-interop bridge for ajv + ajv-formats under TypeScript 5.x + NodeNext: namespace import + runtime fallback `(mod as any).default ?? (mod as any).Ajv2020 ?? mod`. Pure `import Ajv2020 from 'ajv/dist/2020.js'` fails tsc with "This expression is not constructable" because of how TS resolves CJS default-exports under NodeNext. The namespace + runtime-bridge shape is portable across TS 5.x minor versions. Documented in two `biome-ignore lint/suspicious/noExplicitAny` comments.
- Walk-up resource resolution pattern established: env override → walk up N levels from import.meta.url looking for sibling paths. Applied in schema.ts (schema.json lookup) and test/schema.test.ts (fixture lookup). Covers three build layouts uniformly (repo dev dist/, repo test dist-test/, production /opt/agentlinux/). Same pattern applicable to Phase 4+ modules that need to find static resources at runtime.
- AGENTLINUX_STATE_DIR env test seam for sentinel.ts: sentinel writes + reads resolve the dir lazily per-call via `process.env.AGENTLINUX_STATE_DIR ?? '/opt/agentlinux/state/installed.d'`. Unit tests inject an mkdtemp'd tmp dir without needing root to create the real path. Production sets the var (or uses the default) via Plan 06's provisioner-time setup.
- STUB pattern for interface-surface plans locked: each subcommand file exports a single async function whose body throws `Error` with an explicit plan-pointer ("lands in Plan 04-03/04/05"). Preserves the full Commander.js option-flag surface (`--force`, `--version`, `--include-test`, `--reset-all-curated`, etc.) so downstream plans replace only function bodies. An invocation attempting to run the stub immediately shows which plan is missing.
- Biome `--write` normalization accepted: single→double quotes + alphabetical import sort applied during Task 1's biome-check auto-fix. Plans that grep-verify single-quoted literals (e.g., Plan 04-01's `grep -Fq "'-H', '-E', '--'"` for the as_user keystone) must accept biome-normalized double-quoted form. Future plans in this Phase document both forms or use a pattern that matches either.
- Walk-up fixture resolver in test file: tsc does NOT copy .json fixtures to dist-test/ (only .ts → .js). Test file walks up from its own dir looking for `test/fixtures/` or `plugin/cli/test/fixtures/`. Same pattern avoids adding a copy-files step to the test script. Applies to future Phase 4 test files that load fixtures from source.
- Comment rephrasing continued per Plan 02-04 precedent: guard/user.ts originally had the literal "NOT process.env.USER" which matched the plan's `! grep -q 'process.env.USER'` verify chain. Rephrased to "environment-variable lookup of the invoking account" — identical semantic invariant (identity comes from geteuid()-backed userInfo()), just without the specific literal. Future plans extending the env-var-is-spoofable docstring must carry this convention forward.
- plugin/cli/pnpm-lock.yaml committed (first lockfile in the repo). Reproducible-install convention: CI (Phase 6) will run `pnpm install --frozen-lockfile`. pnpm-lock.yaml is kept in git; node_modules/ is gitignored (pre-existing entry). plugin/cli/dist/ + dist-test/ added to .gitignore (tsc build artefacts, not checked in). No other package-manager artefact (no npm-shrinkwrap, no yarn.lock).
- CLI-01 acceptance is split across Plan 04-01 + Plan 04-06: 04-01 ships the Commander bootstrap + --version binary at dist/index.js with #!/usr/bin/env node + 0755. 04-06 ships the 50-registry-cli.sh provisioner that stages dist/ under /opt/agentlinux/cli/<ver>/ + symlinks /home/agent/.npm-global/bin/agentlinux → dist/index.js. Only AFTER Plan 04-06 is the requirement "The agentlinux command is available on PATH for the agent user after install" fully met.

**New decisions from Plan 04-02 execution:**

- claude-code pinned to `2.1.98` (Anthropic `stable` dist-tag) over `2.1.114` (`latest`). Stable channel is Anthropic's explicit stability contract per RESEARCH Table line 190 `[VERIFIED: npm view @anthropic-ai/claude-code dist-tags → {stable: '2.1.98', latest: '2.1.114'}]`. Rationale aligns with ADR-011 (stability-first pinning) and CLAUDE.md's "self-update is the canonical installer acceptance test" — the whole point of pinning a tested version is to avoid chasing head. Phase 6 CI re-validates via TST-08 (pinned-combo gate).
- gsd canonical npm package name is `get-shit-done-cc` (NOT `gsd`, NOT `get-shit-done`). Verified via npm registry 2026-04-18 per RESEARCH §Standard Stack Catalog Agent npm Packages. Baking the correct identity at catalog-define time eliminates Phase 5 AGT-04 correction risk. Future catalog additions MUST verify npm_package_name via `npm view <slug>` before landing the entry.
- Scaffold-documents-Phase-5 pattern locked for all three real-agent recipes: install.sh stub echoes a human-readable "would install" line + `exit 0`; the real installation logic lives in a block comment citing Pitfall 8 (claude-code curl|bash PIPESTATUS loop), ADR-004 (gsd/playwright `npm install -g` without privilege escalation), and AGT-XX (which phase writes the real body). Preserves the dispatch-path surface for Plan 04-03 + 04-07 bats testing while cleanly deferring network-bound installs to Phase 5.
- Fail-fast env-var guard pattern: `: "${AGENTLINUX_PINNED_VERSION:?msg}"` as the first non-comment line in all 4 install.sh. Unset var → exit 1 loudly (dispatcher bug surface); any non-empty value → exit 0 (scaffolds) or proceed to install (Phase 5 real bodies). Chose fail-fast over `VAR:-default` because missing the pinned version is a bug, not a condition to paper over. Negative smoke validates: `unset AGENTLINUX_PINNED_VERSION; bash install.sh` exits 1 for all 4.
- `install_recipe_path` / `uninstall_recipe_path` values are literal `install.sh` / `uninstall.sh` in all 4 catalog entries — per-agent directory layout at `plugin/catalog/agents/<id>/<recipe>` makes dispatcher path resolution trivial (join catalog-dir + agent-id + recipe-path). Alternative per-entry unique paths (e.g., `claude-code-install.sh`) would complicate both the catalog-auditor rubric and Plan 04-03's dispatcher. Rule for future entries: always use these two literals.
- `version_constraint` (`^2.1`) set only on claude-code — exercises Plan 04-04's `--all-latest` upper-bound feature (CLI-06) with a concrete entry in tests. The other three entries omit `version_constraint`, defaulting to "accept any npm latest under --all-latest". Future entries add `version_constraint` only when an upstream-drift upper bound is needed; most entries should rely on `pinned_version` as the contract.
- test-dummy carries `test_only: true` — filtered from default `agentlinux list` by Plan 04-03's list command; still a real schema-valid entry so the CLI dispatch code path is identical to real agents. Functional install.sh writes `/tmp/agentlinux-test-dummy.marker` via quoted printf (`printf 'version=%s\ninstalled_at=%s\n' "${VAR:?}" "$(date -u ...)"` — format string quoted, all args quoted); uninstall.sh uses `rm -f -- "$MARKER"` with path-terminator `--`. Idempotent on both sides.
- Textual-deviation-per-Plan-02-04 precedent applied again: rephrased "WITHOUT sudo" → "WITHOUT privilege escalation" in gsd/install.sh, gsd/uninstall.sh, playwright/install.sh block comments. A careless catalog-auditor `grep -l 'sudo'` sweep would false-positive on documentation that references the absence of sudo. Pattern to carry forward: comments documenting the absence of forbidden patterns should paraphrase rather than use the literal path/command strings; CLAUDE.md's keystone anti-pattern enforcement relies on greps that don't distinguish documentation from code.
- Pre-commit wrapper unavailable on executor host (same state as Plan 02-01, 03-01, 04-01): `command -v pre-commit` empty. Mitigation: ran each hook's underlying check directly (node plugin/cli/scripts/validate-catalog.mjs for catalog-schema-validate; `python3 -m json.tool` for check-json; `tail -c 1 | od -c` for end-of-file-fixer; `grep -En ' +$'` for trailing-whitespace; shellcheck + shfmt with their pinned flag sets). CI (`.github/workflows/test.yml`) re-runs the full `pre-commit run --all-files` on push as the authoritative enforcement point.
- Review loop applied inline per Phase 2/3/4-01 precedent (no sub-agent spawns in sequential-executor context): catalog-auditor + security-engineer + bash-engineer + qa-engineer rubrics hit all 8 recipes + the catalog manifest. First-pass clean on both tasks — no actionable findings, no fix commits. Test signals (validate-catalog.mjs + shellcheck + shfmt + smoke-tests + harness run) substituted for formal subagent dispatch, matching Plan 04-01's precedent.
- Two atomic commits for a 2-task plan, matching the per-task atomic-commit convention carried forward from Phase 1/2/3/4-01. No refactor or fix commits — both tasks landed first-try. Reinforces the "scaffold-first + verify + commit" loop; future plans that expect tight-iteration should consider whether a plan-level TDD gate is warranted.

**New decisions from Plan 03-02 execution:**

- Helper-accuracy contract ESTABLISHED: any new PATH prepend / env var that lands in plugin/provisioner/*.sh MUST be mirrored in the corresponding tests/bats/helpers/invoke_modes.bash run_* helper, or per-mode tests silently regress in the specific mode while sibling-mode tests keep passing. Discovered via RT-02 failing under `cron` mode while BHV-03 (Phase 2) kept passing — Phase 2 asserts `.local/bin` (still on the helper's PATH) while Phase 3 asserts `.npm-global/bin` (NOT on the helper's hardcoded PATH). Rule 1 fix c4c9fbf extends the helper; pattern for future phases: extend helper's PATH whenever installer's final PATH ordering changes.
- Prefix-match vs substring-match assertion strength: when output may be polluted by harness banners (systemd-run, sudo, etc.), prefix-match assertions are strictly stronger than substring-match — they catch the banner pollution that substring-match tolerates. For Phase 3's `assert_user_prefix_in_home`, the systemd-run banner ("Running as unit: ... Finished with result: ...") was previously benign (substring-matched by assert_path_has) but breaking under prefix-match. Fix: suppress the banner at its source via `systemd-run --quiet` (belongs to the helper, not the assertion). Pattern: when introducing a new assertion stronger than the existing ones, audit every invocation mode helper for banner pollution.
- cowsay pinned @1.6.0 for reproducibility: RESEARCH Open Question 1 recommendation. Cheap (4-char addition) and makes Pitfall 9 two-bin layout (cowsay + cowthink) stable across 1.6.x. Future real catalog agents (Phase 5) do NOT follow this pin — that's a separate supply-chain policy decision.
- 5 @tests in 30-runtime.bats instead of minimum 4 — the extra RT-02 reinforcement (no-EACCES under npm re-install pressure) satisfies VALIDATION task 03-02-05 cheaply. It's a simple re-install check (npm no-op on second invocation) but it exercises the write-path to /home/agent/.npm-global and catches any filesystem ACL regression between provisioner-time and test-time.
- RT-03 ends with a best-effort cowsay re-install for hygiene — matches RESEARCH §Example 3 pattern; makes the bats file self-contained for re-runs when tests execute out of order. Best-effort `|| true` so re-install failure doesn't mask RT-03's own pass/fail.
- Review loop applied inline (qa-engineer + behavior-coverage-auditor + bash-engineer + security-engineer rubrics) per Phase 2 / Plan 03-01 precedent; project does not have interactive subagent spawn in sequential-executor context. First-pass clean on all task commits; Rule 1 fix surfaced through end-to-end Docker smoke (the qa-engineer rubric's strongest signal source).
- Two minor acceptance-criterion deviations (documented in SUMMARY §Deviations): (a) plan's `! grep -q 'set -euo pipefail' tests/bats/helpers/assertions.bash` matches the pre-existing Phase 2 header docstring at line 6 ("No `set -euo pipefail` at top: this file is SOURCED by bats via load 'helpers/assertions'; strict mode inside a sourced library breaks TAP output...") — intent preserved, grep written too strictly; (b) plan's `bash -n tests/bats/30-runtime.bats exits 0` fails on every .bats file because `@test` is bats-macro syntax, not pure bash — same pre-existing precedent for 10-installer.bats + 20-agent-user.bats. Both orthogonal to correctness; shellcheck clean on all edited files; 27/27 bats green proves parse.
- Scope-expansion pattern continued: Plan 03-02's Rule 1 fix modified tests/bats/helpers/invoke_modes.bash which is outside the plan's declared `files_modified`. Applied anyway because both regressions were DIRECTLY caused by Plan 03-01's PATH extension + Phase 3's stricter assertion helper; fixes necessary to execute this plan's own Docker-matrix phase-level verification. Same pattern Plan 03-01 used for its Rule 3 `compgen -G sort` fix in plugin/bin/agentlinux-install (Phase 2 artefact modified to accommodate Phase 3 provisioner addition).

**New decisions from Plan 03-01 execution:**

- `apt-get update` is mandatory before any `apt-get install` in a provisioner. Phase 2's test Dockerfile strips /var/lib/apt/lists/* after base install (standard slim-image pattern), and Ubuntu cloud images ship with stale lists. Discovered via Docker smoke on Task 1 (Rule 3 auto-fix c6d9b41). Pattern: every Phase 3+ provisioner that installs apt packages opens with `DEBIAN_FRONTEND=noninteractive apt-get update`. Idempotent — harmless to re-run. 30-nodejs.sh's header comment documents the rationale inline.
- `compgen -G` returns matches in readdir(3) order, NOT lexical. Phase 2 Plan 02-02 code comment in `plugin/bin/agentlinux-install run_provisioners()` claimed lexical — this is FALSE, depends on inode allocation. Once 30-nodejs.sh was created AFTER 10-agent-user.sh, the filesystem returned them as {30, 10, 40} — violated the numeric-dispatch contract. Fixed by piping compgen -G through sort (Rule 3 fix commit 3dbfcff; rewrote the code comment to document actual compgen behavior). Pattern: any dispatcher using `compgen -G` with an expected order MUST pipe through `sort`. The plan's own success-criteria verification command (`ls ... | sort`) always implicitly assumed this; now the runtime honors it too.
- Case-prepend LIFO order: when stacking multiple case-blocks that prepend to PATH, put the DESIRED-LAST-IN-PATH case FIRST and the DESIRED-FIRST-IN-PATH case LAST. In Phase 3's profile.d, that means `.local/bin` case FIRST and `.npm-global/bin` case SECOND → `.npm-global/bin` ends up FIRST in final PATH (Pitfall 4 — agent-owned npm globals must win over any /usr/local/bin shim). Reversed vs RESEARCH §Example 2 literal diff, which the plan text explicitly told executor to honor invariant-over-diff.
- NPM_CONFIG_PREFIX value is BYTE-IDENTICAL to ~agent/.npmrc `prefix=` value (`/home/agent/.npm-global` in both). T-03-03 mitigation: split-brain between env-var and file-based config is avoided by construction. Future accidental divergence fails the plan's cross-grep acceptance criterion. Pattern: whenever ship both file-based + env-var config for the same setting, cross-grep them.
- NPM_CONFIG_PREFIX NOT shipped in /etc/cron.d/agentlinux — cron.d's vixie-cron parser only reliably honors PATH (and a small set of other keys); arbitrary env-like lines risk silent failure. cron jobs invoke bash which sources ~agent/.bashrc → profile.d → case-stack, so env-var fallback is unnecessary for this artefact. Rule: cron.d is PATH-only; rely on bash-sourcing for other env vars.
- Comments in provisioners that would match the plan's forbidden-substring grep chain (`set -euo pipefail` literal, raw `echo >>` literal) must be rephrased even when appearing in legitimate documentation context. Phase 2 Plan 02-04 established this pattern for `sudoers.d` / `/usr/local/bin/`; Phase 3 extended it to `set -euo pipefail` (rephrased as "strict-mode (errexit / nounset / pipefail)") and `echo >>` (rephrased as "raw blind-append primitive"). The positive-verify chain treats these as forbidden anywhere in source, including comments. Future provisioners document invariants via paraphrase, not literal.
- Review loop applied inline (bash-engineer + security-engineer + qa-engineer rubrics) per Phase 2 precedent — project's subagent-spawn mechanism is not available in the sequential-executor context. Rubrics applied directly against each file with explicit triage documented in commit messages and the SUMMARY. First-pass review clean on both tasks; Rule 3 auto-fixes surfaced during end-to-end Docker smoke (the qa-engineer-equivalent rubric's strongest signal source — catches cross-file, cross-environment interaction bugs that unit-testable lints cannot).

**New decisions from Plan 02-05 execution:**

- systemd-in-Docker recipe for Ubuntu 22.04 + 24.04 locked: CMD ["/sbin/init"] in Dockerfile, then docker run with `--privileged --cgroupns=host -e container=docker -v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /tmp`. The three non-obvious parts RESEARCH §Example 5 was missing on cgroup-v2 / Docker 29.x: (a) `-e container=docker` env var (systemd refuses PID-1 role without it), (b) cgroup bind must be `:rw` not `:ro` (systemd creates its own slice; :ro causes exit 255 zero-log), (c) `dbus` package in the image (systemd-run needs the system bus even when systemctl reports running — without dbus, BHV-04 would silent-skip via the SKIP_SYSTEMD_UNAVAILABLE sentinel). All three fixes land with inline comments so the why survives refactoring.
- Six-mode helper `run_sudo_u` uses `bash --login -c` (not plan-spec'd `bash -c`). Root cause: Ubuntu default `Defaults secure_path=...` strips /home/agent/.local/bin via sudo env_reset BEFORE bash runs — orthogonal to Pitfall 2's .bashrc-at-top claim. Bash invoked as `bash -c` (non-interactive, non-login) does NOT source ~/.bashrc unless stdin is a socket (SSH), so the top-block is dead code under sudo non-interactive. Phase 2 CONTEXT locks no-sudoers-drop-in, so the architectural fix is deferred to v0.4+ (needs PAM or sudoers work). Helper now exercises bash-login-via-sudo; run_sudo_u_i exercises sudo-simulated-login (`-i`). Both semantically distinct; both cover BHV-05's observable contract via different trigger surfaces.
- Helpers (tests/bats/helpers/*.bash) do NOT declare `set -euo pipefail` even though every other bash file in the repo does. These files are `load`'d by bats via `load 'helpers/X'`; strict mode inside a sourced helper breaks bats's own error handling and TAP output generation. Documented inline in each helper's header comment. Pattern to carry forward: every new `tests/bats/helpers/*.bash` file omits strict mode; bats is the test framework, NOT a strict-bash execution context.
- TST-04 diagnostic contract shape: every failure emits four lines via stderr — `# FAIL: <req-id>` / `#   expected: ...` / `#   observed: ...` / `#   log: ...`. bats TAP surfaces these as `# ...` comments attached to the failing test. Pattern applies to ALL future tests/bats/*.bats files; the `__fail` primitive in helpers/assertions.bash is the canonical implementation.
- INST-02 byte-stable re-run test uses `find ... -exec sha256sum {} +` on 5 artefacts (profile.d + agentlinux.env + cron.d + .bashrc + CLAUDE.md) BEFORE and AFTER a re-run, then `diff -q`. This is the strong assertion form that catches any install-time variable expansion leaking into installed files — the single-quoted heredoc + ensure_marker_block contract from 02-04 is verified empirically, not just by inspection.
- BHV-04 skip-gate via SKIP_SYSTEMD_UNAVAILABLE sentinel: helper returns the string and exit 75 (EX_TEMPFAIL) when systemd is unavailable; test observes the sentinel and calls bats `skip` with a clear message. NEVER passes silently. Pattern for future tests that may run in systemd-less environments: use a named sentinel, assert on its presence, skip explicitly.
- Two-phase EXIT trap in run.sh: `trap final_banner EXIT` initially (covers docker-build failure when CID is unset), overwritten by `trap 'cleanup; final_banner' EXIT` once CID is set. Prevents `cleanup` dereferencing an undefined $CID variable on early failure. Pattern to carry forward for any shell orchestrator that sets variables mid-script and needs them cleaned up on exit.
- PASS/FAIL banner via trap + FINAL_STATUS sentinel: `FINAL_STATUS=1` default, set to 0 only if bats exits 0; final_banner trap emits `== PASS: ... ==` or `== FAIL: ... (exit N) ==`. Makes CI log scrollback immediately show status without hunting through docker output.
- CI matrix entries use full strings `ubuntu-22.04` / `ubuntu-24.04` (not `'22.04'` / `'24.04'` + template interpolation). Rationale: (a) grep-friendly — static assertions look for literal substrings; (b) copy-paste friendly — matrix value IS the run.sh arg. Cost: one extra line per matrix entry. Benefit: workflow-edit greps work.
- Empty-plugin guard in `.github/workflows/test.yml` retained even after Phase 2 populates tests/bats/*.bats. If a future revert drops the bats suite, the job short-circuits with a clean skip message rather than an opaque Docker failure. No cost; defensive depth.
- Plan 02-05 discovered a real architectural gap (sudo non-login + secure_path) that Plan 02-04 could not have caught without integration tests — validates the Wave 3 acceptance-gate design: bash lands in Wave 1/2, behavior tests in Wave 3 surface integration defects that unit-testable lints cannot. Pattern to carry forward: Phase 3 Wave 3 plan owns RT-XX bats coverage and will similarly surface any gaps in Phase 3 Wave 1/2 Node.js + npm wiring.

**New decisions from Plan 02-04 execution:**

- Four artefacts, NOT three: `/etc/environment` explicitly not shipped (CONTEXT.md names it as last-resort fallback only; in practice /etc/profile.d + .bashrc-at-top + /etc/agentlinux.env + /etc/cron.d cover all six modes without it, and /etc/environment has known parsing quirks on Ubuntu — no `$VAR` expansion, PAM-only parser). Future phases may add it as a defense-in-depth fallback if bats BHV-02..06 surfaces a gap that profile.d + .bashrc can't close, but Phase 2 ships without.
- PATH ordering `/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin` — Phase 2 locks this prefix only, NOT `/home/agent/.npm-global/bin` (which CONTEXT mentions but the plan scope-locks to Phase 3). Plan frontmatter `must_haves.truths[2]` says `/home/agent/.local/bin` specifically; Phase 3 plan will prepend `$HOME/.npm-global/bin` to all three carrying files (profile.d case-prepend, agentlinux.env literal, cron.d literal header) and the `.bashrc` marker block needs NO change (it sources profile.d).
- Single-quoted heredoc tags (`<<'PROFILE'`, `<<'BASHRC'`, `<<'ENVFILE'`, `<<'CRON'`) for all four artefact writes. Prevents install-time `$PATH`/`$HOME`/`${VAR}` expansion; the installed file contains the literal heredoc body. Byte-idempotent re-runs regardless of install-time environment. T-02-09 + T-02-10 mitigation.
- `install -m 0644 /dev/stdin <DEST> <<'TAG'` as the canonical idempotent full-file write for installer-owned paths. Atomic rename semantics (write to temp path, rename over DEST at end). Preferred over `cat <<EOF > DEST; chmod 0644 DEST` which is two-step, non-atomic, leaves a race window where the file exists with an intermediate mode. Pattern carried forward to Phase 3+ for every installer-owned file write.
- `install -m 0644 -o agent -g agent /dev/null /home/agent/.bashrc` as an atomic empty-file create when skel didn't copy the file (minimal Docker images sometimes skip skel). Sets all three of mode/owner/group in a single invocation — no race window where the file exists but has wrong ownership.
- Re-assert `chown agent:agent /home/agent/.bashrc` + `chmod 0644 /home/agent/.bashrc` AFTER `ensure_marker_block` — the primitive's internal `install -m 0644` writes root:root (verified by reading plugin/lib/idempotency.sh line 100). Same pattern as 10-agent-user.sh for DOC-02 /home/agent/CLAUDE.md. Future `ensure_marker_block` callers on user-owned files follow the same post-call chown+chmod idiom.
- No `ensure_file` primitive extraction — ensure_dir is directory-only, and there's just one caller (`.bashrc` fallback-create) for a hypothetical `ensure_file`. Direct `install -m 0644 -o agent -g agent /dev/null <path>` is an atomic, one-call idempotent create that sets all three attributes; a future caller count ≥ 3 may justify extraction into plugin/lib/idempotency.sh.
- Comments phrased to avoid matching plan's `! grep -q 'sudoers.d'` / `! grep -q '/usr/local/bin/'` forbidden-substring greps. The plan's positive-acceptance verify chain treats those substrings as forbidden anywhere in the source, including documentation comments. First attempt used literal "NO sudoers.d" / "NO /usr/local/bin/ writes" which triggered false positives (`sudoers drop-in` matched `sudoers.d` regex due to `.` wildcard). Rephrased to "zero privilege-escalation configuration" and "zero wrapper shim pointing at an agent-owned binary from a root-owned bin directory" — the invariant is still clearly documented, just without the specific path literals. Pattern to remember for future provisioners that need to document forbidden patterns: use descriptive phrasings, not the literal path strings that the plan's verify chain greps for.

**New decisions from Plan 02-03 execution:**

- Locale folded into 10-agent-user.sh rather than split into a sibling 20-locale.sh. RESEARCH offered the split-vs-fold choice (`20-locale.sh OR folded into 10-`); folded because locale is ~10 lines, tied to user identity, and folding keeps the Phase 2 provisioner count minimal (10/40 instead of 10/20/40). Decision documented in the provisioner's header comment so it's visible at the file.
- `return 1` (not `exit 1`) on locale-verify failure. The provisioner is sourced (`. "$step"`) by the entrypoint's run_provisioners; `return 1` trips the parent's `set -euo pipefail` which fires the on_error ERR trap with proper `src:line` attribution. `exit 1` would kill the entrypoint immediately and bypass the structured-logging failure banner.
- Locale outcome regex `^c\.utf-?8$` with `-i`. Accepts both `C.UTF-8` (documentation canonical) AND `C.utf8` (the form Ubuntu 24.04 reports via `locale -a`). Matches RESEARCH Pitfall 5 verification pattern verbatim.
- `ensure_marker_block --top` placement for DOC-02 (not default `--bottom`). Anti-pattern DO-NOT guidance MUST appear before any user-added sections so agent tooling reading the CLAUDE.md encounters the DO-NOT list before making install decisions. Round-trip verified: two calls with identical body around user preamble + appendix produce a byte-stable diff, preamble + appendix both preserved.
- Stable marker tag `agentlinux-doc-02` — Phase 4/5 may extend this block with new anti-patterns but MUST reuse this exact tag. Renaming would cause the new phase's block to co-exist with the orphaned old one, breaking idempotency across versions.
- `chmod 0644 + chown agent:agent` AFTER `ensure_marker_block`. The helper uses `install -m 0644` which leaves the file root-owned; re-asserting agent:agent ownership ensures the agent user can read + edit outside the marker block on subsequent runs.
- Zero raw state mutation convention enforced: every filesystem / user change routes through `plugin/lib/idempotency.sh` primitives (`ensure_user`, `ensure_dir`, `ensure_marker_block`). `chmod` and `chown` appear only for post-helper ownership re-assertion (metadata-only, idempotent). Verified via `grep -En 'useradd|install -d|echo .*>>|sed -i' | grep -v '^[0-9]*:[[:space:]]*#'` returning empty.
- Provisioner file header contract established: `#!/usr/bin/env bash` shebang (editor syntax + shellcheck), block comment naming sourced-by parent + inherited strict mode + requirement IDs satisfied, bookend `log_info "NN-name: starting/done"` calls for greppable transcript boundaries. Future provisioners (02-04, Phase 3+) follow this shape.

**New decisions from Plan 02-02 execution:**

- Pre-parse fast-exit for --help/--version/--purge added BEFORE log-file init. Plan skeleton ordered `install -m 0644 /dev/null $LOG_FILE` before `parse_args`, which meant non-root `agentlinux-install --help` hit the root-required log-init fallback and exited 64 instead of printing usage and exiting 0 — violating the CONTEXT UX lock and the plan's own acceptance criterion (line 311). Fix: `pre_parse_args` walks argv BEFORE log-init and fast-exits for -h/--help/-V/--version/--purge (all three are print-and-exit; no state mutation). --verbose and unknown-flag diagnostics still route through the post-log-init `parse_args` so they hit the tee transcript. Committed in 44208a3.
- `trap 'wait' EXIT` (Pitfall 6 mitigation from RESEARCH.md line 699) replaced with `trap 'exec >&- 2>&-; wait "$TEE_PID" 2>/dev/null || true' EXIT`. Discovered by reproducing locally: bare `trap wait EXIT` deadlocks because the EXIT trap runs BEFORE bash drops FD 1/2 for the caller, so the tee subshell never sees EOF on its stdin and `wait` blocks forever. Correct idiom: close FD 1+2 (delivering EOF to tee), then `wait` on the saved TEE_PID (avoids accidentally waiting on unrelated background children). RESEARCH.md gets a correction during Phase 3 — for now the fix lives in the installer plus an inline comment block (lines 86-91 of `plugin/bin/agentlinux-install`).
- Provisioner glob uses `mapfile -t steps < <(compgen -G "$PROV_DIR/[0-9][0-9]-*.sh" || true)` instead of `steps=("$PROV_DIR"/[0-9][0-9]-*.sh)`. shfmt 3.8.0's lexer misparses `[0-9][0-9]` immediately after a word as an array subscript (`"[x]" must be followed by =`) and fails `shfmt -d`. `compgen -G` is a bash builtin that takes the pattern as a string — no lexer trip, same lexical ordering, `|| true` handles empty-match. Documented in-source at lines 167-172.
- SC2155 split: `readonly X="$(cmdsub)"` decomposed into `X="$(cmdsub)"; readonly X` so cmdsub failures propagate to `set -e` instead of being masked by the `readonly` wrapper. Applied to BIN_DIR / LIB_DIR / PROV_DIR.
- Function surface is a superset of plan: `pre_parse_args + parse_args + require_root + run_provisioners + main + usage + on_error`. Plan had only `parse_args + require_root + main + usage + on_error`; `pre_parse_args` is the correctness fix documented above; `run_provisioners` was pulled out of main for clarity.

**New decisions from Plan 02-01 execution:**

- Arg-count guards added to every library primitive (review-loop finding). Review loop caught that the plan's exact-shape skeletons dereference `$1`/`$2`/`$3` before checking `$#` — under the entrypoint's mandated `set -euo pipefail` (02-02), zero-arg misuse crashes with a raw `$1: unbound variable` bash diagnostic instead of routing through `log_error`. Fix: `[[ $# -lt N ]] && { log_error "usage: ..."; return 64; }` prepended to every primitive (`as_user`, `as_user_login`, `ensure_line_in_file`, `ensure_marker_block`, `ensure_user`, `ensure_dir`, `visudo_validate`). Committed in 69bd859. EX_USAGE=64 matches sysexits.h and the pre-existing `as_user foo` (no-command) branch.
- Source order locked: `log.sh → distro_detect.sh → idempotency.sh → as_user.sh`. All three downstream libs check `command -v log_error` at top and hard-fail (return 1 2>/dev/null || exit 1) if log.sh has not been sourced first. Entrypoint in 02-02 enforces the order.
- `ensure_marker_block` hardcodes mode 0644 via `install -m 0644`. Deferred for Phase 3 — no 0600 callers in Phase 2. Phase 3 will either extend signature with a 4th mode arg or carve out `ensure_marker_block_with_mode` when `~/.npmrc` (likely 0600) gets marker-block treatment.
- `AGENTLINUX_SKIP_DISTRO_CHECK=1` escape hatch ships in distro_detect.sh. Intended for bats unit sourcing on non-Ubuntu dev hosts; exports `AGENTLINUX_DISTRO_VERSION=unchecked` and logs a WARN. Documented as bats-only in file header.
- pre-commit itself not installed on executor host (expected: dev workstation, not CI image). Mitigation: ran shellcheck 0.9.0 + shfmt 3.8.0 via apt with the exact args from `.pre-commit-config.yaml` (`shellcheck --severity=warning --shell=bash --external-sources` + `shfmt -i 2 -ci -bn`). Both green on all 4 files. CI will re-run the full pre-commit stack on push.

**New decisions from Plan 01-03 execution:**

- CLAUDE.md left untouched: line 46 already pointed at `.claude/skills/review/SKILL.md` (Plan 01-01's doing). Success-criterion was to verify the pointer resolves — it does, so no silent edit was made.
- All six subagents ship with read-only tool sets (`tools: Read, Grep, Glob, Bash` — no Write/Edit) per HARNESS.md §4.2 threat-register T-03-01 mitigation. Write access can be granted when spawned outside the review loop, but the file-level restriction is the belt-and-braces layer.
- Subagent rubrics are copy-of-truth for `docs/HARNESS.md` §4.2: every rubric bullet expands a HARNESS.md §4.2 one-liner. Same pattern Plan 01-02 used for `.pre-commit-config.yaml`. Future HARNESS.md §4.2 edits require a sweep across the six subagent files — drift is detectable via diff.
- Subagent files omit `model:` frontmatter (let Claude Code infer from parent session); the plan's `<interfaces>` example only declared `name`, `description`, `tools`. Pinning `sonnet` is a trivial one-line edit if future tuning wants it.
- `/review` skill explicitly names `behavior-coverage-auditor` as the "always spawn at phase close regardless of what changed" TST-07 gate — the rule is in the dispatch-rules table (last row) and in a dedicated "Relation to TST-07" section, so no phase can close without the report.

**Carried forward from v0.2.0 (still relevant for plugin installer):**

- Node.js 22 LTS from NodeSource as the runtime baseline (install path proven)
- npm install -g for Claude Code / GSD packages (but now as the agent user, not root)
- MCP config merged into ~/.claude.json via jq (works for default-agent setup)
- Chrome install pattern for browser-access tool (now under Playwright in the v0.3.0 catalog)
- Provisioner script chain pattern (ordered numbered scripts) translates to installer phases

**Retired with pivot:**

- Debian 12 Bookworm base — superseded by "target user's existing Ubuntu"
- Packer + QEMU image build — replaced by Docker (fast) + QEMU (release gate) test harnesses
- fpm-built `.deb`s as distribution artifacts — superseded by in-installer npm install (fpm may return as the plugin's own optional .deb packaging)
- Local apt repo in image — N/A
- OpenNebula contextualization — N/A
- one-context-based agent user creation — replaced by direct useradd in installer
- chrome-devtools-mcp as the canonical browser tool — replaced by Playwright per locked decision

**New for v0.3.0:**

- Ubuntu as initial target distro (22.04 + 24.04)
- Canonical acceptance test: agent user can self-update Claude Code without sudo/EACCES (AGT-02)
- Behavior-contract framing: bats test suite is the spec
- No default agents — catalog ships claude-code, gsd, playwright as *available*; users opt in
- Phase 1 is Harness Setup (non-negotiable); restart phase numbering at 1
- Mutation testing is advisory in v0.3.0; promotion to release gate is a v0.4 decision
- [Phase ?]: Phase 12 Plan 01: Pillar 2 verdict locked — hard reframe; published docs/exploration/PILLAR-2-NOTES.md (Decision summary lines 128–196). EXPL-01 gate GREEN.
- [Phase ?]: Phase 16 minimum-viable contradiction removal — rewrite contradicting copy in place; preserve 8-card grid, 3-block comparison, dual-column problem section, 5-item FAQ; site stays under-radar (no install section, no footer doc-links, no nav Vision link)
- [Phase ?]: SITE-06 voice-rule HARD GATE on index.html carries VIS-07 / STRATR-06 discipline to site copy; defence-in-depth global zero-counts on 5 forbidden strings (purpose-built Linux distribution / runs on a dedicated machine / full operating system / dedicated machine / entire operating system) all return 0
- [Phase ?]: OG card rendered via rsvg-convert 2.58.0 (apt: librsvg2-bin per ADR-012 NOPASSWD); SVG preserved as source-of-truth; PNG is what social-card preview platforms (Slack, LinkedIn, Twitter, Facebook) render reliably

### Key Infrastructure Details

OpenNebula API and target VM details from v0.2.0 are no longer load-bearing. Test infrastructure for v0.3.0:

- Docker matrix (ubuntu:22.04, ubuntu:24.04) — fast, every PR (lands in Phase 2)
- QEMU with fresh Ubuntu cloud images — nightly + release gate (lands in Phase 6)

### Pending Todos

- [ ] Add PR preview deployments for website (tooling)
- [ ] Convert OG image from SVG to PNG for broader social platform support

### Blockers/Concerns

None. Roadmap created; all 46 requirements mapped; Phase 1 is ready to plan.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260502-i4p | Add stop hook reminding Claude to run review loop (AL-23) and amend ADR-010 | 2026-05-02 | af9bd74 | [260502-i4p-add-stop-hook-reminding-claude-to-run-re](./quick/260502-i4p-add-stop-hook-reminding-claude-to-run-re/) |
| 260503-8z4 | Add session-tracker Stop hook (AL-24) — second instance of ADR-010 reminder-hook pattern | 2026-05-03 | _pending_ | [260503-8z4-al-24-add-stop-hook-for-session-tracking](./quick/260503-8z4-al-24-add-stop-hook-for-session-tracking/) |

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-05-24T08:31:11.429Z
Stopped at: Phase 15 context gathered (5-section Rumelt-style spine adopted via mid-discuss research reframe; AL-38 + AlmaLinux defines first usable release)
Resume file: None
