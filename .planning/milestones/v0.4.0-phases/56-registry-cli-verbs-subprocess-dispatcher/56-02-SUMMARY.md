---
phase: 56-registry-cli-verbs-subprocess-dispatcher
plan: 02
subsystem: infra
tags: [rust, cli, verbs, adapters, serde, sentinel, catalog, detect-cache, tsrewrite, bats]

# Dependency graph
requires:
  - phase: 55-rust-pure-core
    provides: "the pure agentlinux-core gates (classify/decide_version/derive_category/presence_gate/reuse_gate/remediate_gate/parse_pin_spec/semver_shim) + DetectedAgent/CatalogEntry/Sentinel lean types"
  - phase: 56-registry-cli-verbs-subprocess-dispatcher
    plan: 01
    provides: "clap CLI structs (cli.rs), RecipeEnv + resolve_install_user (recipe_env.rs), the dispatcher, canonical_path/GSD_SYSTEM_PATH in main.rs, and the AGENTLINUX_STAGE_RUST_CLI run.sh override"
provides:
  - "the four bin-side file adapters: guard.rs (CLI-05), catalog.rs (FullCatalogEntry + preserve_paths traversal reject), sentinel.rs (atomic write-path shape), cache.rs (detect-cache reader, deferred from Phase 55)"
  - "the three read-only/state-only verbs: cmd/list.rs (byte-compatible padded table + --by-category + --json Row), cmd/pin.rs, cmd/adopt.rs — all consuming the pure gates, dispatching NO recipe"
  - "CLI-05 guard wired into main::dispatch before EVERY verb (mirrors the TS preAction hook)"
affects: [56-03-install-remove-upgrade, 56-04-phase-close, 57-provisioner-port, 58-cutover]

# Tech tracking
tech-stack:
  added: [serde 1 (derive) + serde_json 1 (bin), thiserror 1 (bin), tempfile 3 (dev)]
  patterns:
    - "Full→core entry projection via serde_json::json! so field semantics stay in lockstep with the lean core CatalogEntry (no hand-mapping to drift)"
    - "skip_serializing_if = Option::is_none on the write-path Sentinel + list Row so serialized JSON byte-matches the TS JSON.stringify (omits undefined)"
    - "Atomic sentinel write = tmp+rename(2) with a trailing newline; POSIX rename overwrites in one step (T-56-08)"
    - "The host statSync re-validation lives in the calling verb adapter (cmd/adopt.rs), NOT the pure gate and NOT cache.rs — the pure/I-O seam holds"
    - "The CLI-05 guard is a single dispatch-level call (matching the TS preAction hook), so verbs never re-guard"

key-files:
  created:
    - rust/crates/agentlinux/src/guard.rs
    - rust/crates/agentlinux/src/catalog.rs
    - rust/crates/agentlinux/src/sentinel.rs
    - rust/crates/agentlinux/src/cache.rs
    - rust/crates/agentlinux/src/cmd/mod.rs
    - rust/crates/agentlinux/src/cmd/list.rs
    - rust/crates/agentlinux/src/cmd/pin.rs
    - rust/crates/agentlinux/src/cmd/adopt.rs
  modified:
    - rust/crates/agentlinux/src/main.rs
    - rust/crates/agentlinux/Cargo.toml
    - rust/Cargo.lock

key-decisions:
  - "CLI-05 guard runs ONCE in main::dispatch (mirroring the TS index.ts preAction hook that guards actionCommand.name() before ANY subcommand — including read-only `list`). Verbs do NOT re-guard; the plan's per-verb `guard_agent_user(...)` wording is honored by the single dispatch-level call. This is why CLI-05 `agentlinux list` as root exits 64."
  - "The four adapters carry a Task-1-boundary module-scoped #![allow(dead_code)] (catalog/sentinel/cache) — they have no non-test consumer until the Task-2/3 verbs import them; the #[cfg(test)] modules exercise every item. Mirrors the Wave-0 recipe_env/dispatcher scaffold pattern."
  - "now_iso8601 is hand-rolled (civil-from-days, no chrono dep) so adopt's reused-sentinel timestamp matches the TS `new Date().toISOString()` shape while keeping the bin dependency-light."
  - "catalog_dir/detect_cache_path/state_dir are resolved via dedicated env-seam helpers (resolve_catalog_dir / detect_cache_path / installed_dir) so the bats seams (AGENTLINUX_CATALOG_DIR / AGENTLINUX_DETECT_CACHE / AGENTLINUX_STATE_DIR) drive the Rust build identically to the TS."

requirements-completed: [VERB-01, GATE-01, GATE-05]

# Metrics
duration: 45min
completed: 2026-07-28
status: complete
---

# Phase 56 Plan 02: Read-only / State-only Verbs + File Adapters Summary

**The four bin-side file adapters (guard/catalog/sentinel/cache) + the three no-subprocess verbs (`list`/`pin`/`adopt`) over the pure `agentlinux-core` — byte-compatible stdout (em-dash suffixes, `## <label>` groups, `--json` Row/AdoptResult arrays), the CLI-05 invoker guard, the preserve_paths traversal reject, and atomic sentinel writes — with `list`/`adopt` green on `40-registry-cli.bats` against the staged Rust musl bin, and `pin` unit-green (bats-blocked only by the Plan-03 `install` fixture).**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-07-28T17:17Z (approx)
- **Completed:** 2026-07-28T18:03Z
- **Tasks:** 4
- **Files:** 11 (8 created, 3 modified)

## Accomplishments

- **Task 1 — the four file adapters:**
  - `guard.rs`: CLI-05 invoker guard. geteuid-backed invoker (`nix::unistd::User::from_uid(geteuid())`, NOT an env var; exposed as a test-DI param), the exact two-line stderr message, exit 64. Wired into `main::dispatch` before every verb.
  - `catalog.rs`: `FullCatalogEntry` (field names byte-identical to `types.ts:7-49` so the SAME `catalog.json` deserializes) + `load_catalog(dir, validate)`. Ports the preserve_paths traversal reject (loader.ts:31-65, **T-56-06**): reject non-`~/`, absolute, or `..`-containing paths, with a lexical `normalize_path` matching Node's `path.normalize` for the check. Honors `AGENTLINUX_CATALOG_DIR`.
  - `sentinel.rs`: full write-path `Sentinel` (`types.ts:57-89`) + read/**atomic** write (tmp+`rename`, trailing newline, **T-56-08**)/delete/list. `skip_serializing_if = Option::is_none` byte-matches the TS `JSON.stringify` (omits `undefined`). Honors `AGENTLINUX_STATE_DIR`.
  - `cache.rs`: the deferred Phase-55 detect-cache reader → `agentlinux_core::types::DetectedAgent`, accepting BOTH `.agents` and `.components.agents` shapes; `None` on absent/unparseable. The `statSync` re-validation is deliberately absent (lives in the verb adapters). Honors `AGENTLINUX_DETECT_CACHE`.
- **Task 2 — `list`:** the padded NAME/STATUS/CURATED/INSTALLED table via the PURE `classify`/`derive_category`/`presence_gate` (never re-derives). The INSTALLED-column suffixes are copied byte-for-byte incl. the em-dash `—` (U+2014) — reused/broken/drift/present-adopt/present-reconcile/present-migrate. `--by-category` renders `## <label>` groups in `derive_category` order; `--json` emits the field-identical `Row` array. Ports `probe_installed_version` (npm package.json read) + the AL-61/62 presence hints. Always exits 0.
- **Task 3 — `pin` + `adopt`:** state-only sentinel mutations via the ported pure gates, dispatching NO recipe.
  - `pin`: PURE `parse_pin_spec` → on `Err` print the ported `PinSpecError` message + exit 64; unknown → 64; not-installed → present-hint sentences to STDERR via `presence_gate` + exit 1; else partial-update the sentinel and print the exact `pinned to`/`pin cleared`/`follow upstream` literals.
  - `adopt`: exit 64 on no-name-no-`--all`/unknown/test-only; per entry PURE `reuse_gate` THEN the host `std::fs::metadata(path).is_file()` re-validation **in the adapter**; PURE `remediate_gate` for the AL-62 migration candidate. Writes a `status:"reused"` sentinel; prints the `[ADOPT]`/`already managed`/`[MIGRATE]`/`nothing to adopt` literals. `--all` sweep, `--json` `AdoptResult` array.
- **Task 4 — Wave-1 bats gate:** ran `AGENTLINUX_STAGE_RUST_CLI=1 ./tests/docker/run.sh ubuntu-24.04 40-registry-cli` against the staged Rust musl bin. `list` + `adopt` @tests are GREEN; `pin` is bats-blocked only by its `install` setup dependency (Plan 03). No code change was needed — no list/adopt parity gap surfaced.

## Task Commits

Each task committed atomically:

1. **Task 1: file adapters (guard/catalog/sentinel/cache)** — `028ecfc` (feat)
2. **Task 2: list verb** — `aabffd5` (feat)
3. **Task 3: pin + adopt verbs** — `a84a4ff` (feat)
4. **Task 4: Wave-1 bats gate** — no code change (list/adopt already green; pin blocked by the Plan-03 `install` fixture). Findings recorded in this SUMMARY; bats spec untouched.

## Verification (per-task, exact)

- **Task 1:** `cargo test -p agentlinux catalog:: sentinel:: cache:: guard::` → **24 pass** (8 catalog + 5 sentinel + 6 cache + 5 guard): preserve_paths traversal reject (absolute + `..`), sentinel atomic round-trip + trailing newline + None-field omission, cache dual-shape + `AGENTLINUX_DETECT_CACHE` override + null-on-absent, guard invoker-mismatch.
- **Task 2:** `cargo test -p agentlinux cmd::list` → **4 pass**: em-dash suffix byte strings, present-adopt/migrate suffixes, padded-table golden, `--json` Row serialization.
- **Task 3:** `cargo test -p agentlinux cmd::pin` → **4 pass**; `cargo test -p agentlinux cmd::adopt` → **6 pass**: exact stdout/stderr literals + exit map (pin 64/1; adopt 64) + the reused-sentinel round-trip + the epoch formatter.
- **Task 4 (bats on the Rust build):** `AGENTLINUX_STAGE_RUST_CLI=1 ./tests/docker/run.sh ubuntu-24.04 40-registry-cli` — **list/adopt GREEN, pin bats-blocked by the `install` fixture**. Per-@test (Wave-1 scope):
  - **`list` GREEN:** CLI-02 default (#3), `--include-test` (#4), `--json` (#5); AL-61 present overlay (#8); AL-62 migrate overlay (#11); CAT-01 (#24), CAT-04 (#26), CAT-03 fixture (#27).
  - **`adopt` GREEN:** AL-61 no-args-64 (#6), greenfield-noop (#7), reused-sentinel record (#9), adopt-on-install hook (#10); AL-62 migrate candidate (#12).
  - **guard (CLI-05) GREEN:** root exits 64 (#19), agent succeeds (#20).
  - **`pin` DEFERRED (not a parity gap):** CLI-07 (#22, #23) fail because their bats `setup` runs `agentlinux install --include-test test-dummy` first, which is a **Wave-2 (Plan 03) stub** (exit 70). The pin verb logic is fully unit-green; end-to-end bats confirmation of pin lands when Plan 03 wires `install`.
- **Workspace gates:** `cargo test --workspace` → **64 (bin) + 121 (core) pass**; `cargo clippy -p agentlinux --all-targets -- -D warnings` → **clean**; `cargo fmt --all --check` → **clean**.
- **Purity:** `grep -rnE 'std::(process|fs|env)'` over `agentlinux-core/src/` finds only `#[cfg(test)]` uses (pre-existing, untouched by this plan) — the pure core stays pure; all new I/O is in the bin.
- **Seam checks:** `grep metadata|is_file cache.rs` → only the doc comment (the stat is absent — it lives in the verb adapter); `grep metadata|is_file cmd/adopt.rs` → the adapter statSync present; `grep dispatch_recipe|as_user cmd/pin.rs cmd/adopt.rs` → nothing (state-only).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Bin crate lacked serde/serde_json/thiserror deps**
- **Found during:** Task 1.
- **Issue:** The Wave-1 adapters need serde (deserialize catalog.json/sentinels/detect-cache) + serde_json + thiserror (typed `CatalogError`), and the adapter unit tests need `tempfile`; none were in `rust/crates/agentlinux/Cargo.toml`.
- **Fix:** Added `serde`/`serde_json`/`thiserror` as normal deps and `tempfile` as a dev-dep (all already in the workspace / core; legitimacy inherited).
- **Committed in:** `028ecfc`.

**2. [Rule 3 - Blocking] Task-1 adapters are dead code until the verbs import them**
- **Found during:** Task 1 (clippy `-D warnings`).
- **Issue:** With no verb consumers yet, the whole adapter surface is dead code from clippy's view — the Task-1 commit would not compile clippy-clean in isolation.
- **Fix:** Added a module-scoped `#![allow(dead_code)]` to catalog/sentinel/cache (documented as a Task-1-boundary artifact), mirroring the Wave-0 `recipe_env`/`dispatcher` scaffold pattern. The `#[cfg(test)]` modules exercise every item, so nothing is truly unreachable. The allows become silently redundant once Tasks 2/3 wire the consumers (Rust does not warn on redundant `allow`).
- **Committed in:** `028ecfc` (+ per-item allows on the Plan-03-only surface: `delete_sentinel`, `read_detected_agent`, the `FullCatalogEntry` recipe-path fields).

**3. [Deviation - minor] CLI-05 guard wired once at dispatch, not per-verb**
- **Found during:** Task 3.
- **Issue:** The plan's Task-3 action says "Guard via `guard_agent_user(\"pin\", …)`" inside each verb. The TS guards ONCE via a Commander `preAction` hook (index.ts:34-36) that runs before ANY subcommand, not per-command.
- **Fix:** Wired the single guard call into `main::dispatch` (before the verb match), passing the verb name — byte-identical behavior to the TS preAction, and it correctly covers the read-only `list` (CLI-05 `agentlinux list` as root → exit 64, bats #19). Verbs do not re-guard (a double-guard would be a behavior divergence). Minimal correct choice per the deviation protocol.
- **Committed in:** `a84a4ff` (the guard call itself landed in `028ecfc`).

## Known Stubs

- `install`/`remove`/`upgrade` remain loud `EX_SOFTWARE(70)` "not implemented yet (Wave 2)" stubs in `main::dispatch` — by plan design (Plan 03 scope). They are loud (non-zero, no silent success), so a premature invocation cannot false-green.
- No stubs exist inside the Wave-1 verbs themselves — `list`/`pin`/`adopt` are complete.

## Deferred to Plan 03 / Plan 04 (phase close)

- **`pin` end-to-end bats (CLI-07 #22/#23):** blocked only by the `install` fixture in the bats `setup`. Confirmed green the moment Plan 03 lands `install`. The pin verb is fully unit-green now.
- **CLI-03/04/06 + INST-04 (#13-18, #21, #28):** install/remove/upgrade @tests — Plan 03 scope; they fail against the current stubs (expected).
- **CLI-01 (#1/#2):** the `run.sh` `AGENTLINUX_STAGE_RUST_CLI` override symlinks `~agent/.npm-global/bin/agentlinux → ~agent/.local/bin/agentlinux`, so `which agentlinux` resolves the `.local/bin` reuse-shim path (PATH order) instead of the `.npm-global` path CLI-01 asserts; the SSH-mode sub-case also hit an environmental ssh-key error. This is a Plan-01 staging-mechanic detail (not a list/pin/adopt parity issue) — recorded for Plan 04's closeout to reconcile the override target (or adjust the reuse-shim staging path).
- **Network/systemd-gated cases:** none of the list/pin/adopt @tests are network/systemd-gated in plain Docker; all ran (no newly-skipped for these verbs). The real-install network cases live in `50-agents.bats` (not this file).

## Threat Flags

None. The plan's `<threat_model>` register (T-56-06 preserve_paths traversal, T-56-07 guard, T-56-08 atomic sentinel write, T-56-09 cache path) is fully implemented as specified: the traversal reject (absolute + `..` rows) is unit-tested; the guard invoker is geteuid-backed (not caller-controllable); the sentinel write is tmp+rename atomic; the detect-cache path is the same `AGENTLINUX_DETECT_CACHE` seam as the TS (no new surface).

## Self-Check: PASSED

- Created files present: `guard.rs`, `catalog.rs`, `sentinel.rs`, `cache.rs`, `cmd/mod.rs`, `cmd/list.rs`, `cmd/pin.rs`, `cmd/adopt.rs` — all FOUND.
- Commits present: `028ecfc`, `aabffd5`, `a84a4ff` — all FOUND in git log.
- `agentlinux-core` unchanged by this plan (empty diff stat) — the pure core is untouched.

---
*Phase: 56-registry-cli-verbs-subprocess-dispatcher*
*Completed: 2026-07-28*
