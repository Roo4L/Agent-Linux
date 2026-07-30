# Phase 53: Rust Scaffold + De-Risking Spike - Research

**Researched:** 2026-07-28
**Domain:** Rust cargo-workspace bootstrap · static musl CI · node-semver→Rust `semver` parity · bats integration seam for a partial TS→Rust port
**Confidence:** HIGH (toolchain + semver divergences empirically verified this session; repo seam grounded in cited source)

## Summary

This spike proves the v0.4.0 Rust rewrite end-to-end at small scale. The decision to
use Rust is settled (`docs/research/v0.3.0/stack-reconsideration.md`, owner 2026-07-27) —
this research does **not** re-litigate it. It answers *how to build the first slice*:
a cargo workspace producing a fully-static musl `agentlinux` binary (RUST-01), wired into
the existing GitHub-Actions CI as a Rust job in the Docker matrix (RUST-02), with three
units ported — `classify`, `divergence`, and one gnarly provisioner unit — validated
behind the **existing bats suite unchanged** (RUST-03, GATE-01), and agent-loop cost
instrumented (RUST-03) so phases 54–59 are calibrated by evidence.

The single highest-risk correctness item — node-semver→Rust `semver` parity — was probed
empirically this session and produced concrete, actionable divergences (compound-range
comma requirement; strict `Version::parse`; prerelease opt-in). The single highest-value
*integration* insight is that the recommended provisioner unit (`reuse::agent_decision`,
per REUSE-03) is consumed at exactly **one** call site (`remediate.sh:288`) via command
substitution and is exercised by bats through a sourced bash function that reads
`DETECT_AGENT_*` env vars and prints a token — a seam so thin the Rust binary can be
swapped in behind it with **zero bats edits**.

**Primary recommendation:** Cargo workspace at repo-root `rust/` with `crates/agentlinux-core`
(pure, no I/O — the classify/divergence/reuse-decision logic + a `semver` compatibility
shim) and `crates/agentlinux` (bin). Port `reuse::agent_decision` as the gnarly unit
(single call site, env-var-in/token-out, directly bats-exercised). Build the parity shim
around dtolnay `semver 1.0.28` that normalizes the catalog's space-separated compound ranges
to comma form and reuses the TS test tables verbatim as the golden corpus.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| classify (6-state version status) | Pure-logic core (`agentlinux-core`) | — | I/O-free deterministic fn; the whole rewrite is justified by making this testable in isolation |
| computeDivergence + resolveLatestFor | Pure-logic core | — | Same; `resolveLatestFor` needs the semver shim but takes versions as a `&[String]` — no I/O |
| semver range/version evaluation | Pure-logic core (shim over `semver` crate) | — | Wraps dtolnay `semver`; owns the node-semver→Rust normalization so callers never see the divergence |
| reuse::agent_decision (the gnarly unit) | Pure-logic core (decision) + bin (env-var read + stdout token) | Bash seam (`reuse/agents.sh`) shells to bin | Decision is pure (predicates 1+2 over status/path); only the env-var read + `printf` token are I/O — matches the existing bash contract |
| CLI entrypoint / arg parse | Bin crate (`agentlinux`) | — | Subcommand dispatch (`clap` later; spike needs only a couple of hidden subcommands) |
| provisioner recipes (`install.sh`) | Bash (unchanged) | — | Irreducible env-var boundary — survives any rewrite (stack-reconsideration §"irreducible boundary"); **do not port** |
| bats acceptance | Bash (unchanged) | — | ADR-002 language-agnostic executable spec; the safety net, edited only if a genuine behavior change demands it |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `semver` (dtolnay) | 1.0.28 | Version + VersionReq parse/match; `resolveLatestFor` max-satisfying | The de-facto Rust semver crate (Cargo's own); closest semantic match to node-semver per stack-reconsideration §4 `[VERIFIED: cargo search + empirical probe this session]` |
| `clap` | 4.6.4 | CLI arg/subcommand parsing (bin crate) | Standard Rust CLI framework; ships shell completions `[VERIFIED: cargo search this session]` — spike may defer to a hand-rolled `match` on argv if <3 subcommands |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `anyhow` | 1.x | Ergonomic error propagation in the bin crate | Bin-crate I/O/adapter errors; NOT the core (core uses typed errors so proptest asserts them) `[ASSUMED]` |
| `thiserror` | 1.x/2.x | Typed error enums in `agentlinux-core` | `resolveLatestFor` zero-match error must be a *typed* value (TEST-01 asserts "returns a typed error"), not a stringly error `[ASSUMED]` |
| `serde` + `serde_json` | 1.x | Parse the sentinel + catalog JSON the ported units read | classify/divergence consume `CatalogEntry` + `Sentinel` shapes; deserialize with serde `[ASSUMED]` |

### Phase-54-readiness crates (DO NOT install this phase — just don't preclude)
| Library | Version | Purpose | Spike must-not-preclude |
|---------|---------|---------|-------------------------|
| `proptest` | 1.11.0 | Property tests on the pure core (TEST-01) | Keep `agentlinux-core` genuinely I/O-free and its errors typed so proptest can assert invariants `[VERIFIED: cargo search this session]` |
| `cargo-mutants` | 27.1.0 | Mutation gate on the pure core (TEST-02) | Core must be a *separate crate* so `--package agentlinux-core` scopes mutation to it; keep the bin thin `[VERIFIED: cargo search this session]` |
| `schemars` | 1.2.2 | Generate `catalog/schema.json` from Rust types (TEST-03) | Model `CatalogEntry` as a plain `#[derive(Deserialize)]` struct now so `#[derive(JsonSchema)]` bolts on later without reshaping `[VERIFIED: cargo search this session]` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dtolnay `semver` | hand-rolled range matcher | Reinventing semver = exactly the "don't hand-roll" trap; the crate is Cargo's own and battle-tested |
| `clap` (spike) | bare `std::env::args` + `match` | For 1–2 hidden subcommands (`classify`, `reuse-decision`) a `match` is lighter and dodges a dep; adopt `clap` in Phase 56 when real verbs land |

**Installation (spike):**
```bash
# in rust/crates/agentlinux-core/Cargo.toml
semver = "1"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "1"
```

**Version verification (this session):**
```
cargo 1.97.1 (c980f4866 2026-06-30)   rustc 1.97.1 (8bab26f4f 2026-07-14)
rustfmt 1.9.0-stable                   clippy present ("No issues found")
target x86_64-unknown-linux-musl installed ; musl-gcc at /usr/bin/musl-gcc
semver = "1.0.28"  proptest = "1.11.0"  schemars = "1.2.2"  clap = "4.6.4"  cargo-mutants = "27.1.0"
```

## Package Legitimacy Audit

All Rust crates below are first-party or ecosystem-canonical; verified via `cargo search`
against crates.io this session. `semver` and `serde`/`serde_json` are dtolnay/serde-team
crates (billions of downloads). No SLOP/SUS verdicts.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| semver | crates.io | mature (Cargo's own) | ~billions | github.com/dtolnay/semver | OK | Approved |
| serde / serde_json | crates.io | mature | ~billions | github.com/serde-rs/serde · serde-rs/json | OK | Approved |
| thiserror | crates.io | mature | very high | github.com/dtolnay/thiserror | OK | Approved |
| anyhow | crates.io | mature | very high | github.com/dtolnay/anyhow | OK | Approved |
| clap | crates.io | mature | very high | github.com/clap-rs/clap | OK | Approved |
| proptest | crates.io | mature | high | github.com/proptest-rs/proptest | OK | Approved (Phase 54) |
| cargo-mutants | crates.io | mature | high | github.com/sourcefrog/cargo-mutants | OK | Approved (Phase 54) |
| schemars | crates.io | mature | high | github.com/GREsau/schemars | OK | Approved (Phase 54) |

**Packages removed due to SLOP verdict:** none
**Packages flagged as suspicious (SUS):** none

## Architecture Patterns

### System Architecture Diagram

```
                        ┌───────────────────── bats suite (UNCHANGED, ADR-002) ─────────────────────┐
                        │  13-reuse.bats  40-registry-cli.bats  14-remediate.bats  73-*.bats         │
                        └───────────┬───────────────────────────────────────┬──────────────────────┘
                                    │ (a) provisioner seam                    │ (b) CLI seam
                                    │ sources reuse.sh → reuse/agents.sh      │ invokes `agentlinux`
                                    ▼                                         ▼
     DETECT_AGENT_*_STATUS/PATH ─► reuse::agent_decision()  ──shells to──► agentlinux (bin, musl static)
     (env vars, set by bats/detect) │  prints {reuse|remediate|create}          │
                                    │  ▲ SAME contract in/out                    ▼
                                    │  └──────────────────────────────► agentlinux-core (pure crate)
                                    │                                    ├─ classify(entry,sentinel,installed) → Status
     remediate.sh:288 ─────────────┘                                    ├─ compute_divergence(...) → DivergenceReport
     RESOLUTIONS[agents.$id]=$(reuse::agent_decision "$id")             ├─ resolve_latest_for(entry,&[ver]) → Result<ver,Err>
                                                                        └─ semver_shim (normalize range → dtolnay semver)
```

Data-flow trace (primary use case = REUSE-03 decision): a bats `@test` exports
`DETECT_AGENT_CLAUDE_CODE_STATUS=healthy` + `_PATH=<canonical>`, sources the lib chain,
and runs `reuse::agent_decision claude-code`; the bash function (now a ~3-line shim) forwards
those env vars to the Rust bin, which computes the decision in `agentlinux-core` and prints
`reuse`; bats asserts stdout `== reuse`. No test edit.

### Recommended Project Structure
```
rust/                              # repo-root; NOT under plugin/ (see rationale)
├── Cargo.toml                     # [workspace] members = ["crates/*"]
├── Cargo.lock                     # committed (bin crate → lockfile is authoritative)
├── rust-toolchain.toml            # pin channel = "1.97.1" so CI + local + agent match
├── crates/
│   ├── agentlinux-core/           # PURE. no std::process, no std::fs, no std::env
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── classify.rs        # port of version/classify.ts
│   │       ├── divergence.rs      # port of upgrade/divergence.ts
│   │       ├── reuse.rs           # pure predicates 1+2 of reuse::agent_decision
│   │       ├── semver_shim.rs     # node-semver→dtolnay normalization (THE risk surface)
│   │       └── types.rs           # CatalogEntry, Sentinel, Status, DivergenceReport (serde)
│   └── agentlinux/                # BIN. reads env/args, calls core, prints
│       ├── Cargo.toml
│       └── src/main.rs            # hidden subcommands: reuse-decision, (classify/divergence for tests)
```

### Where the Rust code lives — recommendation + justification
**Put it at repo-root `rust/`, not `plugin/rust/`.** Justification against the existing layout:
- `plugin/` is described in `AGENTS.md` as "shippable installer code (bash entrypoint, lib
  helpers, provisioner steps, catalog, registry CLI in `plugin/cli/`)". The TS CLI lives at
  `plugin/cli/`. Mirroring with `plugin/rust/` is *defensible*, but the workspace's build
  artifacts, `target/`, and toolchain pin are a different build system than the bash tree;
  keeping them at `rust/` keeps `plugin/` a clean "what ships in the tarball" boundary during
  the parallel-track migration (GATE-05) where **both** the TS CLI and the Rust bin coexist.
- The CI `changes` filter (`test.yml:56-64`) already globs `plugin/**`, `scripts/**`,
  `.github/workflows/**`. A top-level `rust/` needs one new filter entry (`rust/**`) — a
  smaller, more legible diff than threading a second build root through `plugin/`.
- **Confidence: MEDIUM** — this is a Claude's-discretion layout call. The alternative
  `plugin/rust/` is acceptable; the planner should pick one and note it. Do NOT put Rust
  under `plugin/cli/` (that dir is the TS package root with its own `package.json`).

### Pattern 1: pure core / thin adapter split (mutation-test enabler)
**What:** Every branch of decision logic lives in `agentlinux-core` as a fn taking owned/borrowed
data and returning a value or typed error; the bin crate only reads env/args/stdin, calls the
core, and writes stdout/exit-code.
**When to use:** Everywhere. This is the structural reason the rewrite exists — `cargo-mutants
--package agentlinux-core` (Phase 54) only bites if the logic is in the pure crate.
**Example:**
```rust
// agentlinux-core/src/reuse.rs — pure; mirrors reuse::agent_decision predicates 1+2
// Source: ports plugin/lib/reuse/agents.sh:46-97
pub enum Decision { Reuse, Remediate, Create }
pub struct AgentObservation<'a> { pub status: &'a str, pub detected_path: &'a str }
pub fn agent_decision(id: &str, obs: Option<AgentObservation>, canonical: Option<&str>, gsd_system_path: &str) -> Decision {
    let Some(obs) = obs else { return Decision::Create };      // status=absent
    let Some(canonical) = canonical else { return Decision::Create }; // unknown id
    if obs.status == "broken" { return Decision::Remediate; }
    if obs.detected_path != canonical {
        if id == "gsd" && obs.detected_path == gsd_system_path { return Decision::Reuse; }
        return Decision::Remediate;
    }
    Decision::Reuse
}
```

### Pattern 2: semver compatibility shim (isolate the node divergences)
**What:** One module owns the node-semver→dtolnay translation so `classify`/`divergence` never
call `semver::VersionReq::parse` directly on a raw catalog string.
```rust
// agentlinux-core/src/semver_shim.rs
// dtolnay semver REQUIRES commas between compound comparators; node-semver accepts spaces.
// The catalog's compatibility_window is space-separated: ">=2.0.0 <3.0.0".
pub fn normalize_range(node_range: &str) -> String {
    // ">=2.0.0 <3.0.0" -> ">=2.0.0, <3.0.0"; leaves "^2.1" and "*" untouched.
    node_range.split_whitespace().collect::<Vec<_>>().join(", ")
}
```
**When to use:** `resolve_latest_for` and any `satisfies`. The classify path uses only *equality*
(`semver.eq`) and *greater-than* (`semver.gt`) on two concrete versions, which needs the
lenient-parse handling below, not range normalization.

### Anti-Patterns to Avoid
- **Calling `semver::Version::parse` directly on installed/sentinel strings.** It rejects
  `2.1`, `v1.0.0` (verified this session). node's `semver.eq`/`gt` accept `v`-prefix + partials
  via loose parsing. Route every version string through a lenient parser (strip leading `v`;
  see Pitfall 1) before comparing, or classify parity breaks on real-world `<bin> --version` output.
- **Porting the recipes or the env-var contract.** Out of scope (Phase 56/57). The spike emits
  a token / a decision; it does not touch `install.sh` or the six `AGENTLINUX_*` strings.
- **Editing bats tests to fit the Rust build.** The whole point (ADR-002) is that the spec is
  language-agnostic. If a bats test needs editing, that signals a real behavior divergence to fix
  in Rust, not a test to relax. Zero newly-skipped tests (GATE-01).
- **A single `agentlinux` crate with logic in `main.rs`.** Kills the Phase-54 mutation gate.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| semver range satisfaction / max-satisfying | a custom comparator | `semver` crate + a thin normalize shim | This is literally the reason bash "stops at predicate 2" (agents.sh:10-13); reinventing it reintroduces the bug class |
| JSON parse of sentinel/catalog | manual string slicing | `serde_json` | The TS side already models these shapes; serde derive is the parity-safe port |
| static-musl linking flags | bespoke linker invocation | rustup musl target + documented RUSTFLAGS (below) | The target is already added; the flag set is well-known |
| CLI subcommand dispatch (later) | argv string matching at scale | `clap` | Only when Phase 56 verbs land; spike can `match` 1–2 hidden subcommands |

**Key insight:** the sync pain the whole milestone targets *is* a hand-rolled-semver-in-bash
artifact. The spike's job is to prove Rust removes it — so leaning on the `semver` crate (not
re-deriving ranges) is the thesis, not a shortcut.

## node-semver → Rust `semver` Parity (HIGHEST-RISK ITEM — empirically probed)

The CLI uses `semver.valid`, `semver.satisfies`, `semver.maxSatisfying`, `semver.eq`,
`semver.gt` (classify.ts:20,22,26 · divergence.ts:64). The live catalog uses only caret
(`^2.1`), a bare pin, and one compound `compatibility_window` (`>=2.0.0 <3.0.0`) — no `||` or
hyphen ranges `[VERIFIED: grep of plugin/catalog this session]`.

**Empirical probe results (Rust `semver 1.0.28`, run this session):**

| node-semver call | node behavior | Rust `semver` behavior (probed) | Parity risk | Mitigation |
|------------------|---------------|--------------------------------|-------------|------------|
| `satisfies("2.5.0","^2.1")` | true | `^2.1` matches 2.5.0 → **true**; matches 3.0.0 → **false** | none | caret semantics agree |
| `satisfies("2.5.0",">=2.0.0 <3.0.0")` (space) | true | **`VersionReq::parse(">=2.0.0 <3.0.0")` ERRORS** ("expected comma after patch") | **HIGH** | `normalize_range`: space→", " before parse |
| `maxSatisfying(vs,"^1.0")` | `1.2.0` | `1.2.0` | none | agrees on the divergence.test.ts corpus |
| `maxSatisfying(vs,"~1.1")` | `1.1.0` | `1.1.0` | none | agrees |
| `maxSatisfying(vs,"^9.0")` | `null` → throw | NONE → typed error | none | matches T-04-13 zero-match error path |
| `maxSatisfying(vs,"*")` | `2.1.0` | `2.1.0` | none | agrees |
| range vs prerelease `^1.0` vs `1.5.0-beta` | false | **false** | none | both exclude prereleases from a non-prerelease range |
| range `>=1.0.0 <2.0.0` vs `1.5.0-beta` | false | false | none | agrees |
| `valid("2.1")` | `null`-ish / loose accepts as `2.1.0` in ranges | **`Version::parse("2.1")` ERRORS** | **MEDIUM** | never `Version::parse` a partial; only full versions from `npm ls`/`--version` reach `eq`/`gt` |
| `eq("v1.0.0","1.0.0")` | true (strips `v`) | **`Version::parse("v1.0.0")` ERRORS** | **MEDIUM** | strip a leading `v` in the lenient parser before compare |

**Load-bearing findings for the planner (all verified this session unless noted):**
1. **Compound-range comma is mandatory** in dtolnay `semver` — the catalog's space-separated
   `compatibility_window` will NOT parse as-is. `normalize_range` is a required, tested helper.
   This is the single most likely silent parity break. `[VERIFIED: empirical probe]`
2. **`Version::parse` is strict** — rejects partials (`2.1`) and `v`-prefix (`v1.0.0`). node's
   loose mode accepts both. classify's `eq`/`gt` receive full versions from `npm ls -g --json`
   and `<bin> --version`, but `<bin> --version` output commonly carries a `v` prefix — strip it.
   `[VERIFIED: empirical probe]`
3. **Prerelease opt-in already agrees** for the ranges the catalog uses (caret + compound both
   exclude prereleases unless the comparator names one). Lower risk than feared. `[VERIFIED: empirical probe]`
4. Reuse the TS test tables verbatim as the golden corpus: `divergence.test.ts:133`
   (`["1.0.0","1.1.0","1.2.0","2.0.0","2.1.0"]` with `^1.0→1.2.0`, `~1.1→1.1.0`, `^9.0→throw`)
   and the six classify states in `classify.test.ts:36-93`. The Rust probe already reproduced
   the divergence-corpus expectations. `[VERIFIED: repo files + probe]`

> The **full** parity audit (TEST-04) is Phase 54. The spike must (a) build `normalize_range` +
> lenient version parse so classify/divergence pass their ported test tables, and (b) hand Phase 54
> this table as the starting audit. Do not defer the comma/`v`-prefix handling — the ported unit
> tests fail without it.

## Static musl Build in GitHub Actions CI

The existing `.github/workflows/test.yml` is the fit target. It has a `changes` job
(`dorny/paths-filter@v3`, outputs `code`), a `pre-commit` job, `cli-unit` (node), a
`bats-docker` matrix (`ubuntu-22.04/24.04/26.04 + almalinux-9`), and `permissions: contents: read`
with a per-workflow least-privilege posture (CIPUB-01, `test.yml:24`).

### Recommended additions (RUST-02)
1. **Extend the `changes` filter** (`test.yml:56`) with a `rust/**` path so a Rust job can gate
   its steps like `cli-unit`/`bats-docker` do (job runs + reports green fast on dev-only changes;
   keeps required-check contexts always reported — see the `test.yml:37-40` matrix-skip trap note).
2. **Add a `rust` job** (mirrors `cli-unit`'s guard-then-steps shape):
```yaml
  rust:
    needs: changes
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v5
      - name: Skip if no code changed or rust/ absent
        id: guard
        env: { CODE_CHANGED: "${{ needs.changes.outputs.code }}" }
        run: |
          if [ "$CODE_CHANGED" != "true" ] || [ ! -f rust/Cargo.toml ]; then
            echo "ready=false" >> "$GITHUB_OUTPUT"
          else echo "ready=true" >> "$GITHUB_OUTPUT"; fi
      - name: Install Rust toolchain (pinned via rust-toolchain.toml)
        if: steps.guard.outputs.ready == 'true'
        uses: dtolnay/rust-toolchain@stable          # respects rust-toolchain.toml; or @1.97.1
        with: { components: clippy,rustfmt, targets: x86_64-unknown-linux-musl }
      - uses: Swatinem/rust-cache@v2                  # caches ~/.cargo + target/
        if: steps.guard.outputs.ready == 'true'
        with: { workspaces: rust }
      - name: rustfmt --check
        if: steps.guard.outputs.ready == 'true'
        working-directory: rust
        run: cargo fmt --all -- --check
      - name: clippy (deny warnings)
        if: steps.guard.outputs.ready == 'true'
        working-directory: rust
        run: cargo clippy --all-targets -- -D warnings
      - name: unit tests
        if: steps.guard.outputs.ready == 'true'
        working-directory: rust
        run: cargo test --all
      - name: static musl build + ldd assertion (RUST-01)
        if: steps.guard.outputs.ready == 'true'
        working-directory: rust
        run: |
          sudo apt-get update -qq && sudo apt-get install -y musl-tools
          cargo build --release --target x86_64-unknown-linux-musl -p agentlinux
          BIN=target/x86_64-unknown-linux-musl/release/agentlinux
          ldd "$BIN" 2>&1 | grep -q "not a dynamic executable" \
            || { echo "RUST-01 FAIL: binary is dynamically linked"; ldd "$BIN"; exit 1; }
```
3. **Fully-static linking.** With the `x86_64-unknown-linux-musl` target, recent Rust links musl
   statically by default for a pure-Rust dep tree (no C deps here). Belt-and-braces, set in
   `rust/.cargo/config.toml`:
```toml
[target.x86_64-unknown-linux-musl]
rustflags = ["-C", "target-feature=+crt-static"]
linker = "musl-gcc"   # musl-tools provides it; /usr/bin/musl-gcc present this session
```
   `[VERIFIED: musl-gcc + target present this session]` `[CITED: rust musl target defaults — crt-static is default for *-musl]`
4. **Adding the Rust build to the "Docker matrix"** (RUST-02 wording). Two readings — call this out
   for the planner:
   - **(a) Add the Rust job to `test.yml`** so it runs on every PR alongside the Docker matrix
     (recommended for the spike — cheapest, satisfies "on every PR" + "Rust job added").
   - **(b) Build the musl binary INSIDE the `bats-docker` containers** so the bats suite exercises
     the actual static artifact per-distro. This is stronger (and is where GATE-02 lands in
     Phase 59) but heavier. For the spike, the ported unit only needs to run behind bats on the
     musl binary — building it once (step above) and copying it into the container via
     `tests/docker/run.sh` is the smallest sufficient seam. **Recommendation: (a) for the RUST-02
     job + a single musl artifact mounted into the targeted bats containers for the ported surface.**
     Flag: the roadmap says "added to the Docker matrix" — the planner should decide (a) vs (b);
     (a) satisfies the literal RUST-02 checkbox, (b) is the Phase-59 endgame.
5. **`rust-toolchain.toml`** pinning `channel = "1.97.1"` guarantees CI, local, and the agent loop
   use one compiler — removes a class of "works on my machine" churn that inflates iterations-to-green.

## The bats-Integration Seam for a PARTIAL Port

The bats suite (41 files, 10,638 LOC, ADR-002) asserts observable state. For a partial port the
smallest seam depends on the unit; the two the spike touches:

### Pure logic (classify + divergence)
These are **not directly** invoked by bats — they are internal CLI functions unit-tested in TS
(`classify.test.ts`, `divergence.test.ts`) and exercised *indirectly* when bats runs
`agentlinux list`/`upgrade` (`40-registry-cli.bats`). For the spike, port them into
`agentlinux-core` and validate with **ported Rust unit tests reusing the TS tables** (the golden
corpus). Wiring them behind the live `agentlinux list` output is Phase 56 (CLI verbs) — the spike
does not need `list` to shell to Rust to prove classify/divergence port correctly; the ported
unit tests + the semver parity table are the evidence. Keep this explicit so the planner does not
over-scope a `list` rewrite into the spike.

### The gnarly provisioner unit — the true bats-validated seam
`reuse::agent_decision` (`plugin/lib/reuse/agents.sh:46`) is exercised **directly** by bats:
`13-reuse.bats` sources the lib chain via `__source_lib_chain_with_reuse` (13-reuse.bats:57),
exports `DETECT_AGENT_<ID>_STATUS/PATH/VERSION`, runs `reuse::agent_decision <id>`, and asserts
stdout `== {reuse|remediate|create}` (13-reuse.bats:429-500+). It is consumed in production at
**exactly one** call site: `remediate.sh:288` — `RESOLUTIONS[agents.$agent_id]=$(reuse::agent_decision "$agent_id")`.
`[VERIFIED: grep this session]`

**Smallest seam (zero bats edits):** replace the *body* of the `reuse::agent_decision` bash function
with a shim that forwards the same env vars to `agentlinux reuse-decision <id>` and echoes its stdout:
```bash
# plugin/lib/reuse/agents.sh (spike form)
reuse::agent_decision() {
  local id=${1:-}
  # env vars DETECT_AGENT_<UPPER>_STATUS/PATH already exported by caller/bats.
  agentlinux reuse-decision "$id"   # Rust bin reads env, prints reuse|remediate|create
}
```
- The env-var-in / stdout-token-out contract is **unchanged**, so every `13-reuse.bats` @test and
  the `remediate.sh:288` call site work verbatim. The `REUSE_AGENT_CANONICAL_PATHS` map + gsd
  `REUSE_GSD_SYSTEM_PATH` move into Rust (`agentlinux-core`), which is the point (kills the
  byte-identical-sync duplication for this unit — though the *delete-from-detect.ts* consolidation
  is Phase 57; the spike may keep both maps present, or gate the shim behind a flag).
- **Bats files covering the ported surface:** `tests/bats/13-reuse.bats` (the REUSE-03
  `reuse::agent_decision` @tests — the primary evidence), with `14-remediate.bats` and
  `40-registry-cli.bats` as the downstream consumers to smoke. `73-phase51-gsd-codex.bats`
  references reuse/gsd too. Record exactly which files were run.
- **OOM constraint (documented):** the full Docker bats suite OOMs mid-run (~test 131) in this VM
  `[VERIFIED: MEMORY.md reference_docker_oom]`. Run **targeted per-file** bats containers
  (`13-reuse.bats`, `14-remediate.bats`) and record which files were exercised. Do NOT claim
  full-suite green from a partial run — the CI Docker matrix (fresh runners) is where full-suite
  green is asserted; locally, run the ported-surface files only.

## Which Provisioner Unit to Port (CONTEXT recommends REUSE-03; evaluated)

Criterion: *smallest bats-validatable integration seam with highest thesis signal.*

| Candidate | LOC | Bats seam | Integration surface | Thesis signal | Verdict |
|-----------|-----|-----------|---------------------|---------------|---------|
| `reuse::agent_decision` (`reuse/agents.sh`) | 97 | **Direct** — `13-reuse.bats` calls the fn, asserts stdout token | **1 call site** (`remediate.sh:288`), env-var-in/token-out | **Highest** — it is the exact sync-pain exemplar (stops at predicate 2 because "semver in bash is non-trivial"; hand-synced CANONICAL_PATHS). Porting proves Rust does the semver predicate AND lets the map live once | **RECOMMENDED** |
| npm-prefix reconciliation (`30-nodejs.sh:154-172`) | 174 | Indirect — asserted via post-install filesystem/ownership state across `13/14/15-*.bats` | Wide — reads `RESOLUTIONS[npm-prefix]`, calls `remediate::nodejs::chown_or_rebase`, mutates real dirs/ownership, TTY-decline paths | Medium — proves subprocess/FS mutation but drags in ownership/chown side-effects that are hard to isolate in a spike | Alternative only if a stdout-token seam is judged too narrow |

**Recommendation: port `reuse::agent_decision`.** It is the single thinnest seam (one call site,
pure env→token), it is *directly* bats-asserted (highest-fidelity acceptance signal with least
plumbing), and it carries the maximal thesis payload — it is the verbatim example the decision doc
quotes for why bash can't do the job. The npm-prefix unit is broader (real filesystem/ownership
mutation, TTY-decline branches) and better suited to Phase 57 where the full provisioner ports.

## Common Pitfalls

### Pitfall 1: `<bin> --version` output breaks strict `Version::parse`
**What goes wrong:** classify's `semver.eq(sentinel.version, installed)` gets `installed` from
`<bin> --version`, which often emits `v1.2.3` or trailing build metadata. Rust `Version::parse`
rejects `v`-prefix (verified this session).
**Why:** dtolnay `semver` is strict-by-design (Cargo's flavor); node-semver runs a loose/coerce path.
**How to avoid:** a `parse_lenient(&str) -> Result<Version>` that strips a leading `v`/whitespace
before `Version::parse`. Add the `v1.0.0` and `2.1` cases to the ported test table.
**Warning signs:** a classify parity test passes on clean `1.2.3` inputs but fails on real
`--version` strings.

### Pitfall 2: compound `compatibility_window` silently fails to parse
**What goes wrong:** `VersionReq::parse(">=2.0.0 <3.0.0")` errors (needs a comma) — verified. If the
port swallows the parse error, `reuse` predicate-3 / `resolveLatestFor` misbehaves silently.
**Why:** node accepts space-separated comparators; dtolnay requires comma-separated.
**How to avoid:** `normalize_range` (space→", ") applied to every catalog range before parse; a
test asserting `>=2.0.0 <3.0.0` matches `2.5.0`.
**Warning signs:** `13-reuse.bats` predicate involving `compatibility_window` (or Phase-55 tests)
flips reuse→remediate for an in-window version.

### Pitfall 3: cargo compile timeouts inflate the agent loop (a MEASURED risk)
**What goes wrong:** stack-reconsideration §7 flags an open Claude Code bug where slow `cargo`
compiles time out; Rust also has the worst crate-hallucination rate (Opus 4 ~27%).
**Why:** cold `cargo build` on a fresh dep tree + agent-loop tool timeouts.
**How to avoid:** `Swatinem/rust-cache` in CI; keep the spike's dep tree tiny (semver+serde+thiserror);
pin the toolchain; **instrument** these incidents (this is literally RUST-03's deliverable, not
just a nuisance — a timeout/hallucination is a data point).
**Warning signs:** repeated tool-timeouts on `cargo build`; a hallucinated crate name in a
`Cargo.toml` edit.

### Pitfall 4: over-scoping the spike into a `list`/CLI rewrite
**What goes wrong:** wiring classify/divergence behind live `agentlinux list` output drags the whole
CLI-verb + subprocess-dispatcher surface (Phase 56) into a spike.
**Why:** classify/divergence are only *indirectly* bats-visible (via `list`/`upgrade`).
**How to avoid:** validate classify/divergence with **ported unit tests reusing the TS tables**;
only `reuse::agent_decision` needs the live bats seam. Keep `list` on TS this phase.
**Warning signs:** the plan grows tasks for `npm_ls.ts`, `runner.ts`, or the env-var contract.

## Runtime State Inventory

> This is a rename/refactor-adjacent phase (porting logic across languages), so the inventory applies
> to the *duplicated-constant* surface the port touches.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — the ported units are pure functions over passed-in JSON (sentinel/catalog); no datastore keys renamed. Verified: classify/divergence/reuse take args, touch no DB. | none |
| Live service config | None — no external service embeds the ported logic. | none |
| OS-registered state | None — spike adds a `rust/` build + a CI job; no OS-registered names change. | none |
| Secrets/env vars | The `DETECT_AGENT_*` and `AGENTLINUX_*` env-var *names* are the contract the seam reads; the spike **preserves** them (env-var-in/token-out). No secret/key rename. | none — preserve names exactly |
| Build artifacts | New: `rust/target/` (gitignore it), `rust/Cargo.lock` (commit it). The duplicated `CANONICAL_PATHS`/`GSD_SYSTEM_PATH` in `detect.ts:16,28` + `reuse/agents.sh:31,41` MUST stay byte-identical while both exist — the spike may move the reuse-unit copy into Rust but **deleting from bash/TS is Phase 57**; keep them in sync until then. | add `rust/target/` to `.gitignore`; commit `Cargo.lock`; note the still-duplicated maps for Phase 57 |

**The canonical question — after every file is updated, what still has the old contract?** The
bats suite and `remediate.sh:288` both call `reuse::agent_decision` with the same signature; the
seam preserves it, so nothing downstream breaks. The only live duplication is the CANONICAL_PATHS
map (deliberately kept in sync until Phase 57's consolidation).

## Validation Architecture

> `.planning/config.json` not read as blocking; nyquist not confirmed false — section included.

### Test Framework
| Property | Value |
|----------|-------|
| Framework (Rust) | `cargo test` (built-in; `#[test]` + `#[cfg(test)]` mod) — Wave 0 for the ported units |
| Framework (acceptance) | bats-core (existing) via `tests/docker/run.sh <target>` |
| Config file | `rust/Cargo.toml` workspace; no extra test config for the spike |
| Quick run command | `cd rust && cargo test --all` |
| Full suite command | targeted: `bash tests/docker/run.sh ubuntu-24.04` after limiting to ported-surface bats files (OOM constraint) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RUST-01 | static musl binary, `ldd` = "not a dynamic executable" | build+assert | `cargo build --release --target x86_64-unknown-linux-musl -p agentlinux && ldd <bin> \| grep 'not a dynamic executable'` | ❌ Wave 0 |
| RUST-02 | CI clippy+fmt+test+build on PR | CI job | `cargo fmt --check && cargo clippy -- -D warnings && cargo test --all` (in `test.yml` rust job) | ❌ Wave 0 |
| RUST-03 (classify) | 6-state parity | unit | `cargo test -p agentlinux-core classify` (tables from `classify.test.ts`) | ❌ Wave 0 |
| RUST-03 (divergence) | maxSatisfying + zero-match error parity | unit | `cargo test -p agentlinux-core divergence` (tables from `divergence.test.ts`) | ❌ Wave 0 |
| RUST-03 (reuse unit) | reuse/remediate/create tokens behind bats | acceptance | `bats tests/bats/13-reuse.bats` (targeted container) | ✅ exists (13-reuse.bats) — must stay green |
| GATE-01 | no newly-skipped bats; ported surface green | acceptance | targeted `13-reuse.bats` + `14-remediate.bats` green; CI full matrix on PR | ✅ (suite exists) |
| GATE-05 | master shippable; per-phase rollback | process | work isolated on `worktree-stack-revisiting`; Rust job gated so a red spike can't block a master hotfix | n/a |

### Sampling Rate
- **Per task commit:** `cd rust && cargo test --all && cargo clippy -- -D warnings`
- **Per wave merge:** targeted bats (`bash tests/docker/run.sh ubuntu-24.04` limited to the ported
  files) + the musl `ldd` assertion
- **Phase gate:** CI `test.yml` green (rust job + bats-docker matrix) on the PR before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `rust/Cargo.toml` + `rust-toolchain.toml` + `rust/.cargo/config.toml` (workspace + musl flags)
- [ ] `agentlinux-core/src/{classify,divergence,reuse,semver_shim,types}.rs` + `#[cfg(test)]` tables ported from TS
- [ ] `agentlinux/src/main.rs` (`reuse-decision` subcommand)
- [ ] `plugin/lib/reuse/agents.sh` shim body (forward env → Rust bin)
- [ ] `test.yml` rust job + `rust/**` in the `changes` filter
- [ ] `.gitignore` `rust/target/`; commit `rust/Cargo.lock`
- [ ] `53-METRICS.md` scaffold (see below)

## Agent-Loop Metrics (RUST-03) — what to measure + `53-METRICS.md` shape

This is a **first-class deliverable**, not a side note — it is the go/no-go evidence for the bulk
port (stack-reconsideration §7 caveat: every Claude datapoint is 3.7 Sonnet; there is NO per-language
Opus/Sonnet-4.x data — this spike generates the first). Measure with **our** model on **our** code.

Record to `.planning/phases/53-.../53-METRICS.md`:

| Metric | How to capture | Why it matters |
|--------|----------------|----------------|
| Iterations-to-green (per ported unit) | count edit→`cargo test`/`cargo clippy` cycles until green, per unit (classify / divergence / reuse) | Direct calibration of per-unit port cost across the ~7k LOC remaining |
| Crate-hallucination incidents | count times a non-existent crate/API was proposed in a `Cargo.toml`/`use` (Rust's worst-in-class rate per §7) | Validates/refutes the accepted-cost estimate |
| cargo-compile-timeout incidents | count tool-timeouts on `cargo build`/`test` (the open Claude Code bug §7) | Bounds CI + loop-cost risk; informs the `rust-cache`/toolchain-pin mitigations |
| Wall-clock per unit | rough elapsed per unit (where observable) | Schedule input for 54–59 |
| Token cost per unit | where observable from the session | The "slower/pricier loops" accepted cost — quantify it |
| Parity surprises | any node-semver edge that needed a shim beyond the table above | Feeds the Phase-54 TEST-04 audit |

`53-METRICS.md` skeleton (planner seeds it, executor fills it):
```
# Phase 53 Agent-Loop Metrics
| Unit | Iters-to-green | Hallucinations | cargo-timeouts | Wall-clock | Tokens | Notes |
|------|----------------|----------------|----------------|-----------|--------|-------|
| classify   |  |  |  |  |  |  |
| divergence |  |  |  |  |  |  |
| reuse-decision (+ bats) |  |  |  |  |  |  |
## Verdict for the bulk port (54–59)
<go / go-with-caveats / re-estimate — the calibration output>
```

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| cargo/rustc | RUST-01/02/03 | ✓ | 1.97.1 | — |
| `x86_64-unknown-linux-musl` target | RUST-01 | ✓ | added via rustup | — |
| musl-gcc (musl-tools) | RUST-01 static link | ✓ | /usr/bin/musl-gcc | — |
| clippy | RUST-02 | ✓ | present | — |
| rustfmt | RUST-02 | ✓ | 1.9.0-stable | — |
| Docker (bats harness) | GATE-01 acceptance | ✓ (used by `tests/docker/run.sh`) | — | targeted per-file runs (full suite OOMs in this VM) |
| node/pnpm (existing TS tests) | parity corpus reference | ✓ | node 22 | — |

**Missing dependencies with no fallback:** none — the toolchain was bootstrapped this session.
**Missing dependencies with fallback:** full Docker bats suite OOMs mid-run in this VM → run
targeted per-file bats containers for the ported surface (`13-reuse.bats`, `14-remediate.bats`);
CI runners (fresh) run the full matrix.

## Project Constraints (from CLAUDE.md / AGENTS.md)

- **Behavior tests in `tests/bats/` are the spec (ADR-002).** Implementation may change freely
  while the suite stays green — the spike swaps Rust behind the same observable interface; zero
  bats edits, zero newly-skipped tests.
- **No wrapper shims at `/usr/local/bin/`** pointing to agent-owned binaries. The Rust bin ships in
  the plugin tree / tarball like the TS CLI — do NOT drop a shim at `/usr/local/bin/agentlinux`.
- **Agent-owned `$HOME`; never `sudo npm install -g`.** The Rust toolchain lives in agent-owned
  `~/.cargo`/`~/.rustup` (already set up). No privilege climbing.
- **Docker-only test runs are insufficient for a release** (QEMU gate) — but the *spike* validates
  the ported surface via Docker bats (GATE-02/QEMU is Phase 59). Don't claim release-readiness.
- **Review loop** (`.claude/skills/review/`) must run on changed files before reporting complete —
  new file types: Rust (bash reviewer for the `agents.sh` shim + a Rust reviewer role if present),
  YAML (CI), docs.
- **`master` (v0.3.6, shipped) untouched** — all work on `worktree-stack-revisiting` (GATE-05).
- **Session tracking** in Jira project AL for the concrete deliverable (this is a code-producing
  session, not research-only).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| semver predicate hand-stubbed in bash (stops at predicate 2) | Rust `semver` crate evaluates the range | this spike (reuse unit) | proves the thesis; predicate 3 becomes doable |
| CANONICAL_PATHS duplicated byte-identically across `detect.ts` + `agents.sh` | map lives once in Rust core (delete-from-bash/TS in Phase 57) | starts this spike, completes Phase 57 | removes a hand-sync bug class |
| TS CLI is the only binary | Rust static-musl bin coexists on a parallel track | v0.4.0 | no Node dependency for ported surface; per-phase rollback |

**Deprecated/outdated:** nothing removed this phase — the TS CLI stays authoritative; Rust is
additive behind the bats spec until Phase 59.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `anyhow`/`thiserror` are the right error crates for bin/core | Standard Stack | Low — swappable; only affects error ergonomics, not parity |
| A2 | `serde`/`serde_json` model CatalogEntry/Sentinel cleanly | Standard Stack | Low — shapes are simple JSON; TS types are the reference |
| A3 | `rust/` (not `plugin/rust/`) is the better home | Project Structure | Low/Medium — a layout call; either works, planner should lock one |
| A4 | node-semver excludes prereleases from non-prerelease ranges identically to Rust | Parity | Low — Rust side probed true; node side is documented behavior, not re-run this session (deps uninstalled) |
| A5 | crt-static is the musl default for a pure-Rust tree (belt-and-braces flag set anyway) | CI | Low — flag makes it explicit; `ldd` assertion is the real gate |
| A6 | RUST-02 "Docker matrix" is satisfied by adding the rust job to test.yml (option a) | CI | Medium — planner should confirm reading (a) vs (b); (a) meets the literal checkbox, (b) is Phase-59 endgame |

## Open Questions (RESOLVED)

> Resolved during planning (plan-checker APPROVED 2026-07-28). Each resolution is
> carried in both PLAN.md files' "Resolved decisions (from research open questions)"
> section: Q1 → literal reading (separate gated `rust` job on every PR; per-distro
> in-container musl build deferred to Phase 59/GATE-02); Q2 → keep both CANONICAL_PATHS
> maps in sync, delete-from-bash/TS deferred to Phase 57; Q3 → full node-semver
> prerelease audit is TEST-04 (Phase 54); the spike covers only the catalog's current ranges.

1. **RUST-02 "added to the Docker matrix" — literal or endgame?** → RESOLVED: literal.
   - Known: the roadmap/REQUIREMENTS say "the Rust job is added to the Docker matrix."
   - Unclear: whether the spike must build the musl binary *inside* each bats-docker container, or
     just add a separate `rust` job that runs on every PR.
   - Recommendation: add the `rust` job (option a) for the literal checkbox + mount one musl artifact
     into the targeted bats containers for the ported surface; defer per-distro in-container builds to
     Phase 59 (GATE-02). Planner should confirm.
2. **Does the spike delete the duplicated CANONICAL_PATHS from bash/TS, or keep both in sync?**
   - Known: consolidation is scoped to Phase 57 (Deferred Ideas).
   - Recommendation: KEEP both maps in sync this phase (the reuse-unit's copy may also live in Rust);
     do not delete from `detect.ts`/`agents.sh` yet — that risks a wider behavior change than a spike wants.
3. **Node-semver prerelease parity edge cases beyond the catalog's current ranges** — the full audit is
   TEST-04 (Phase 54). The spike only needs the ranges the catalog uses today (caret + one compound).

## Sources

### Primary (HIGH confidence)
- Empirical Rust `semver 1.0.28` probe (this session) — caret/compound/prerelease/maxSatisfying/parse-strictness table
- `cargo`/`rustc` 1.97.1, musl target, musl-gcc, clippy, rustfmt versions (this session)
- Repo source: `plugin/cli/src/version/classify.ts`, `plugin/cli/src/upgrade/divergence.ts`,
  `plugin/lib/reuse/agents.sh`, `plugin/lib/reuse.sh`, `plugin/lib/remediate.sh:288`,
  `plugin/cli/src/detect.ts:16,28`, `tests/bats/13-reuse.bats`, `plugin/cli/test/{classify,divergence}.test.ts`,
  `.github/workflows/test.yml`, `plugin/catalog/**` (constraint grep), `plugin/provisioner/30-nodejs.sh`
- `docs/research/v0.3.0/stack-reconsideration.md` (the settled decision + accepted costs)
- `.planning/REQUIREMENTS.md` (RUST/GATE), `.planning/ROADMAP.md` (Phase 53 success criteria)

### Secondary (MEDIUM confidence)
- crates.io `cargo search` versions for proptest/schemars/clap/cargo-mutants (this session)
- MEMORY.md reference_docker_oom (full Docker bats suite OOMs mid-run in this VM)

### Tertiary (LOW confidence)
- node-semver prerelease/`v`-prefix/`valid` behavior stated from documented semantics — node deps
  were not installed this session to re-run (Rust side WAS probed empirically); confirm in Phase 54's TEST-04 audit

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — toolchain + crate versions verified this session
- Architecture / seam: HIGH — `reuse::agent_decision` single call site + bats invocation cited from source
- semver parity: HIGH on the Rust-side divergences (empirically probed); MEDIUM on node-side exactness (documented, not re-run)
- CI: HIGH on the flags/target (musl-gcc + target present); MEDIUM on the RUST-02 "Docker matrix" reading (Open Q1)
- Pitfalls: HIGH — the top two are empirically demonstrated parse failures

**Research date:** 2026-07-28
**Valid until:** ~2026-08-27 (stable toolchain; re-verify crate versions if the spike slips a month)
