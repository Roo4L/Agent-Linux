# Phase 56: Registry CLI Verbs + Subprocess Dispatcher - Research

**Researched:** 2026-07-28
**Domain:** Rust port of the TS registry CLI (6 verbs) + the sudo-u/streaming-tee/timeout/SIGTERM→SIGKILL subprocess dispatcher + the generated `AGENTLINUX_*` recipe env-var contract + the deferred cache-read adapter. Parity pinned by the bats behavior suite + the TS command unit tests.
**Confidence:** HIGH (all findings grounded in this repo's source; the only genuinely-new component — the dispatcher — has a complete unit-test spec that fully pins its behavior)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None locked. CONTEXT.md marks this a **Smart-discuss infrastructure-skip** phase: "like-for-like CLI port; contract-equivalent stdout/exit codes — no observable behavior change." The one hard, non-negotiable bar is **contract-equivalent stdout + identical exit codes the bats assert** — NOT identical internal structure. Enforced by GATE-01 (full bats green for the CLI surface, no regression / no newly-skipped) and GATE-05 (master shippable; parallel track; per-phase rollback).

### Claude's Discretion (recommended shape below — not binding)
- The Rust `agentlinux` bin (Phase-53 thin bin) grows the six real verbs: `list`, `install`, `remove`, `upgrade`, `pin`, `adopt`, consuming `agentlinux-core`.
- Arg parser: the Phase-53 plain-argv `match`, OR `clap` if the verb/flag surface warrants — **research weighs this below (§Arg Parsing) and recommends `clap`.**
- The dispatcher (sudo-u / streaming-tee / timeout / SIGTERM→SIGKILL) is the one genuinely NEW systems component — port it faithfully.
- **VERB-03 env-var contract:** generate the 6 `AGENTLINUX_*` names from ONE typed Rust source consumed by both the dispatcher and a manifest the recipes source, so a rename can't desync. The 6 names: `PINNED_VERSION`, `CATALOG_DIR`, `AGENT_HOME`, `SOURCE_KIND`, `INSTALL_LOG`, `PRESERVE_PATHS` (runner.ts:46-54).
- The cache-read I/O deferred from Phase 55 (`readCachedAgentById` / `detectCachePath`) lands here as the adapter feeding the ported detect gates.
- Parity oracle: the CLI bats (40-registry-cli, 50-agents, 10-installer, 23-install-user) + the TS command unit tests. Bats stays green on the Rust build (Docker OOM → targeted per-file runs; stage the Rust bin like Phase 53's run.sh does).

### Deferred Ideas (OUT OF SCOPE)
- Provisioner port (agent-user / sudoers / nodejs / path-wiring / registry-staging + detect/remediate/reuse/idempotency) + `CANONICAL_PATHS` consolidation → **Phase 57. Keep the maps duplicated this phase.**
- musl tarball as sole channel + drop fpm `.deb` → **Phase 58.**
- Full-matrix bats + QEMU validation gate → **Phase 59.**
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VERB-01 | `list / install / remove / upgrade / pin / adopt` produce contract-equivalent stdout + exit codes to the TS CLI; `CLI-*` + `50-agents`/list/upgrade/pin bats green. | §The Six Verbs — full stdout/exit/flag contract + core-consumption map per verb. §Standard Stack, §Architecture Patterns. |
| VERB-02 | The subprocess dispatcher runs recipes as target user (`sudo -u`), streams (tee), enforces a timeout, escalates SIGTERM→SIGKILL; dispatcher/streaming behavior tests green. | §VERB-02 — the Dispatcher — exact TS source (state/dispatcher.ts) mapped line-by-line + the `dispatcher-stream.test.ts` parity spec + Rust crate recommendation. |
| VERB-03 | The 6 `AGENTLINUX_*` env vars generated from a single typed Rust source; the ~25 Bash recipes run unchanged (a rename can't desync). | §VERB-03 — the Env-Var Contract — the 6 names, their recipe consumption (grep counts), and the single-typed-source recommendation. |
| GATE-01 | Full bats green for the CLI surface; no red / newly-skipped. Cross-cutting. | §Acceptance Oracle — bats file map + staging strategy (replace the `agentlinux` symlink target with the Rust bin). |
| GATE-05 | master shippable; parallel track; per-phase rollback. Cross-cutting. | §Architecture Patterns (parallel-track: the Rust bin is staged only in the test harness; the provisioner still symlinks the TS bundle until Phase 57/58) + §Risks. |
</phase_requirements>

## Summary

Phase 56 is the **I/O + CLI-arg + subprocess layer** wrapped around the already-ported pure core. The heavy lifting of Phase 55 pays off here: `classify`, `decide_version`, `compute_divergence`, `resolve_latest_for`, the three detect gates (`reuse_gate` / `remediate_gate` / `presence_gate`), `derive_category`, `parse_pin_spec`, and `reuse::agent_decision` are **all present in `agentlinux-core`** with byte-for-byte-verified verdicts `[VERIFIED: rust/crates/agentlinux-core/src/{classify,divergence,detect_gates,category,pin_spec,reuse}.rs]`. The six verbs consume these; they do NOT re-derive any decision. What remains to build is: (a) six thin command adapters that read/write files + emit the exact TS stdout strings; (b) the one genuinely-new systems component, the **subprocess dispatcher**; (c) the cache-read adapter deferred from Phase 55; and (d) argument parsing.

**The dispatcher (VERB-02) is the risk center and the only new systems work.** Its complete behavior lives in `plugin/cli/src/state/dispatcher.ts` (171 lines) `[VERIFIED]` and is fully pinned by `plugin/cli/test/dispatcher-stream.test.ts` (six tests) `[VERIFIED]`. The contract: `sudo -u <user> -H -E -- <argv>` with an **invoker==target short-circuit** (run argv directly when `whoami == user`, because `agent→agent` sudo fails with no sudoers entry — dispatcher.ts:70-72); a **buffered path** (exec + capture, non-zero → return the shape never throw) and a **streaming path** (spawn, tee each chunk to this process's stdout/stderr AND accumulate, resolve-never-reject); a **timeout** that fires `SIGTERM` then escalates to `SIGKILL` after a 2000 ms grace (dispatcher.ts:135-141); and an **exit-code mapping** where timeout→124, signal-kill-no-code→1, spawn-ENOENT→1, clean→`code` (dispatcher.ts:164-168). Recommended Rust: **`std::process::Command` + a dedicated timeout/tee approach; use the `nix` crate for the `SIGTERM`-then-`SIGKILL` escalation and `sudo -u`**, since `std::process::Child::kill` only sends SIGKILL and cannot express the graceful-then-forceful escalation the test asserts.

**VERB-03 is nearly trivial and needs no recipe-side manifest file.** The 6 vars are consumed by recipes as **plain `${AGENTLINUX_*}` bash reads** (e.g. `: "${AGENTLINUX_PINNED_VERSION:?...}"` at `plugin/catalog/agents/gsd/install.sh:7`) `[VERIFIED]` — so a Rust dispatcher that sets those 6 names in the child process's environment works identically with **zero recipe changes**. The "single typed Rust source" is a `struct RecipeEnv` (or a const-array of the 6 field names) that the dispatcher populates; there is no file the recipes need to `source`. The recipes read the process environment, which the child inherits.

**Primary recommendation:** Adopt `clap` (derive API) for the verb/flag surface (23 distinct flags across 6 verbs + a program-level `--version`/`--help`, with the tricky `install --version <semver>` shadowing that Commander needed `enablePositionalOptions()` for). Build a `RecipeEnv` typed struct + the buffered/streaming `Dispatcher` on `std::process` + `nix`. Port the cache-read adapter (`detect.ts:116-159`) as `bin/src/cache.rs` feeding the pure gates. Port the 6 command adapters, each emitting the exact TS stdout strings (bats greps them literally). Stage the Rust bin into the container by **overriding the `agentlinux` symlink target** post-install (extend `tests/docker/run.sh`), then run the CLI bats per-file (Docker OOM).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Verb decision logic (classify/divergence/gates/category/pin-spec) | Pure core (`agentlinux-core`) | — | **Already ported (Phase 55).** Verbs consume; never re-derive. |
| Arg parsing (verb + flags) | CLI bin (`agentlinux`) | — | I/O boundary; `clap` in the bin, not the pure crate. |
| Subprocess dispatch (`sudo -u`, tee, timeout, signal escalation) | CLI bin (`bin/src/dispatcher.rs`) | OS (process/signals) | The one new systems component — `std::process` + `nix`. Pure crate stays free of `std::process`. |
| Recipe env-var contract (6 `AGENTLINUX_*`) | CLI bin (typed `RecipeEnv`) | Bash recipes (read plain env) | Rust owns the names (single source); recipes read the inherited process env — no manifest file, no recipe change. |
| Detect-cache read (`/run/agentlinux-detect.json`) | CLI bin adapter (`bin/src/cache.rs`) | — | `std::fs` read → deserialize `DetectedAgent` → feed pure gates. Deferred from Phase 55. |
| Sentinel read/write (`installed.d/<id>.json`) | CLI bin adapter (`bin/src/sentinel.rs`) | — | `std::fs` atomic write (tmp + rename). |
| Catalog load (`catalog.json` + preserve_paths siblings) | CLI bin adapter (`bin/src/catalog.rs`) | — | `std::fs` + `serde_json`; ajv-schema validation is the `validate:true` path. |
| Installed-version probe / npm ls / npm view | CLI bin adapter | Subprocess (npm) / `std::fs` | `probe.ts` = fs read of installed package.json; `npm_ls.ts` = dispatch `npm ls`/`npm view` via the dispatcher. |
| CLI-05 invoker guard | CLI bin (`bin/src/guard.rs`) | OS (geteuid) | `guardAgentUser` — resolve install user, compare to `whoami`, exit 64. |
| Canonical-path map (`CANONICAL_PATHS`, `GSD_SYSTEM_PATH`) | Passed into pure gates as params | Duplicated (TS + bin `main.rs`:19,26-33 + bash) | Stays duplicated until Phase 57. The bin's `main.rs` already carries the Rust twin (`canonical_path()` / `GSD_SYSTEM_PATH`). |

## Standard Stack

Two new bin-only dependencies (`clap`, `nix`). The pure core adds nothing.

### Core (bin `agentlinux` — new deps this phase)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `clap` (derive) | `4.x` (verify at plan time — see §Version Verification) | Verb + flag parsing with subcommands, per-subcommand flags, `--version`/`--help` | The de-facto Rust CLI parser (dtolnay-adjacent ecosystem, used by cargo itself). Derive API mirrors Commander's declarative shape 1:1. `[ASSUMED]` pending §Package Legitimacy Audit. |
| `nix` | `0.29.x` (verify at plan time) | `kill(pid, SIGTERM)` then `SIGKILL`; `sudo -u` is argv (no nix needed for that) — nix is for the **signal escalation** `std::process` cannot express | `std::process::Child::kill()` sends **only SIGKILL** — it cannot do the graceful SIGTERM-then-2000ms-then-SIGKILL escalation `dispatcher-stream.test.ts:117-131` asserts. `nix::sys::signal::kill` is the standard Rust way. `[ASSUMED]` pending audit. |
| `serde` / `serde_json` | `1` (already in core) | (Re)used in the bin to deserialize catalog/sentinel/cache | Already a workspace dep. |
| `agentlinux-core` | path | The ported pure decision core the verbs consume | In-repo. `[VERIFIED: rust/Cargo.toml]` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `clap` derive | Phase-53 plain-argv `match` | **Rejected — see §Arg Parsing.** 23 flags + the `install --version` shadow + `--json`/`--help`/`--version` conventions make hand-rolled arg parsing error-prone. `clap` gives `--help` for free (Commander emitted it; bats may grep usage text). The one caveat: verify no bats asserts an exact Commander-specific usage string; if it does, that string must be replicated (clap's default help differs). |
| `nix` for signals | `std::process::Child::kill` (SIGKILL only) | **Rejected for the streaming path.** The test asserts SIGTERM-first (exit 124 on a `sleep 5` killed at 300 ms) with SIGKILL escalation only after a grace window. `std` cannot send SIGTERM. `nix` (or `libc::kill`) is required. `libc` is a lighter alternative to `nix` — weigh at plan time (fewer transitive deps, but rawer API). |
| A subprocess-timeout crate (`wait-timeout`, `process-control`) | — | `wait-timeout` gives `Child::wait_timeout` cleanly for the **buffered** path; it does NOT tee live output nor do signal escalation, so the **streaming** path still needs manual thread-per-pipe + `nix` kill. Consider `wait-timeout` for the buffered path only; evaluate vs. a hand-rolled `try_wait` loop at plan time. `[ASSUMED]` pending audit. |

**Installation (to add at plan time, after §Package Legitimacy Audit clears):**
```bash
cd rust && cargo add --package agentlinux clap --features derive
cd rust && cargo add --package agentlinux nix --features signal   # or `libc`
```

**Version verification:** Before writing the Standard Stack table into a plan, verify each new crate exists and is current on crates.io:
```bash
cargo search clap        # confirm latest 4.x
cargo search nix         # confirm latest 0.x
cargo search wait-timeout
```
Record the resolved versions + publish dates; training data may be stale.

## Package Legitimacy Audit

> **Required — this phase adds `clap` and `nix` (or `libc`) to the bin.** Run the legitimacy gate before pinning versions in a plan.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| `clap` | crates.io | (verify) | (verify — hundreds of millions) | github.com/clap-rs/clap | (run gate) | Approved pending gate — canonical Rust CLI parser |
| `nix` | crates.io | (verify) | (verify — very high) | github.com/nix-rust/nix | (run gate) | Approved pending gate — canonical *nix syscall bindings |
| `libc` | crates.io | (verify) | (verify — highest) | github.com/rust-lang/libc | (run gate) | Alternative to `nix`; rust-lang-owned |
| `wait-timeout` | crates.io | (verify) | (verify) | github.com/alexcrichton/wait-timeout | (run gate) | Optional — buffered-path timeout only |

**Gate command (run at plan time):**
```bash
gsd-tools query package-legitimacy check --ecosystem crates clap nix libc wait-timeout
```
All four are long-established, high-download, source-backed crates by well-known maintainers (clap-rs org, nix-rust org, rust-lang, alexcrichton). Expect `OK`; still run the gate. Until each is verified via crates.io + the gate, treat the version numbers above as `[ASSUMED]`.

**Packages removed due to [SLOP] verdict:** none anticipated
**Packages flagged as suspicious [SUS]:** none anticipated

## Architecture Patterns

### System Architecture Diagram

```
                          agentlinux <verb> [flags]  (argv)
                                     │
                                     ▼
                         ┌───────────────────────┐
                         │  clap parse (bin)      │  ── unknown verb / bad flag → exit 64
                         └───────────┬───────────┘
                                     ▼
                         ┌───────────────────────┐
                         │  guard::guard_agent    │  ── invoker != install-user → exit 64
                         │  (CLI-05, geteuid)     │
                         └───────────┬───────────┘
                                     ▼
        ┌────────────────────────────┼────────────────────────────────────┐
        ▼            ▼            ▼   ▼    ▼            ▼                    │
     list         install      remove upgrade pin    adopt   (6 verb adapters, bin)
        │            │            │     │      │        │
        │  reads:    │  reads/writes files, calls the PURE gates:          │
        │            │                                                      │
        ▼            ▼                                                      ▼
  ┌──────────────────────────────┐              ┌───────────────────────────────┐
  │ bin ADAPTERS (std::fs / env) │              │ agentlinux-core (PURE, Phase55)│
  │  catalog.rs  loadCatalog     │──CatalogEntry─▶ classify / decide_version     │
  │  sentinel.rs read/write/list │──Sentinel────▶ compute_divergence            │
  │  cache.rs    detect-cache RD │──DetectedAgent▶ resolve_latest_for            │
  │  probe.rs    installed ver   │              │ reuse_gate/remediate_gate      │
  │  guard.rs    invoker check   │              │ presence_gate                  │
  └──────────────┬───────────────┘              │ derive_category / parse_pin    │
                 │ recipe dispatch              │ reuse::agent_decision          │
                 ▼                              └───────────────────────────────┘
  ┌──────────────────────────────────────────────────┐
  │ dispatcher.rs (VERB-02 — the NEW systems piece)   │
  │  build RecipeEnv (6 AGENTLINUX_* + PATH/HOME/…)    │ ── VERB-03 typed source
  │  invoker==target? run argv : sudo -u -H -E -- argv │
  │  buffered: exec+capture, never throw               │
  │  streaming: spawn+tee, timeout→SIGTERM→(2s)→SIGKILL │──▶ bash <recipe>  (~25 recipes, UNCHANGED)
  │  exit map: timeout=124, sig=1, enoent=1, clean=code│      read ${AGENTLINUX_*} from inherited env
  └──────────────────────────────────────────────────┘
```

Data flows: argv → clap → guard → verb adapter. The adapter reads files (catalog/sentinel/cache), feeds the pure core, and — for install/remove/upgrade — dispatches a recipe through `dispatcher.rs`, which sets the 6-var env contract and shells to the unchanged Bash recipe.

### Recommended Project Structure
```
rust/crates/agentlinux/src/
├── main.rs           # clap parse → dispatch to cmd::*; keeps reuse-decision (Phase 53)
├── cli.rs            # clap derive structs (the 6 verbs + flags + program opts)
├── dispatcher.rs     # VERB-02: RecipeEnv + buffered/streaming asUser + timeout/signal
├── recipe_env.rs     # VERB-03: the typed RecipeEnv struct (6 AGENTLINUX_* names, ONE source)
├── guard.rs          # CLI-05 invoker guard
├── catalog.rs        # loadCatalog + preserve_paths hydrate + full CatalogEntry
├── sentinel.rs       # read/write/delete/list sentinels (atomic rename)
├── cache.rs          # detect-cache reader (deferred from Phase 55) → DetectedAgent
├── probe.rs          # probeInstalledVersion (fs read of installed package.json)
├── npm.rs            # queryGlobalNpm / queryNpmViewLatest (dispatch npm)
├── rewire.rs         # reconcileCrossWiring (post-install cross-agent wiring)
└── cmd/
    ├── list.rs  install.rs  remove.rs  upgrade.rs  pin.rs  adopt.rs
```

### Pattern 1: The pure/adapter split (already proven in the bin)
**What:** Every side effect lives in a bin adapter; the decision lives in `agentlinux-core`. Established Phase 53: `cmd_reuse_decision` (main.rs:49) reads env, `reuse::agent_decision` decides.
**When to use:** Every verb. e.g. `list` reads catalog+sentinels+cache (adapters), then calls `classify` + `presence_gate` + `derive_category` (pure) and renders.
**Example:**
```rust
// Source: rust/crates/agentlinux/src/main.rs:49-68 (existing pattern)
let status = std::env::var(...).unwrap_or_else(|_| "absent".into());   // adapter (I/O)
let decision = agentlinux_core::reuse::agent_decision(id, &status, ...); // pure
print!("{}", decision.as_str());                                        // adapter (I/O)
```

### Pattern 2: Exact-string stdout (bats greps literals)
**What:** Every human-facing line in the TS commands is a load-bearing literal string the bats assert with `grep -qF`. Port them character-for-character.
**When to use:** All six verbs. Examples that MUST match byte-for-byte:
- list suffixes: `" (reused — managed by agentlinux upgrade/remove)"`, `" (detected — run: agentlinux adopt <id> to manage)"` (list.ts:126-140) — the em-dash `—` is literal.
- install: `"[REUSE-03] <id> reused: binary=… version=… (in window …) status=healthy"` (install.ts:127); `"<id>: installed <ver> (<source>)"` (install.ts:311); `"<id>: already installed at <ver> (<source>); no-op"` (install.ts:270).
- remove: `"<id>: removed"` (remove.ts:74); the `"▸ removing <id>…"` streaming prefix (remove.ts:54).
- pin: `"<id>: pinned to <ver> (sticky=true)"` (pin.ts:163); `"<id>: pin cleared (source=curated, sticky=false)"` (pin.ts:147).
- adopt: `"[ADOPT] <id>: adopted pre-existing install <ver> (status=reused — managed by agentlinux upgrade/remove)"` (adopt.ts:120).
- upgrade table header: `["ID","STATUS","SENTINEL","INSTALLED","CURATED","LATEST","SRC"]` padded (upgrade.ts:104).
- list table header: `["NAME","STATUS","CURATED","INSTALLED"(,"DESCRIPTION")]` padded, `.trimEnd()` on each row (list.ts:141-177).

### Pattern 3: Column-padding renderer parity
**What:** Both `list` and `upgrade` render fixed-width columns: compute each column width = `max(len over header+rows)`, pad each cell with `padEnd`, join with **two spaces**, and (list only) `trimEnd()` each line. Port this exactly — off-by-one padding fails a `grep` on aligned output.
**Source:** list.ts:166-177, upgrade.ts:114-118.

### Anti-Patterns to Avoid
- **Re-deriving decisions in the verb.** The gates are ported — call them. Re-implementing `tryReuse`'s 5 gates in `install.rs` would drift from the golden-tested core.
- **Using `std::process::Child::kill()` for timeout.** It's SIGKILL-only; the test asserts SIGTERM-first. Use `nix::kill`.
- **Buffered path that throws on non-zero exit.** The TS contract is "return the shape, never throw" (dispatcher.ts:89-107). A verb decides whether a non-zero exit is fatal (install → yes; npm ls → no). The dispatcher must NOT propagate errors as panics/`Result::Err` for the non-zero-exit case.
- **Adding a manifest file for recipes to `source`.** Unnecessary — recipes read `${AGENTLINUX_*}` from the inherited process env. A file would be a new, un-tested surface.
- **Symlinking the Rust bin at `/usr/local/bin`.** The self-update anti-pattern (CLAUDE.md). Stage at an agent-owned path and override the `~/.npm-global/bin/agentlinux` symlink target.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Verb/flag parsing | A bespoke argv state machine | `clap` derive | 23 flags, per-verb scoping, `--version` shadow, help text — all solved + tested upstream. |
| Send SIGTERM to a child | Poking `/proc` or raw syscalls | `nix::sys::signal::kill` (or `libc::kill`) | Portable, safe wrapper; `std` only offers SIGKILL. |
| Live tee of child stdout+stderr while capturing | Ad-hoc select loop with subtle deadlocks | Thread-per-pipe (stdout thread + stderr thread) reading to `String` while writing through to the parent's streams | Classic pipe-buffer-deadlock trap if you read only one pipe; two reader threads is the standard fix. |
| Atomic sentinel write | `write()` in place | tmp file + `std::fs::rename` (same dir) | POSIX rename(2) atomicity — mirrors sentinel.ts:47-48. |
| semver valid / satisfies / eq / gt / maxSatisfying | Calling `semver::` directly | `agentlinux_core::semver_shim::{valid,satisfies,eq,gt,max_satisfying}` | The shim isolates the node-semver divergences (TEST-04). Direct calls reintroduce the exact bug. `[VERIFIED: semver_shim.rs:104-160]` |

**Key insight:** The decision surface is entirely ported. The remaining work is faithful I/O plumbing + one subprocess dispatcher — exactly the domains where hand-rolling introduces the process/signal/deadlock bugs `nix` + a thread-per-pipe pattern eliminate.

---

## The Six Verbs (VERB-01)

For each: TS source, stdout contract, exit codes, flags/args, core functions consumed, and the I/O adapters it needs. Line numbers cite `plugin/cli/src/`.

### `list` (list.ts, 227 LOC) — CLI-02, ENABLE-06, AL-61/62
- **Flags:** `--include-test`, `--by-category`, `--descriptions`, `--json` (index.ts:41-44). No positional arg.
- **Consumes (pure):** `derive_category` (list.ts:96), `classify` (list.ts:75), `presence_gate` (via `detectPresence`, list.ts:85).
- **Adapters needed:** `loadCatalog({validate:false})` (hot path — no ajv), `listSentinels`, `probeInstalledVersion` (probe.ts — fs read of installed package.json for npm entries), `detectCachePath`+`readCachedAgentById` (cache adapter for presence overlay).
- **stdout:** the padded NAME/STATUS/CURATED/INSTALLED table (+ DESCRIPTION with `--descriptions`); INSTALLED-column suffixes are load-bearing literals (list.ts:126-140). `--by-category` prefixes `## <label>` group headers in canonical order; flat default is unchanged. `--json` → `JSON.stringify(rows, null, 2)` — the Row shape (list.ts:25-64) must serialize field-identically.
- **Exit:** always 0 (a read-only report). No `process.exit` in list.ts.
- **Gap vs core:** the `Row` JSON shape has ~20 fields; needs a bin-side `Row` struct with serde field names matching TS exactly (`sentinel_version`, `present_canonical`, `category_label`, etc.).

### `install <name>` (install.ts, 318 LOC) — CLI-03, REUSE-03, REMEDIATE-04, UX-01
- **Args/flags:** `<name>` (required); `--force`, `--version <semver>`, `--include-test`, `--yes`, `--dry-run` (index.ts:50-62).
- **Consumes (pure):** `reuse_gate` (tryReuse), `remediate_gate` (tryRemediate), `decide_version` (install.ts:266), `semver_shim::valid` (install.ts:68 — `--version` validation), `semver_shim::eq` (install.ts:269 — idempotent short-circuit), `semver_shim::satisfies` (install.ts:149 — migration window check).
- **Adapters needed:** loadCatalog(validate:true), readSentinel/writeSentinel, cache adapter (tryReuse/tryRemediate read `/run/agentlinux-detect.json` + a host `statSync` re-validation — that stat stays in the adapter, NOT the pure gate), `existsSync` (post-uninstall verification, install.ts:200), `dispatchRecipe` (the dispatcher), `reconcileCrossWiring` (rewire.rs).
- **Exit codes (all load-bearing):** `64` EX_USAGE — `--dry-run + --yes` (install.ts:46), unknown agent (install.ts:59), test-only without `--include-test` (install.ts:65), bad `--version` semver (install.ts:70). `65` EX_DATAERR — REMEDIATE-04 bail in non-TTY without `--yes` (install.ts:170). `1` — uninstall/install recipe failure or post-uninstall binary still present (install.ts:194,204,239); recipe exit propagated as `result.exitCode` on the normal path (install.ts:297).
- **stdout literals:** `[DRY-RUN] …` (install.ts:103), `[REUSE-03] …` (install.ts:127), `[REMEDIATE-04] …`/`[REMEDIATE-04:*]` family (install.ts:174,191,201,236,257), `▸ installing <id> <ver>…` (install.ts:282), `<id>: installed <ver> (<source>)` (install.ts:311), `<id>: already installed at … no-op` (install.ts:270). The REMEDIATE bail block writes to **stderr** (install.ts:161-169). `--dry-run --json` emits a `summary` object (install.ts:92-99).
- **TTY dependency:** `process.stdin.isTTY` (install.ts:159) gates the `--yes` requirement. In Rust: `std::io::stdin().is_terminal()` (std, stable) or the `is-terminal` crate.

### `remove <name>` (remove.ts, 75 LOC) — CLI-04
- **Args/flags:** `<name>` (required); `--force` (index.ts:83).
- **Consumes (pure):** none directly (pure decision-free; it's an orchestration verb).
- **Adapters:** loadCatalog(validate:true), readSentinel/deleteSentinel, `existsSync` (reused-binary-vanished branch, remove.ts:43), dispatchRecipe(uninstall.sh, **stream:true**).
- **Exit:** `64` unknown agent (remove.ts:28); `1` not-installed without `--force` (remove.ts:35) OR uninstall recipe failure (remove.ts:69, propagated). `--force` + not-installed → exit 0 no-op (remove.ts:37).
- **stdout literals:** `▸ removing <id>…` (remove.ts:54), `<id>: removed` (remove.ts:74), the reused-binary-gone sentence (remove.ts:45), `<id>: uninstall.sh failed (exit N)` → stderr (remove.ts:67).

### `upgrade` (upgrade.ts, 262 LOC) — CLI-06, ADR-011
- **Flags:** `--reset-all-curated`, `--respect-overrides`, `--all-latest`, `--check-upstream`, `--json` (index.ts:91-95). No positional arg.
- **Consumes (pure):** `compute_divergence` (upgrade.ts:160), `presence_gate` (presence overlay, upgrade.ts:163), `resolve_latest_for` (via queryNpmViewLatest → npm.rs).
- **Adapters:** loadCatalog(validate:true), listSentinels/readSentinel/writeSentinel, `queryGlobalNpm` (dispatch `npm ls -g --json`), `queryNpmViewLatest` (dispatch `npm view … versions --json`; opt-in only), cache adapter (presence), `statSync` (validateReusedBinary, upgrade.ts:40), dispatchRecipe(install.sh). **`shouldReinstall` flag-priority logic (upgrade.ts:76-101) is pure and small — port it into the bin (or a core helper).**
- **Exit:** default report-only exits 0. Reconcile loop `continue`s on per-entry failures (upgrade.ts:239) — never aborts; overall exit 0 unless a top-level error. Per-entry recipe failure → stderr note, sentinel preserved.
- **stdout:** the padded 7-column table (or `--json` array of `DivergenceReport`), then reconcile-loop lines (`<id>: reinstalling at <ver> (<source>)`, upgrade.ts:229). The `DivergenceReport` JSON shape is **already the core's `DivergenceReport`** (serde field renames match — `sentinelVersion`, etc.) `[VERIFIED: types.rs:125-139]`.

### `pin <spec>` (pin.ts, 168 LOC) — CLI-07, ADR-011
- **Args:** `<spec>` = `<name>=curated|latest|<semver>` (index.ts:101). No flags (a `--json` PinOpts exists but no flag registered).
- **Consumes (pure):** `parse_pin_spec` (pin.ts:52 — **already ported to `pin_spec::parse_pin_spec`** `[VERIFIED: pin_spec.rs:87]`), `presence_gate` (the not-installed hint routing, pin.ts:117).
- **Adapters:** loadCatalog(validate:true), readSentinel/writeSentinel, cache adapter (present-hint).
- **Exit:** `64` malformed spec or unknown agent (pin.ts:83,99); `1` not-installed (pin.ts:135). State-only mutation — never dispatches a recipe.
- **stdout literals:** `<id>: pinned to <ver> (sticky=true)` (pin.ts:163), `<id>: pinned to follow upstream latest …` (pin.ts:153), `<id>: pin cleared (source=curated, sticky=false)` (pin.ts:147). The not-installed present-hint sentences (pin.ts:119-133) → stderr.
- **Note:** the TS `PinTarget` union maps to the core's `ParsedPin`/`PinTarget` (pin_spec.rs:36-49). The error MESSAGES the TS throws (pin.ts:57-73) are ported into `PinSpecError` (pin_spec.rs:58) — confirm the message strings match the TS `throw new Error(...)` text byte-for-byte, since pin.ts:82 prints `err.message` to stderr and bats may grep it.

### `adopt [name]` (adopt.ts, 130 LOC) — AL-61, AL-62
- **Args/flags:** `[name]` (optional); `--all`, `--include-test`, `--json` (index.ts:71-75).
- **Consumes (pure):** `reuse_gate` (tryReuse, adopt.ts:41), `remediate_gate` (tryRemediate — migration-candidate detection, adopt.ts:47).
- **Adapters:** loadCatalog(validate:false — hot path), readSentinel/writeSentinel, cache adapter. Never dispatches a recipe, never downloads.
- **Exit:** `64` no name and no `--all` (adopt.ts:103), unknown agent (adopt.ts:93), test-only without `--include-test` (adopt.ts:97). Otherwise 0.
- **stdout literals:** `[ADOPT] <id>: adopted … (status=reused — managed by agentlinux upgrade/remove)` (adopt.ts:120), `<id>: already managed at <ver>; no-op` (adopt.ts:123), `[MIGRATE] <id>: …` (adopt.ts:125), `<id>: nothing to adopt — <reason>` (adopt.ts:127). `--json` → array of `AdoptResult`.

### What is NOT yet in `agentlinux-core` that a verb needs
Nothing in the **decision** layer — all gates/classify/divergence/category/pin-spec/semver are ported `[VERIFIED]`. The gaps are all **adapter/shape** work for the bin:
1. **A full `CatalogEntry`** — the core's `CatalogEntry` (types.rs:16-42) is a lean 7-field subset. The bin needs the full shape (`display_name`, `description`, `install_recipe_path`, `uninstall_recipe_path`, `rewire_recipe_path`, `preserve_paths`, `test_only`, `homepage`, …) to load the catalog + build recipe paths. Recommendation: a bin-side `FullCatalogEntry` (or extend the core struct with more `#[serde(default)]` optional fields — but keep the core lean per its Phase-55 contract; a bin-local struct is cleaner). The `schema_gen.rs::SchemaCatalogEntry` (schema_gen.rs:57) already enumerates the full field set for reference.
2. **The full `Sentinel`** — core's is 4 fields (types.rs:88-93); the bin needs the write-path fields (`installed_at`, `status`, `binary_path`, `detected_source`, `reused_at`, `remediated_at`, `decline_reason`, …) to write sentinels (install/adopt/upgrade/pin all write). See types.ts:57-89 for the full shape.
3. **The `Row` (list) and `AdoptResult` / dry-run `summary` JSON shapes** — bin-side serde structs matching the TS `JSON.stringify` output field-for-field.
4. **`shouldReinstall` flag-priority** (upgrade.ts:76-101) — small pure logic; port into the bin or a core helper.

---

## VERB-02 — the Dispatcher (the one new systems component)

### TS source map
**Two files:**
- `plugin/cli/src/runner.ts` (121 LOC) — `dispatchRecipe`: builds the env + argv, resolves the install user, delegates to `asUser`. **This is the VERB-03 env-var assembly (§below).**
- `plugin/cli/src/state/dispatcher.ts` (171 LOC) — `asUser`: the actual spawn. **This is VERB-02.** `[VERIFIED]`

### `asUser` behavior — port faithfully (dispatcher.ts:60-171)
1. **invoker==target short-circuit (dispatcher.ts:70-72):** `invoker = whoami`. If `invoker == user`, run `argv` **directly**; else prepend `["sudo","-u",user,"-H","-E","--"]`. Rationale (dispatcher.ts:14-27): `agent→agent` sudo fails (no sudoers entry; CONTEXT locks zero sudoers). The `-H -E --` flags are byte-for-byte the bash `as_user.sh` keystone. In Rust: `nix::unistd::User::from_uid(getuid())` or read `$USER`/`getpwuid` to get the invoker name.
2. **Buffered path (dispatcher.ts:81-107):** exec, capture stdout/stderr (10 MiB max buffer). On non-zero exit → **return `{exitCode, stdout, stderr}`, never throw.** ENOENT/spawn failure → exitCode 1. In Rust: `Command::output()` + map.
3. **Streaming path (`spawnTee`, dispatcher.ts:116-170):** spawn with piped stdout/stderr, `stdio: ["ignore","pipe","pipe"]` (**stdin ignored**). For each chunk: append to the capture string AND `process.stdout/stderr.write(chunk)` (live tee). On `error` (spawn failure) → resolve `{exitCode:1, stderr: stderr+err.message, streamed:true}`. On `close(code, signal)` → `exitCode = timedOut ? 124 : (code ?? (signal ? 1 : 0))`, `streamed:true`.
4. **Timeout + signal escalation (dispatcher.ts:135-141):** if `timeout > 0`, set a timer; on fire, set `timedOut=true`, `child.kill("SIGTERM")`, then a **second timer at 2000 ms** → `child.kill("SIGKILL")`. Clear both timers on close/error. This is the crux `std::process` cannot express.
5. **`streamed` flag:** true only on the streaming path; callers use it to skip re-printing captured stdout (already on screen). Buffered leaves it unset.

### The parity spec: `dispatcher-stream.test.ts` (6 tests) `[VERIFIED]`
These pin VERB-02 exactly — the Rust port must reproduce every one:
| Test (dispatcher-stream.test.ts) | Asserts |
|---|---|
| `:44` stream tees + captures | exit 0, `streamed==true`, stdout has `out-line`, stderr has `err-line`, AND both teed to the console |
| `:64` non-zero exit no throw | `bash -c "echo hi; exit 7"` → exitCode 7, streamed true, stdout has `hi` |
| `:77` buffered still captures | no stream → captures, `streamed` unset |
| `:84` sudo branch on invoker!=target | unknown user → non-zero exit, streamed true, returned shape (no throw) |
| `:104` ENOENT → exitCode 1 | `/no/such/binary` → exitCode 1, streamed true |
| `:117` timeout → SIGTERM → 124 | `bash -c "sleep 5"` with `timeout:300` → **exitCode 124**, streamed true |

There is also `runner.test.ts` (§VERB-03) pinning the env/PATH/user assembly. Together these two unit-test files are the **parity reference** the Rust dispatcher must satisfy (plus the bats that exercise real installs).

### Recommended Rust implementation
- **Buffered path:** `std::process::Command::output()`; on non-zero, return the shape. For an optional buffered timeout, evaluate `wait-timeout`'s `Child::wait_timeout` (else a `try_wait` poll loop).
- **Streaming path:** `Command::stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn()`. Spawn **two reader threads** (one per pipe) that read chunks, write through to the parent's stdout/stderr, and accumulate into a shared `String` (channel or `Arc<Mutex<String>>`). Main thread runs the timeout: `try_wait` poll loop, OR spawn a watchdog thread. On timeout: `nix::sys::signal::kill(Pid::from_raw(child.id() as i32), Signal::SIGTERM)`, sleep 2000 ms (or wait-with-deadline), then `SIGKILL` if still alive. Join reader threads, map exit: timed-out → 124; `ExitStatus::code()` → that; killed-by-signal-no-code → 1.
- **Signal crate:** `nix` (ergonomic) or `libc::kill` (lighter). Recommend `nix` for readability; note `libc` as the lower-dep alternative.
- **`sudo -u` argv:** plain `Command::new("sudo").args(["-u", user, "-H", "-E", "--"]).args(argv)` — no crate needed. Set `.env_clear().envs(recipe_env)` to mirror the TS explicit-env contract (TS passes `env: opts.env` which **replaces**, not extends, the environment; confirm with `env_clear()` + explicit sets, since `sudo -E` alone drops PATH to secure_path — Pitfall 5, runner.ts:11).

### VERB-02 caveats to pin at plan time
- **Exit-code mapping is exact** — 124/1/0/code. A mismatch fails the timeout/ENOENT tests.
- **The 2000 ms SIGKILL grace** is a literal in the TS (dispatcher.ts:139). Reproduce it; the `sleep 5` + `timeout:300` test would pass with any grace, but the value is contract.
- **Two-pipe deadlock:** read stdout AND stderr concurrently (thread-per-pipe), never sequentially, or a chatty recipe filling the stderr pipe buffer while you block reading stdout will hang.

---

## VERB-03 — the Env-Var Contract

### The 6 names + source (runner.ts:45-56, 106-118) `[VERIFIED]`
| Var | Value source (TS) |
|-----|-------------------|
| `AGENTLINUX_PINNED_VERSION` | `args.version` (decideVersion().version) |
| `AGENTLINUX_CATALOG_DIR` | `args.catalogDir` |
| `AGENTLINUX_AGENT_HOME` | `/home/<install-user>` |
| `AGENTLINUX_SOURCE_KIND` | `args.entry.source_kind` |
| `AGENTLINUX_INSTALL_LOG` | `/var/log/agentlinux-install.log` (constant) |
| `AGENTLINUX_PRESERVE_PATHS` | `(entry.preserve_paths ?? []).join(":")` (colon-separated; empty string when none) |

Plus non-`AGENTLINUX_*` env the recipes rely on (runner.ts:112-116): `PATH` (the canonical `/etc/agentlinux.env` literal), `HOME`, `NPM_CONFIG_PREFIX`, `LANG=C.UTF-8`, `LC_ALL=C.UTF-8`, and `...extraEnv`.

### How recipes consume them — plain env reads, NO manifest file `[VERIFIED]`
Recipes read the vars directly from the process environment, e.g.:
```bash
# plugin/catalog/agents/gsd/install.sh:7-8
: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
```
Grep counts across `plugin/catalog/` (recipe files referencing each var) `[VERIFIED]`:
`AGENT_HOME` 51, `CATALOG_DIR` 33, `PINNED_VERSION` 21, `PRESERVE_PATHS` 10, `SOURCE_KIND` 1, `INSTALL_LOG` 0. (Shared recipe libs under `plugin/catalog/lib/` account for much of the fan-out.)

**Implication:** A Rust dispatcher that sets these 6 names in the child process's environment (via `Command::envs`) satisfies every recipe **with zero recipe changes**. The child inherits the parent-set env; the recipes' `${AGENTLINUX_*}` reads resolve identically to today.

### Recommendation — the single typed Rust source
Define ONE typed source of the 6 names in the bin (`recipe_env.rs`):
```rust
// recipe_env.rs — the ONE place the 6 names live.
pub struct RecipeEnv {
    pub pinned_version: String,
    pub catalog_dir: String,
    pub agent_home: String,
    pub source_kind: String,
    pub install_log: String,
    pub preserve_paths: String, // colon-joined
}
impl RecipeEnv {
    // The dispatcher calls this to build the child env. The KEY STRINGS
    // ("AGENTLINUX_PINNED_VERSION", …) exist in exactly one place.
    pub fn into_env_pairs(self) -> [(String, String); 6] { … }
}
```
The dispatcher populates the child env from this struct. Because the key strings are defined once and both the assembly (dispatcher) and the field mapping live in this one struct, **a rename is a compile error, not a silent desync** — satisfying VERB-03's "a rename cannot silently desync CLI and recipes." No file for recipes to `source` is needed (the recipes read the inherited env). The recipes themselves are the untyped boundary that survives the rewrite (CONTEXT §irreducible boundary); VERB-03 is satisfied by centralizing the *names* on the Rust side.

### Parity spec: `runner.test.ts` `[VERIFIED]`
Pins the exact assembly: `AGENTLINUX_PINNED_VERSION/CATALOG_DIR/SOURCE_KIND/AGENT_HOME/INSTALL_LOG` (runner.test.ts:66-70), the canonical PATH literal (runner.test.ts:80-88), `extraEnv` append+override (runner.test.ts:91-107), the `stream` flag threading (runner.test.ts:118-139), and the configured-install-user derivation (runner.test.ts:158-196: `AGENTLINUX_USER=claude` → dispatch as claude with `/home/claude` env; malformed → fall back to `agent`). The install-user resolution (`resolveInstallUser`, runner.ts:30-43: `$AGENTLINUX_USER` > `/etc/agentlinux.env` `AGENTLINUX_USER=` line > `agent`, POSIX charset `^[a-z][a-z0-9_-]*$` validated) must port to `guard.rs`/`recipe_env.rs`.

---

## Cache-Read Adapter (deferred from Phase 55)

**TS source:** `detect.ts:116-159` `[VERIFIED]`. Four functions, all `std::fs`:
- `detectCachePath()` (detect.ts:116) → `$AGENTLINUX_DETECT_CACHE` or `/run/agentlinux-detect.json`.
- `readCacheAgents()` (detect.ts:129) → `existsSync` guard, `readFileSync` + `JSON.parse`, accept **both** shapes: top-level `.agents` (from `detect::run_once`) OR `.components.agents` (from `--report-only`). Returns `null` on absent/unparseable.
- `readCachedAgentById(id)` (detect.ts:144) → find by id, no canonical requirement (list presence overlay).
- `readDetectedAgent(entry)` (detect.ts:151) → canonical-gated: `CANONICAL_PATHS[id]` must exist; returns `{detected, canonical}` for reuse/remediate.

**Rust landing:** `bin/src/cache.rs`. Reads the file, deserializes into `Vec<agentlinux_core::types::DetectedAgent>` (the core already has the 4-field `DetectedAgent` struct, types.rs:50 `[VERIFIED]`), and exposes `read_cached_agent_by_id` + `read_detected_agent`. **The pure gates are already there** — `reuse_gate` / `remediate_gate` / `presence_gate` (detect_gates.rs) take a `&DetectedAgent` + `canonical: Option<&str>` + `gsd_system_path` + `agent_home` `[VERIFIED: detect_gates.rs:134,216,269]`. So `cache.rs` reads, then hands the record to the pure gate.

**The `statSync` re-validation stays in the adapter:** `tryReuse` does a host `statSync(detected.path)` (detect.ts:183-188) AFTER the pure gate passes, to confirm the binary still exists. That stat is I/O — it lives in the install verb's adapter (call `reuse_gate`, then if `Some`, `std::fs::metadata(path).is_file()` before committing). The pure `reuse_gate` correctly OMITS this stat (documented at detect_gates.rs:124).

**Test seam:** the `AGENTLINUX_DETECT_CACHE` env override (detect.ts:117) is used heavily by bats (e.g. 40-registry-cli.bats:183 `AGENTLINUX_DETECT_CACHE=${cache} agentlinux list`) — `cache.rs` MUST honor it.

---

## Arg Parsing — clap vs. plain-argv

### The real surface (counted)
6 subcommands + a program-level `-V/--version` and implicit `--help`. Flags per verb (index.ts):
- `list`: 4 flags (`--include-test`, `--by-category`, `--descriptions`, `--json`)
- `install <name>`: 5 flags (`--force`, `--version <semver>`, `--include-test`, `--yes`, `--dry-run`) + 1 positional
- `adopt [name]`: 3 flags (`--all`, `--include-test`, `--json`) + 1 optional positional
- `remove <name>`: 1 flag (`--force`) + 1 positional
- `upgrade`: 5 flags (`--reset-all-curated`, `--respect-overrides`, `--all-latest`, `--check-upstream`, `--json`)
- `pin <spec>`: 0 flags + 1 positional
**Total: 23 flags, 4 positionals, 6 subcommands.** Plus Commander's `enablePositionalOptions()` (index.ts:31) so `install --version <semver>` shadows the program-level `-V/--version` (index.ts:27-30).

### Recommendation: **`clap` (derive API)**
- The surface is well past the "plain-argv match" comfort zone (Phase-53's bin had ONE subcommand + one arg). 23 flags with per-verb scoping, a value-taking `--version <semver>` that must not collide with `-V`, `--json` conventions, and free `--help` all argue for a real parser.
- `clap` derive mirrors Commander's declarative shape 1:1 — each verb is a struct variant, each flag a field. Low porting friction.
- **The one caveat** to verify at plan time: does any bats assert an **exact Commander-generated usage/help string**? clap's default `--help` output differs from Commander's. Grep `tests/bats/40-registry-cli.bats` (and 23/50/10) for `Usage:`/`Options:`/help-text asserts. `CLI-01: agentlinux --version` (40-registry-cli.bats:97) asserts the version number, not help text — that's fine (clap `.version()`), but confirm there's no `--help` body assertion. If one exists, replicate that string (clap allows custom help templates) or keep a hand-written help for that verb.
- **`install --version` shadow:** clap handles this natively — a subcommand-level `--version <String>` arg coexists with a global `--version` flag when the global is only defined at the top level. Verify the exact clap config (may need `#[command(disable_version_flag)]` on the subcommand or a global `-V`-only version flag) so `agentlinux install foo --version 2.1.7` parses `2.1.7` as the arg, and `agentlinux --version` prints the CLI version. This is the direct analog of Commander's `enablePositionalOptions()`.

**Rejected:** the plain-argv `match`. It would work but re-implements flag parsing, value-taking options, and `--help` — exactly what `clap` tests upstream. Only choose it if the audit finds `clap` unacceptable for some reason (not anticipated).

---

## Acceptance Oracle (GATE-01)

### bats files covering this surface `[VERIFIED: ls tests/bats]`
| File | Covers | Needs Rust bin staged? |
|------|--------|------------------------|
| `40-registry-cli.bats` (34.6K) | CLI-01..07, CAT-01..04, INST-04, AL-61 (list/install/remove/upgrade/pin/adopt happy + error paths, `--json`, `--include-test`, presence overlay, `--purge`) | **YES** — every `agentlinux <verb>` call. |
| `50-agents.bats` (18.8K) | AGT-01..05 — real `agentlinux install claude-code/gsd/playwright-cli` + version stamping + skill wiring | **YES** — but these do **real network installs**; gated by systemd/network availability (`skip` guards, 50-agents.bats:114). Run in the full harness, not the quick loop. |
| `23-install-user.bats` (15.2K) | INST-07 — `--user=NAME`/`AGENTLINUX_USER` provisioning + `sudo -u <user> agentlinux list` guard | **YES** — exercises `resolveInstallUser` + guard on a non-`agent` user. |
| `10-installer.bats` (12.3K) | Installer end-to-end (provisions, then CLI available) | Partially — CLI-adjacent; verify which @tests call `agentlinux`. |

Also relevant (detect/reuse/remediate paths the cache adapter + gates feed): `13-reuse.bats`, `14-remediate.bats`, `15-detection.bats`, `15-preflight-ux.bats` — these already went green on the Rust `reuse-decision` path in Phase 53; the cache adapter + gates in this phase must keep them green.

### TS command unit tests — the parity reference `[VERIFIED: plugin/cli/test/]`
`install.test.ts`, `list.test.ts` (+ `list-drift`, `list-presence`, `list-presence-catalog`), `remove.test.ts`, `upgrade.test.ts`, `pin.test.ts`, `adopt.test.ts`, `runner.test.ts`, `dispatcher-stream.test.ts`, `sentinel.test.ts`, `loader.test.ts`, `probe.test.ts`, `npm_ls.test.ts`, `rewire.test.ts`, `guard-user.test.ts`. Each verb's `.test.ts` enumerates its stdout strings + exit codes + branch conditions — the fastest way to enumerate the parity cases per verb before writing the Rust adapter.

### Staging strategy — the key GATE-01 mechanic
The provisioner symlinks `~agent/.npm-global/bin/agentlinux → <stage>/dist/index.js` (the **TS bundle**) at `plugin/provisioner/50-registry-cli.sh:124` `[VERIFIED]`. bats invokes `agentlinux <verb>` which resolves that symlink. **Phase 53's `run.sh` staged the Rust bin at `~agent/.local/bin/agentlinux` and only wired `AGENTLINUX_RUST_BIN` for the reuse-shim** (run.sh:220-253) — it did NOT replace the `agentlinux` command itself. For Phase 56, the CLI bats must hit the **Rust** bin:
- **Recommended:** extend `tests/docker/run.sh` to **re-point the `agentlinux` symlink** at the staged Rust musl bin AFTER the installer runs (`ln -sfn <rust-bin> ~agent/.npm-global/bin/agentlinux`), gated behind a flag/env so master's TS path is unaffected (GATE-05 parallel-track). This is a test-harness override, NOT a provisioner change (the provisioner keeps symlinking the TS bundle until Phase 58 makes the tarball the channel).
- **Docker OOM (memory):** the full suite OOMs ~test 131 in this VM (MEMORY). Run **targeted per-file** container runs for the CLI files (`bats tests/bats/40-registry-cli.bats`, etc.), mirroring Phase 53's pattern. The `tests/docker/run.sh` already bind-mounts the source + stages the bin; parameterize it to run a single file.
- **Exit 127 risk:** if the Rust bin fails to build/stage, `agentlinux` resolves to a dangling symlink → exit 127. The Phase-53 fallback (TS bundle) avoids this on master; the Phase-56 harness must fail loudly if the Rust bin is expected but absent (don't silently fall back to TS and report false-green).

---

## Runtime State Inventory

> This is a like-for-like port, not a rename — but it touches how a running system's CLI is wired. Explicit inventory:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | Sentinels at `/opt/agentlinux/state/installed.d/<id>.json`; detect cache at `/run/agentlinux-detect.json`. The Rust CLI reads/writes the SAME files in the SAME JSON shapes — no migration. | Code: match sentinel/cache JSON field names byte-for-byte (serde renames). No data migration. |
| Live service config | The `agentlinux` command is a **symlink** (`~agent/.npm-global/bin/agentlinux`) installed by the provisioner (50-registry-cli.sh:124) pointing at the TS `dist/index.js`. | Test harness: override the symlink target to the Rust bin (§Staging). Provisioner symlink change is **Phase 57/58**, NOT this phase (GATE-05 parallel-track). |
| OS-registered state | `/etc/agentlinux.env` carries `AGENTLINUX_USER=` (read by `resolveInstallUser`) and the canonical PATH literal. | None — the Rust CLI reads the same file; no rewrite. |
| Secrets/env vars | `AGENTLINUX_USER`, `AGENTLINUX_DETECT_CACHE`, `AGENTLINUX_STATE_DIR`, `AGENTLINUX_CATALOG_DIR`, `NPM_CONFIG_PREFIX`, `AGENTLINUX_AGENT_HOME` — all test/prod seams the TS honors. | Code: the Rust adapters MUST honor every one of these env overrides (bats depend on them). None renamed. |
| Build artifacts | TS `dist/` bundle (staged by provisioner); Rust musl bin (staged by run.sh). Both coexist on the parallel track. | None — additive. The TS bundle stays authoritative on master until Phase 58. |

**Nothing renamed this phase.** The env-var NAMES (VERB-03) are preserved exactly; VERB-03 is about centralizing them in Rust, not renaming them.

## Common Pitfalls

### Pitfall 1: `std::process::Child::kill()` is SIGKILL-only
**What goes wrong:** Using `child.kill()` for the timeout sends SIGKILL immediately; the `dispatcher-stream.test.ts:117` timeout test expects SIGTERM-first (graceful), SIGKILL only after 2000 ms. A recipe with a SIGTERM trap (cleanup) would be denied its grace.
**Avoid:** `nix::sys::signal::kill(pid, SIGTERM)` → wait 2000 ms → `SIGKILL`. Map timed-out → exit 124.
**Warning sign:** the timeout test passes but real recipes lose cleanup; or exit code isn't 124.

### Pitfall 2: Two-pipe deadlock in the streaming tee
**What goes wrong:** Reading stdout to EOF before reading stderr; a recipe that fills the 64 KiB stderr pipe buffer blocks on write while you block reading stdout → hang.
**Avoid:** thread-per-pipe — read stdout and stderr concurrently. Mirrors Node's independent `child.stdout.on('data')` + `child.stderr.on('data')`.

### Pitfall 3: `sudo -E` drops PATH to secure_path
**What goes wrong:** Relying on `sudo -E` to preserve PATH; Ubuntu's `secure_path` overrides it, so `npm` resolves from `/usr/bin` not `~agent/.npm-global/bin` → EACCES (the bug AgentLinux exists to kill). runner.ts:11, Pitfall 5.
**Avoid:** set PATH **explicitly** in the child env to the canonical literal (`env_clear()` + explicit `.env("PATH", …)`), exactly as `dispatchRecipe` does (runner.ts:104,112).
**Warning sign:** recipes fail with EACCES or "npm: command not found" under `sudo -u`.

### Pitfall 4: em-dash and Unicode in stdout literals
**What goes wrong:** The list/install/adopt suffixes use `—` (em-dash, U+2014) and `▸` (U+25B8) — bats greps them with `grep -qF`. A Rust string with a hyphen `-` instead of `—` silently fails the grep.
**Avoid:** copy the literals byte-for-byte from the TS source; add a Rust `#[test]` asserting the exact bytes.

### Pitfall 5: Buffered dispatcher throwing on non-zero exit
**What goes wrong:** Idiomatic Rust returns `Result::Err` on a failed command; but the TS contract is "return the shape, never throw" (dispatcher.ts:89) because callers decide fatality (`npm ls` exits 1 on peer-dep warnings but its JSON is still valid — npm_ls.ts:16-19). A Rust dispatcher that errors on exit≠0 breaks `queryGlobalNpm`.
**Avoid:** the dispatcher returns `DispatchResult { exit_code, stdout, stderr }` for ALL exits; only genuine spawn failures map to exit_code 1.

## Code Examples

### Buffered dispatch (mirrors dispatcher.ts:81-107)
```rust
// bin/src/dispatcher.rs — never throw on non-zero exit
let out = std::process::Command::new(cmd)
    .args(&rest)
    .env_clear()
    .envs(recipe_env.into_env_pairs())      // VERB-03 typed source
    .output();
match out {
    Ok(o) => DispatchResult {
        exit_code: o.status.code().unwrap_or(1),
        stdout: String::from_utf8_lossy(&o.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&o.stderr).into_owned(),
        streamed: false,
    },
    Err(_) => DispatchResult { exit_code: 1, stdout: String::new(), stderr: /*msg*/, streamed: false },
}
```

### invoker==target short-circuit (mirrors dispatcher.ts:70-72)
```rust
let invoker = /* getpwuid(getuid()).name or $USER */;
let (cmd, rest) = if invoker == user {
    (argv[0].clone(), argv[1..].to_vec())
} else {
    ("sudo".into(), {
        let mut v = vec!["-u".into(), user.into(), "-H".into(), "-E".into(), "--".into()];
        v.extend(argv); v
    })
};
```

### Timeout with SIGTERM→SIGKILL (mirrors dispatcher.ts:135-141)
```rust
// after spawn, in the watchdog:
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;
let pid = Pid::from_raw(child.id() as i32);
if deadline_exceeded {
    let _ = kill(pid, Signal::SIGTERM);
    // wait up to 2000ms for exit; then:
    let _ = kill(pid, Signal::SIGKILL);
    exit_code = 124; // GNU timeout convention
}
```

## State of the Art

| Old (TS) | New (Rust) | Notes |
|----------|-----------|-------|
| Commander `^12` subcommands | `clap` 4 derive | Same declarative shape; free `--help`; verify no exact-help-text bats assert. |
| Node `child_process.execFile`/`spawn` | `std::process::Command` + `nix` signals | `std` lacks SIGTERM; `nix`/`libc` fills the gap. |
| `process.stdin.isTTY` | `std::io::IsTerminal` (stable) | `stdin().is_terminal()` — no crate. |
| `semver` npm | `agentlinux_core::semver_shim` | Already ported; node-semver divergences isolated (TEST-04). |

**Deprecated/outdated:** none introduced. The TS remains the live implementation on master until Phase 58 flips the distribution channel.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `clap` 4.x is current + legitimate | Standard Stack | Low — canonical crate; gate + `cargo search` at plan time confirm. |
| A2 | `nix` (signal feature) is the right escalation primitive; `libc` is the lighter alt | Standard Stack, VERB-02 | Low — both are rust-lang/well-known; either works. Pick at plan time. |
| A3 | No bats asserts an exact Commander-generated `--help` body | Arg Parsing, Acceptance Oracle | Medium — if one does, clap's default help differs; must replicate the string. **Grep to confirm at plan time.** |
| A4 | Setting the 6 env vars on the child process (no manifest file) satisfies every recipe | VERB-03 | Low — verified recipes read `${AGENTLINUX_*}` from env; a Rust `Command::envs` child inherits them. |
| A5 | Overriding the `agentlinux` symlink target in the test harness is the accepted staging mechanic (vs. changing the provisioner) | Acceptance Oracle, Runtime State | Low — matches GATE-05 parallel-track; provisioner change is explicitly Phase 57/58. |
| A6 | `wait-timeout` (if used) covers the buffered-path timeout; streaming still needs manual threads+nix | Standard Stack | Low — optional; a `try_wait` loop is the fallback. |
| A7 | clap can express the `install --version <semver>` vs global `--version` shadow | Arg Parsing | Medium — standard clap pattern (`disable_version_flag` on the subcommand), but verify the exact config reproduces Commander's `enablePositionalOptions` behavior. |

**All A1/A2/A6 crate versions are `[ASSUMED]` until §Package Legitimacy Audit + `cargo search` run at plan time.**

## Open Questions

1. **Does any CLI bats assert exact `--help`/usage text?**
   - Known: `CLI-01 --version` asserts the version number (fine for clap `.version()`).
   - Unclear: whether a `--help` body or a Commander-specific usage line is grepped.
   - Recommendation: `grep -nE 'Usage:|Options:|--help' tests/bats/{40,23,10,50}*.bats` in Wave 0; if found, use a clap custom help template or a per-verb hand-written help.

2. **Buffered timeout: is any buffered caller time-bounded?**
   - `queryGlobalNpm`/`queryNpmViewLatest` pass `timeout: 30_000` (npm_ls.ts:78,119) to the **buffered** `asUser` (not streaming). The TS buffered path honors `execFile`'s `timeout` option (dispatcher.ts:85).
   - Recommendation: the Rust buffered path must ALSO honor a timeout (30s for npm) — use `wait-timeout` or a `try_wait` loop + SIGKILL. Pin this; it's easy to miss since the streaming test dominates attention.

3. **Where does `shouldReinstall` + `validateReusedBinary` (upgrade.ts:33-101) land?**
   - `shouldReinstall` is pure (flag priority); `validateReusedBinary` does a `statSync` (I/O).
   - Recommendation: `shouldReinstall` → a small pure helper (bin or core); `validateReusedBinary`'s stat → the upgrade adapter. Split them.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `cargo` + musl target | Build the Rust bin | ✓ (Phase 53 CI) | rust 1.97.1 (workspace) | — (blocking) |
| `sudo` | dispatcher `sudo -u` path (invoker!=target) | ✓ (in container) | — | invoker==target short-circuit avoids it in the common case |
| `npm` | `queryGlobalNpm`/`queryNpmViewLatest` (upgrade) | ✓ (Phase 3 Node) | NodeSource | upgrade report still renders with `latest=null` on failure |
| Docker + bind-mount | bats acceptance (per-file, OOM-safe) | ✓ (tests/docker/run.sh) | — | QEMU (Phase 59) |
| `crates.io` access | add `clap`/`nix` | ✓ (assumed CI) | — | vendored deps |

**Missing dependencies with no fallback:** none identified — the toolchain is established by Phases 53–55.

## Validation Architecture

> nyquist_validation: the CLI I/O layer is validated by **bats behavior** (per CONTEXT: "the CLI I/O layer is validated by bats behavior"); new pure helpers (`shouldReinstall`, `RecipeEnv` assembly) get Rust `#[test]` + fall under the Phase-54 proptest/mutants scope.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats (acceptance) + Rust `cargo test` (unit/parity) + node:test (TS reference oracle) |
| Config file | `tests/bats/` (bats), `rust/` workspace (cargo), `plugin/cli/` (node:test) |
| Quick run command | `cargo test -p agentlinux` (dispatcher/env/parse units) |
| Full suite command | `tests/docker/run.sh <distro>` per-file for CLI bats (OOM-safe) |

### Phase Requirements → Test Map
| Req | Behavior | Test Type | Automated Command | Exists? |
|-----|----------|-----------|-------------------|---------|
| VERB-01 | 6 verbs contract-equiv stdout/exit | acceptance | `bats tests/bats/40-registry-cli.bats` (Rust bin staged) | ✅ bats / ❌ Rust cmd adapters (Wave) |
| VERB-01 | per-verb parity strings | unit | `cargo test -p agentlinux cmd::` | ❌ Wave 0 (mirror the `.test.ts` cases) |
| VERB-02 | dispatcher tee/timeout/signal/exit-map | unit | `cargo test -p agentlinux dispatcher` (mirror dispatcher-stream.test.ts's 6 cases) | ❌ Wave 0 |
| VERB-02 | real recipe dispatch | acceptance | `bats tests/bats/50-agents.bats` (network/systemd-gated) | ✅ bats / ❌ dispatcher |
| VERB-03 | env-var assembly + PATH + install-user | unit | `cargo test -p agentlinux recipe_env` (mirror runner.test.ts) | ❌ Wave 0 |
| VERB-03 | recipes run unchanged | acceptance | `bats tests/bats/40,50` | ✅ bats |
| GATE-01 | full CLI bats green on Rust build | acceptance | per-file `tests/docker/run.sh` | ✅ harness / ❌ staging override |

### Sampling Rate
- **Per task commit:** `cargo test -p agentlinux` + `cargo clippy` (fast).
- **Per wave merge:** the targeted CLI bats file(s) for that wave's verbs on the Rust-staged container.
- **Phase gate:** full CLI bats set (40/23/10 + 50 where network permits) green on the Rust build before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `rust/crates/agentlinux/src/dispatcher.rs` + `cargo test dispatcher` — the 6 dispatcher-stream parity cases (VERB-02).
- [ ] `recipe_env.rs` + `cargo test recipe_env` — the runner.test.ts env/PATH/user cases (VERB-03).
- [ ] `tests/docker/run.sh` symlink-override (stage Rust bin AS the `agentlinux` command), flag-gated (GATE-05).
- [ ] Grep bats for exact `--help`/usage asserts (Open Q1) before committing to clap default help.
- [ ] Confirm buffered-path timeout honored for npm (Open Q2).

## Security Domain

> `security_enforcement` enabled (absent = enabled). This phase runs subprocesses as another user + parses user-controlled argv → input-validation + command-injection are live.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V5 Input Validation | yes | clap-parsed args; `parse_pin_spec` (core) validates pin targets; `--version` via `semver_shim::valid`; install-user via POSIX charset `^[a-z][a-z0-9_-]*$` (runner.ts:20). |
| V5 Command Injection | yes | **argv arrays, never a shell string** — `Command::new(...).args(argv)` (mirrors TS `execFile`/`spawn`, NOT `exec`). The `--` terminator ends sudo option parsing so user args can't be reparsed (dispatcher.ts:6,72). |
| V4 Access Control | yes | CLI-05 invoker guard (`guardAgentUser`) — refuse unless invoker == configured install user, exit 64. |
| V6 Cryptography | no | — |

### Known Threat Patterns for {Rust CLI + sudo dispatch}
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Shell injection via catalog `id`/`npm_package_name` | Tampering/Elevation | argv arrays (never shell); ajv schema pattern-validates the fields at load (npm_ls.ts:7-10). |
| `sudo -u` arg reparse | Elevation | `--` terminator (dispatcher.ts:72); user string re-validated against POSIX charset before it reaches `sudo -u` (runner.ts:20,41). |
| Malformed install-user from tampered `/etc/agentlinux.env` | Elevation | charset re-validation → fall back to `agent` (runner.ts:41; runner.test.ts:188). |
| preserve_paths traversal (`..`/absolute) deleting user data on REMEDIATE | Tampering | loader rejects `..`/absolute normalized paths (loader.ts:52-63) — port this validation into `catalog.rs`. |
| Detect-cache path override abuse | Tampering | `AGENTLINUX_DETECT_CACHE` is a test seam; in prod the cache is root-written at `/run/…`. No new surface — mirror TS. |

## Sources

### Primary (HIGH confidence — this repo's source, read this session)
- `plugin/cli/src/state/dispatcher.ts` (VERB-02 core), `plugin/cli/src/runner.ts` (VERB-03 assembly) — dispatcher + env contract.
- `plugin/cli/src/commands/{list,install,remove,upgrade,pin,adopt}.ts` — the 6 verbs' stdout/exit/flag contracts.
- `plugin/cli/src/{detect,index,rewire}.ts`, `catalog/loader.ts`, `state/sentinel.ts`, `guard/user.ts`, `version/probe.ts`, `upgrade/npm_ls.ts` — adapters + entrypoint.
- `plugin/cli/test/{dispatcher-stream,runner}.test.ts` — the VERB-02/VERB-03 parity specs.
- `rust/crates/agentlinux-core/src/{lib,types,classify,divergence,detect_gates,category,pin_spec,reuse,semver_shim}.rs` — confirmed ported decision core.
- `rust/crates/agentlinux/src/main.rs` — the Phase-53 thin bin + canonical-path map + pure/adapter split precedent.
- `plugin/provisioner/50-registry-cli.sh` (symlink staging), `tests/docker/run.sh` (Rust bin staging), `plugin/catalog/agents/gsd/install.sh` (recipe env consumption), `tests/bats/{40,50,23,10}*.bats` (acceptance).

### Secondary (MEDIUM confidence)
- CONTEXT.md, REQUIREMENTS.md, ROADMAP.md (phase boundary + requirement IDs).

### Tertiary (LOW confidence — verify at plan time)
- `clap`/`nix`/`libc`/`wait-timeout` crate versions + legitimacy — run `cargo search` + `package-legitimacy check`.

## Metadata

**Confidence breakdown:**
- The Six Verbs (VERB-01): HIGH — every verb's TS source read; decision core confirmed ported; only adapter/shape work + exact-string replication remain.
- Dispatcher (VERB-02): HIGH — full TS source + a complete 6-case unit-test spec; the only uncertainty is which Rust signal crate (both viable).
- Env contract (VERB-03): HIGH — the 6 names + recipe consumption + runner.test.ts pin it; no manifest needed.
- Cache adapter: HIGH — TS source read; the pure gates it feeds are ported.
- Arg parsing: MEDIUM — `clap` recommended; the one risk (exact-help-text bats asserts) is a plan-time grep.
- Crate versions/legitimacy: LOW until the plan-time gate.

**Research date:** 2026-07-28
**Valid until:** 2026-08-27 (stable — grounded in in-repo source; only external crate versions age).
