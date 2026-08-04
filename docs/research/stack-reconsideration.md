# Stack Reconsideration — should AgentLinux move off JS + Bash?

**Question:** Code review surfaced that two stability practices — mutation testing
and property-based testing — are hard to apply here, and that carrying two
languages (TypeScript/Node + Bash) forces us to keep values in sync by hand. Did
we pick the wrong stack? Would Rust (or Go) have been better, and is a migration
worth it now?

**Researched:** 2026-07-26 · **Decision recorded:** 2026-07-27
**Scope:** the registry CLI (`product/plugin/cli/`, ~2,800 LOC TS) and its Bash boundary
(`product/plugin/lib/`, `product/plugin/provisioner/`, `product/plugin/catalog/agents/*/install.sh`).
Paths are the pre-rewrite tree; all but the per-agent recipes are gone now.
**Candidates evaluated:** Rust, Go, "stay on TypeScript, shrink Bash," and a
fourth surfaced mid-review — "stay TS, expand into the provisioner, ship a
runtime-bundled binary" (Bun/Deno/SEA). (Python was considered and dropped by
the owner.)
**Decision:** **Rust** (owner, 2026-07-27).
**Confidence:** HIGH on the diagnosis and the tooling facts; MEDIUM on the
migration-cost estimates.
**Status:** executed on the Rust-rewrite branch (unmerged at time of writing) —
the registry CLI and the provisioner were reimplemented as a single static musl
binary. Deleted: the TypeScript CLI and the ~4.3k LOC of provisioner Bash. The
~27 per-agent `install.sh` recipes stay Bash by design, exactly as the TL;DR
below argues they must in any language. The behavior-level bats suites were
re-pointed at the new binary and stayed green; the Bash-unit fixtures that
sourced the deleted libraries were removed, their logic having moved into
`agentlinux-core`.

---

## TL;DR

The pain is real, but the diagnosis "we picked the wrong language" is **partly
misattributed**. The question bundles two separable problems, and neither is
primarily solved by *which* language the CLI is written in:

1. **Cross-language value sync** — root cause is **logic split across the
   TS↔Bash boundary**, not the choice of TS. Bash can't evaluate semver, so the
   reuse/version decision leaks into two languages and a canonical-path map is
   hand-synced byte-for-byte. The fix is **consolidating logic out of Bash**,
   which is achievable in the current stack.
2. **Mutation / property testing is hard** — on the TS side this is *unadoption*,
   not a block: `fast-check` ≈ `proptest` and StrykerJS ≈ `cargo-mutants` are
   peer-class, just not wired up. The real black hole is **Bash** — and not only
   the recipes: **~4,363 LOC of branch-heavy provisioner Bash**
   (`agentlinux-install`, `detect/`, `remediate/`, `idempotency`, …) carries
   parsing, `mapfile`, and conditional reconciliation that *no* Bash tool can
   mutation- or property-test. Making that logic testable means moving it into a
   typed language — and here is the asymmetry that reshapes the decision:
   **a plain Node *script* cannot do it.** The provisioner runs *before Node
   exists* (its job is to install Node), so only a binary that runs on a bare box
   can absorb it — a **compiled static binary** (Rust/Go) *or* a **runtime-bundled
   JS binary** (the fourth option). This — not "a cleaner artifact" — is the single
   strongest argument for a rewrite.

A rewrite still **cannot** remove the irreducible boundary: the CLI will always
shell out to the ~25 per-agent `install.sh` recipes (npm/apt/curl glue) through an
untyped env-var contract, in **any** language. But that boundary is thin; the
~4.3k LOC of provisioner logic behind it is not.

**Recommendation → Decision (2026-07-27):** the analysis pointed to a **compiled
rewrite as the destination** (it is the only path that makes the provisioner logic
testable), with **Rust and Go both live** on a real tension — Go owns the
provisioner's subprocess ergonomics + cheaper agent loops; Rust owns
mutation-testing rigor, compile-time safety, the schema-drift-airtight `schemars`
path, and the compiler-as-reviewer loop that suits this project's review culture.
**The owner chose Rust.** Step 1's cheap in-place fixes still run first as the
bridge; the spike (previously a *gate on the language*) becomes the **first
de-risking step of the Rust migration**.

---

## What the code actually shows (grounding)

### The sync pain is logic-split, in the authors' own words

`product/plugin/lib/reuse/agents.sh` implements the reuse decision as three
predicates, but stops after two, with this comment (lines 10-13):

> Predicate 3 is NOT done here — semver-range satisfaction is non-trivial in
> bash. The CLI (product/plugin/cli/src/detect.ts …) runs semver.satisfies() …

and hand-maintains a path map that **must** match the TS side (lines 27-28):

> Canonical binary path map — MUST stay byte-identical to the CANONICAL_PATHS
> object in product/plugin/cli/src/detect.ts (drift flips reuse→remediate).

So `CANONICAL_PATHS` is duplicated in `detect.ts:16` and `reuse/agents.sh:31`;
`GSD_SYSTEM_PATH` in `detect.ts:28` and `reuse/agents.sh:41`. The **cause** is
that Bash can't do semver, so the decision was split — not that TS is the wrong
language. Consolidating detection into the CLI removes the duplication regardless
of language.

### The provisioner Bash is heavy logic, not glue

The `.deb`/curl bootstrap fans out into **~4,363 LOC of provisioner-side Bash**
(`product/plugin/bin/agentlinux-install` + `product/plugin/lib/**` + `product/plugin/provisioner/**`,
excluding recipes) — and it is *branch-dense decision logic*, not thin idempotent
glue. `agentlinux-install` alone has ~47 branch-lines and uses `mapfile` in 615
LOC; `detect/agents.sh`, `remediate.sh`, `idempotency.sh`, `detect/render.sh`, and
`detect/nodejs.sh` each carry 15-31 branch-lines of version parsing, path
resolution, and reconciliation. This is exactly the logic that most wants
property/mutation testing — and it has none, because Bash has none.

The decisive constraint: this logic **cannot move to the TS CLI**, because the
provisioner runs *before Node exists* (it installs Node). Only a compiled binary
that runs on a bare box can absorb it. That is why "dependency-free binary" is not
a cosmetic win — it is the *enabler* for making ~4.3k LOC of today-untestable logic
testable. Truly-irreducible Bash then shrinks to a ~5-line postinst stub that
`exec`s the binary plus a ~30-line curl→.deb bootstrap.

### The irreducible boundary: 6 env vars → 25 shell recipes

`runner.ts` hands recipes six untyped `AGENTLINUX_*` strings —
`PINNED_VERSION`, `CATALOG_DIR`, `AGENT_HOME`, `SOURCE_KIND`, `INSTALL_LOG`,
`PRESERVE_PATHS` (`runner.ts:106-111`) — which each `install.sh` reads as bare
strings (`: "${AGENTLINUX_PINNED_VERSION:?…}"`) before shelling out to
`npm install -g`, apt, curl. `codex/install.sh` is representative: 126 lines of
idempotent glue (npm install, `apt-get install bubblewrap`, atomic TOML
patching). Rewriting *that* in Rust/Go would be strictly worse, and it keeps the
env-var contract alive. **This boundary survives any rewrite** — confirmed across
the 25 shipping recipes (the 27 `install.sh` files under `agents/*/` minus
`_template` and `test-dummy`; the catalog has 26 entries, some MCP-type sharing a
recipe rather than owning one).

### Testing is unadopted, not blocked

- `product/plugin/cli/stryker.config.json` exists (advisory, thresholds 85/60/0) but
  `@stryker-mutator/*` is **not in `devDependencies`** — mutation testing is
  configured on paper and not actually installed.
- `fast-check` appears **nowhere** in the repo.
- There is a clean pure-logic core tailor-made for property testing — a ~190 LOC
  I/O-free trio (`version/classify.ts`, the six-state classifier;
  `upgrade/divergence.ts`, `computeDivergence` + `resolveLatestFor`/`maxSatisfying`;
  `catalog/category.ts`) plus the pure gate helpers inside `detect.ts` (the file
  also does I/O, so only its gate functions count) — already unit-tested via DI.
- The ~11k LOC of `product/tests/bats/` behavior contracts are the **only** rigor
  available to the Bash layer; bats-core + shellcheck is the ceiling there.

### One under-appreciated asset

The bats suite asserts **observable system state**, not implementation (ADR-002).
It is therefore a **language-agnostic executable spec**: a CLI rewritten in any
language can be validated against the existing suite. That materially de-risks a
migration — but it validates *installer behavior*, not the CLI's internal pure
logic, which would need its own ported tests.

---

## Per-dimension comparison (sourced)

### 1. Testing tooling (the original motivation) — weight: HIGH

| | Property-based | Mutation |
|---|---|---|
| **Rust** | `proptest` 1.11 — integrated shrinking, actively maintained ([vs-quickcheck][pt]) | `cargo-mutants` 27.1 — zero-config, stable Rust, `--in-diff` CI ([mutants.rs][cm]) |
| **TS/Node** | `fast-check` 4.9 — ~29M dl/wk, first-class `node:test` ([fast-check.dev][fc]) | StrykerJS 9.6 — mutation-switching, `--incremental`, `thresholds.break` gate ([stryker][sj]) |
| **Go** | `pgregory.net/rapid` — good, but stdlib `testing/quick` is **frozen** ([pkg.go.dev][tq]) | **genuinely weak** — gremlins/ooze all pre-1.0, single-maintainer; gremlins self-admits it doesn't scale ([gremlins][gr]) |
| **Bash** | none exists ([confirmed][pbt]) | none exists ([awesome-mutation-testing][amt]) |

**Key finding:** Rust's mutation-testing edge over StrykerJS is **marginal, not
categorical** — they are peer ecosystem leaders with no evidence either is faster
or catches more bugs; the difference is philosophy (zero-config vs feature-rich)
([Thoughtworks Radar][tw]). Property testing is a genuine tie (`fast-check` ≈
`proptest`). **Go would be a *downgrade* on mutation testing** — a real strike,
given testing rigor was the motivating concern. And **no** language switch helps
Bash except by removing logic from it.

→ *For the **CLI layer**, adopting `fast-check` + wiring up the already-present
StrykerJS captures most of what a rewrite would. But it reaches **0%** of the
~4.3k LOC provisioner layer, which no in-place TS change can test (it runs
pre-Node) — see §"The provisioner Bash is heavy logic". That layer is the
rewrite's real prize.*

### 2. Cross-language sync & schema drift — weight: HIGH

- The catalog schema (`product/plugin/catalog/schema.json`, hand-written 2020-12) and
  `types.ts` `CatalogEntry` are **two hand-maintained artifacts** — ajv validates
  against the schema but does not generate it from the type, so they can drift.
- **Rust `schemars`** is the most airtight: `#[derive(JsonSchema)]` makes the type
  the single source of truth ([schemars][sc]). **But TS is not stuck with drift**
  — `typebox` / Zod v4 (native JSON-Schema output) / `ts-json-schema-generator`
  give define-once → type + schema **without a rewrite** ([typebox][tb]). Go's
  `invopop/jsonschema` (reflection over struct tags, v0) is the weakest.

**Key finding:** schema-drift-elimination is a **tooling choice, not a language
choice.** It weakens "rewrite to fix drift" — the same fix is available in place.
The env-var recipe contract can likewise be **generated** from a typed source in
any of the three languages (codegen, not a language property).

### 3. Distribution & runtime footprint — weight: MEDIUM

The authoritative release channel is the **curl-installer + tarball + `.sha256`**
(`product/scripts/build-release.sh`, `product/packaging/curl-installer/`), *not* a `.deb` — the
fpm `.deb` is **optional** per ADR-006 and is `Architecture: all` today only
because the payload is bash + a Node *script*. So the real axis is "how many
tarballs + how smart the installer," not "deb arch":

| | Artifact | Runtime deps on fresh box | Release tarball(s) |
|---|---|---|---|
| Rust (musl) | ~3-6 MB static | **none** | per-arch + arch-detecting installer |
| Go (CGO=0) | ~2-3 MB static | **none** | per-arch + arch-detecting installer |
| Node script (current) | tiny + `node_modules` | **Node + modules** | **one arch-neutral tarball** |
| Bundled-JS binary (Bun/Deno/SEA) | 40-110 MB | none (embedded) | per-arch, heavy |

Sources: [Go static][gostatic], [Rust musl][rustmusl], [Node SEA][sea] (still
"active development"; `vercel/pkg` is [archived][pkg]), [Debian arch][deb];
distribution reconciled against ADR-006 + `product/scripts/build-release.sh`.

**Key findings:** (a) any **binary** (compiled *or* runtime-bundled JS) is
arch-specific → **per-arch tarballs + an arch-detecting curl-installer**, where
today's Node-script artifact is a single arch-neutral tarball; (b) **correction to
an earlier claim:** a *runtime-bundled* JS binary (Bun/Deno/SEA) is **not**
pointless — bundling the runtime lets a JS binary run *pre-Node* too, so it can
also absorb the provisioner logic and make it testable *in TS* (this is the
"fourth option"; its costs are 40-110 MB, per-arch, an experimental/second
runtime, and **no compile-time safety**); (c) the **chicken-and-egg** — a CLI
whose job is partly to install Node can't itself need Node to run — is what lets
*any* binary absorb the ~4.3k LOC of pre-Node provisioner logic (grounding §"The
provisioner Bash is heavy logic"), which a plain Node *script* structurally
cannot. Cold start favors native (Rust ~21 ms / Go ~40 ms / Node ~130 ms,
[directional][cold]); a bundled-JS binary still pays JS-VM startup.

### 4. Ecosystem fit — weight: MEDIUM

- **Semver parity:** the live catalog uses only caret (`^2.1`) and compound
  comparators (`>=2.0.0 <3.0.0`) — no `||`/hyphen. All five node-semver APIs the
  CLI uses port cleanly to Rust `semver`; Go `Masterminds/semver` has broader
  syntax but a different prerelease-opt-in model to audit ([Masterminds][ms]).
  Both viable; **Rust is the closer semantic match** to node-semver's prerelease
  rule.
- **Subprocess orchestration:** Go wins on ergonomics — `exec.CommandContext` +
  `Cmd.WaitDelay` gives **built-in** SIGTERM→SIGKILL escalation
  ([os/exec][osexec]); Rust and Node hand-roll it (as the current
  `dispatcher.ts` already does). Nice-not-necessary.
- **CLI framework:** `clap` / `cobra` / `commander` all mature at ~10 verbs — a
  wash; only clap+cobra ship built-in shell completions, commander does not.

### 5. Contributors, safety, author fit — weight: MEDIUM

- Available pool (SO 2025 "used past year"): **TS 43.6% > Go 16.4% > Rust 14.8%**
  ([SO 2025][so]). Rust is #1 *most admired* but admired ≠ available.
- Compile-time safety: **Rust > Go > TS** (TS types are unsound-by-design and
  runtime-erased; Go keeps `nil`).
- Infra/DevOps center of gravity is **Go** (Docker/K8s/Terraform/`gh`); Rust is
  the rising CLI-tooling language (uv, ruff, ripgrep). A **CloudLinux/C systems
  engineer largely neutralizes Rust's learning-curve penalty**.

### 6. Performance & indexing — weight: MEDIUM (rising)

An honest reading: today's hot path (`agentlinux list` re-probing installed
versions) is **I/O-bound, not CPU-bound** — dominated by spawning `npm ls -g` /
`<bin> --version` and stat-ing files, which costs the same in Node, Go, or Rust. A
blanket "JS is slow" claim would not survive scrutiny here.

But three *language-sensitive* costs are real and all point one way:
- **Cold-start tax.** A frequently-run `list` pays Node's ~130 ms V8 startup
  *every* invocation vs ~20-40 ms native ([cold][cold]) — the recurring cost of a
  status command.
- **Out-of-band drift + indexing.** Making `list` always-fresh despite updates
  applied outside AgentLinux means a persistent, invalidated **index/cache**. (The
  drift *state* already exists — `classify.ts` returns `drift-undeclared` when
  sentinel ≠ installed; the gap is re-probing reality cheaply and caching it.) A
  long-lived, memory-resident index is cleaner and cheaper in a compiled binary
  than in a cold-started Node script.
- **Parallel probing.** Fanning N version-probes out concurrently with bounded
  parallelism + timeouts is more ergonomic in Go (`errgroup`/context) or Rust
  (tokio) than Node's callback/AbortController model.

**Key finding:** performance is a *secondary* driver but a genuine one, and it
reinforces the same direction (compiled) via cold-start, index-friendliness, and
concurrency — not via raw throughput.

### 7. AI-agent coding competence — weight: MEDIUM (the work is agent-driven)

The rewrite is done largely by coding agents (Claude), so agent competence per
language matters. The evidence **splits by task type** — the ranking flips:

| Task shape | Ordering | Source |
|---|---|---|
| Short single-function completion | **TS > Rust > Go** | MultiPL-E ([StarCoder2][mpe]) |
| Build a small program end-to-end (real Claude Code) | **Go > Rust > TS** — all pass; Go cheapest/fastest | Endoh, 40 runs/lang ([endoh][endoh]) |
| Resolve real multi-file GitHub issues | **Rust > TS > Go** (58% / 35% / 31%) | SWE-bench Multilingual, Claude 3.7 ([swe-ml][sweml]) |
| Same, harder harness | **Rust ≥ TS > Go** (all low) | Multi-SWE-bench ([mswe][mswe]) |

Cross-cutting:
- **Training corpus:** JS/TS ≫ Go (~55 GB) ≫ Rust (~16 GB) ([The Stack v2][stack])
  — yet Rust *overperforms* its tiny corpus on real agentic tasks, credited to the
  compiler giving agents structured, iterable errors.
- **Static typing helps an agent that runs the compiler in its loop** (TS beats JS
  on the same repos) — and this project's review/CI culture guarantees that loop.
- **Claude-specific Rust costs:** worst measured crate-hallucination (Opus 4 ~27%,
  [halluc][halluc]); slower/pricier loops (Endoh); an open Claude Code bug where
  slow `cargo` compiles time out ([cc-timeout][ccto]).
- **The "compiler-as-reviewer" thesis** (Anthropic's Schrittwieser: Rust lets
  Claude work unsupervised, [sw][sw]) is real but *tactical* — repair data plateaus
  on ownership/new-logic, and Anthropic's own 100k-LOC-Rust project credited the
  test harness, not the type system ([acc][acc]).
- **Meta-signal:** Claude Code is itself TS/Bun; Codex rewrote TS→Rust for a
  hardened binary ([codex-rust][cxr]).

**Key finding:** this dimension does *not* by itself pick Rust — Go is
cheaper/more predictable for the build-out and the community "LLM-friendly"
favorite, while Rust leads the *maintenance*-shaped benchmarks and pairs with the
compiler-as-reviewer loop this project runs. **Caveat: every Claude datapoint is
3.7 Sonnet — no per-language Opus/Sonnet 4.x data exists.** → the spike must
instrument iterations-to-green, token cost, and hallucination/timeout friction on
*our* code with *our* model.

---

## The honest scorecard

| Motivation for a rewrite | Does a rewrite actually fix it? |
|---|---|
| **Provisioner logic testable** | **Only via a self-contained binary** — ~4.3k LOC of pre-Node Bash can move into a tested language only inside a binary that carries its own runtime (compiled Rust/Go, or a bundled-JS binary); a plain Node *script* can't cross the chicken-and-egg. The biggest gain, and the one this analysis first under-weighted. |
| Mutation/property testing (CLI layer) | **In place** — TS tooling is peer-class and unadopted, not blocked. Rust's mutation edge is marginal; **Go is worse** on mutation. |
| Cross-language value sync | **Partially** — consolidating logic out of Bash fixes most of it *in TS today*; the env-var recipe boundary survives any rewrite. |
| Schema drift | **No (language-wise)** — fixable in place with typebox/Zod-v4; Rust `schemars` is airtight but not uniquely so. |
| **Node-runtime dependency for the CLI** | **Yes** — a static Rust/Go binary removes it (the cleanest genuine win). |
| **Compile-time safety** | **Yes** — Rust > Go > TS is a real, permanent gain. |
| Subprocess ergonomics | **Marginally** — Go's built-in kill-escalation; already solved in TS. |

The CLI-layer pains (testing adoption, sync, drift) are mostly addressable without
a rewrite. But the **largest** prize — making the ~4.3k LOC of provisioner logic
testable — is reachable *only* by a compiled binary, since TS is trapped behind the
Node chicken-and-egg. That reframes a rewrite from "optional cleanup" to "the only
route to the biggest testability gain."

---

## Recommendation

### Step 1 — fix in place first (do this regardless; ~1-2 weeks, reversible)

1. **Adopt property testing now.** Add `fast-check`; write invariants for the
   pure core (`classify` is total and deterministic; `sticky ⇒ status ∈
   {synced, pinned-override}`; `resolveLatestFor` output always satisfies the
   constraint or throws). ~300-400 generated cases over the ~190 LOC pure core.
2. **Actually install + gate StrykerJS** on the pure-logic files only (it's
   already configured); promote from advisory once the score is known.
3. **Consolidate the reuse/version decision into the CLI.** Make Bash detection
   emit raw facts only; delete the duplicated `CANONICAL_PATHS` / `GSD_SYSTEM_PATH`
   from `reuse/agents.sh`. This removes both duplications outright.
4. **Kill schema drift** with typebox or Zod v4 (type → 2020-12 schema, one
   source), replacing the hand-written `schema.json`.
5. **Generate the env-var contract** (the six `AGENTLINUX_*` names) from one typed
   definition consumed by both `runner.ts` and a manifest the recipes source, so
   a rename can't silently desync CLI and recipes.

Then **measure** the residual pain over a milestone.

### Step 2 — the Rust rewrite (chosen 2026-07-27)

Step 1 leaves the ~4.3k LOC of provisioner logic untestable — a plain TS script
can't reach it. Making that logic testable is the original motivation, so a binary
rewrite is the route, and **the owner chose Rust**. Scope: ~2,800 LOC CLI **plus**
~4,363 LOC provisioner (recipes stay Bash) ≈ **~7k LOC** to port behind the
language-agnostic bats spec.

Why Rust over Go and over the fourth (bundled-JS) option:

- **vs Go** — Go owns subprocess ergonomics + cheaper agent loops, but its
  **mutation testing is genuinely weak** (no maintained tool with coverage-guided
  test selection), undercutting the exact practice that motivated this. Rust brings
  peer-class mutation testing (`cargo-mutants`), airtight `schemars` schema-gen,
  strongest compile-time safety on privileged code, semver semantic match, and the
  compiler-as-reviewer loop that suits this project's review culture; the owner's
  systems background neutralizes the curve.
- **vs bundled-JS binary** — that option reaches provisioner testability without
  leaving TS (cheapest migration), but stops at TS's ceiling: **no compile-time
  safety** on root-adjacent code, a 40-110 MB per-arch artifact, and a bet on
  SEA/a second runtime. Rust was judged worth the larger rewrite for the safety +
  footprint.

Accepted costs (to manage in the milestone): Rust's worst-in-class Claude
crate-hallucination rate, slower/pricier agent loops + `cargo`-timeout friction,
the musl cross-toolchain + per-arch tarballs, and the smaller contributor pool.

**First step of the migration is the spike** (a de-risking step now, no longer a
gate): port `classify.ts` + `divergence.ts` **and** one gnarly provisioner unit
(e.g. `detect/nodejs.sh` or the npm-prefix reconciliation) to Rust behind the
existing bats tests; instrument iterations-to-green, token cost, and
hallucination/timeout friction with the real Claude model. That converts the
MEDIUM migration-cost estimate into evidence before the bulk port.

The **bats spec is the safety net** (rewrite behind it, keep it green — nothing is
"done" until the full suite passes on the Rust build); the **per-agent
`install.sh` recipes stay Bash** (data + a thin escape hatch).

---

## Confidence & evidence gaps

| Claim | Confidence | Note |
|---|---|---|
| Testing tooling state (fast-check/proptest peer; Stryker/cargo-mutants peer; Go mutation weak; Bash none) | HIGH | Registry/GitHub/official-doc verified |
| Sync pain is logic-split, fixable by consolidation | HIGH | Grounded in source + code comments |
| Recipe env-var boundary survives any rewrite | HIGH | Verified across the 25 shipping recipes |
| Schema drift fixable in-place | HIGH | typebox/Zod-v4/ts-json-schema-generator verified |
| Distribution/arch facts | HIGH | Debian wiki + nodejs.org primary |
| Provisioner is ~4.3k LOC of branch-dense logic only a compiled binary can rescue | HIGH | LOC + branch counts measured; pre-Node constraint is structural |
| `list` perf is I/O-bound; language matters via cold-start/index/concurrency | MEDIUM | Reasoned from workload shape; cold-start numbers directional |
| Migration cost (~7k LOC: ~2.8k CLI + ~4.3k provisioner + test port) | MEDIUM | No rewrite spike run; the spike is the migration's first step |
| AI-agent competence ranking flips by task type (Rust leads maintenance, Go the build-out) | MEDIUM | Benchmarks disagree; all Claude data is 3.7 Sonnet, no 4.x per-language |
| Cold-start numbers | LOW | Single Lambda benchmark; directional |

**Gaps:** no published head-to-head cargo-mutants vs StrykerJS benchmark; no
rewrite spike to validate the cost estimate or surface porting surprises (e.g.
node-semver prerelease edge cases). A time-boxed Rust spike porting
`classify.ts` + `divergence.ts` **plus one provisioner unit** (per §"Step 2" —
the provisioner is the real unknown) behind the existing tests will convert the
MEDIUM cost estimate to HIGH — it is the migration's first step.

---

## Sources

- [proptest vs quickcheck][pt] · [cargo-mutants][cm] · [fast-check][fc] ·
  [StrykerJS][sj] · [Go testing/quick (frozen)][tq] · [gremlins][gr] ·
  [PBT for shell — none][pbt] · [awesome-mutation-testing][amt] ·
  [Thoughtworks Radar: cargo-mutants][tw]
- [schemars][sc] · [typebox][tb] · [Masterminds/semver][ms] · [Go os/exec][osexec]
- [Go static binaries][gostatic] · [Rust musl][rustmusl] · [Node SEA][sea] ·
  [vercel/pkg archived][pkg] · [Debian ArchitectureVariants][deb] ·
  [cold-start benchmark][cold] · [Stack Overflow Survey 2025][so]
- Agent competence: [MultiPL-E / StarCoder2][mpe] · [Endoh Claude Code by lang][endoh] ·
  [SWE-bench Multilingual][sweml] · [Multi-SWE-bench][mswe] · [The Stack v2][stack] ·
  [Rust crate hallucination][halluc] · [Claude Code cargo timeout][ccto] ·
  [Schrittwieser: Claude + Rust][sw] · [Anthropic C-compiler in Rust][acc] ·
  [Codex TS→Rust rewrite][cxr]

[pt]: https://altsysrq.github.io/proptest-book/proptest/vs-quickcheck.html
[cm]: https://mutants.rs/
[fc]: https://fast-check.dev/docs/ecosystem/
[sj]: https://stryker-mutator.io/docs/stryker-js/incremental/
[tq]: https://pkg.go.dev/testing/quick
[gr]: https://github.com/go-gremlins/gremlins
[pbt]: https://shellspec.info/
[amt]: https://github.com/theofidry/awesome-mutation-testing
[tw]: https://www.thoughtworks.com/radar/tools/cargo-mutants
[sc]: https://github.com/GREsau/schemars
[tb]: https://github.com/sinclairzx81/typebox
[ms]: https://github.com/Masterminds/semver
[osexec]: https://pkg.go.dev/os/exec
[gostatic]: https://www.gofaq.org/en/how-to-build-static-binaries-in-go/
[rustmusl]: https://www.rustfaq.org/en/how-to-target-musl-for-fully-static-linux-binaries/
[sea]: https://nodejs.org/api/single-executable-applications.html
[pkg]: https://github.com/vercel/community/discussions/5353
[deb]: https://wiki.debian.org/ArchitectureVariants
[cold]: https://nebjak.dev/blog/benchmarking-aws-lambda-with-node-js-go-and-rust/
[so]: https://survey.stackoverflow.co/2025/technology
[mpe]: https://arxiv.org/pdf/2402.19173
[endoh]: https://dev.to/mame/which-programming-language-is-best-for-claude-code-508a
[sweml]: https://www.swebench.com/multilingual.html
[mswe]: https://arxiv.org/html/2504.02605
[stack]: https://arxiv.org/abs/2402.19173
[halluc]: https://arxiv.org/html/2606.08444v1
[ccto]: https://github.com/anthropics/claude-code/issues/5451
[sw]: https://www.julian.ac/blog/2025/05/03/claude-code-and-rust/
[acc]: https://www.anthropic.com/engineering/building-c-compiler
[cxr]: https://www.infoq.com/news/2025/06/codex-cli-rust-native-rewrite/

---
