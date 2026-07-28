# Roadmap

**Current milestone:** 🚧 **v0.4.0 Rust Rewrite** — IN PROGRESS (phases **53–59**). Reimplement the TypeScript registry CLI (~2,800 LOC) + the Bash provisioner (~4,363 LOC) as **one Rust static binary** (x86_64 musl), moving today's untestable Bash decision logic into a property- and mutation-tested language — while keeping the ~11k-LOC bats behavior contract green at every step and `master` shippable throughout. Like-for-like: **nothing observable changes for users**. Decision recorded 2026-07-27 in `docs/research/v0.3.0/stack-reconsideration.md` (Rust chosen over Go and a runtime-bundled-JS binary). Previous milestone **v0.3.6 Catalog Expansion** shipped as `v0.3.6-rc1` (2026-07-20); its content is preserved below.

## Current Milestone: v0.4.0 Rust Rewrite

**Milestone goal:** Make the ~7k LOC of CLI + provisioner logic **testable** by porting it into a single dependency-free Rust binary behind the language-agnostic bats spec (ADR-002). The pure decision core gets `proptest` property tests + a `cargo-mutants` gate; the catalog schema is generated from Rust types via `schemars` (kills drift); the provisioner logic that runs *before Node exists* finally lives in a language a mutation tester can reach. The ~25 per-agent `install.sh` recipes stay Bash behind a generated env-var contract. The rewrite lands on a **parallel track** so `master` stays shippable, with a per-phase rollback path.

**Prime directive (ADR-002):** the ~11k-LOC bats behavior suite is the executable spec and the acceptance oracle. **Nothing is "done" until the full bats suite is green on the Rust build.** Validation is **per-phase, first-class, not a final step**.

**Cross-cutting invariants (folded into EVERY phase's success criteria, not a standalone phase):**

- **GATE-01** — every phase ships behind a **green full bats suite** for the ported surface; no phase merges with a red or newly-skipped behavior test; no behavior-contract regression.
- **GATE-05** — `master` stays shippable throughout; the rewrite is a parallel track with a per-phase rollback path; a broken Rust phase never blocks a hotfix release from `master`.

> **Phase-numbering note (continue, not reset).** The previous milestone (v0.3.6 Catalog Expansion) ended at **phase 52**, so v0.4.0 phases start at **phase 53** and run **53–59** (7 phases). This continues the project's global phase counter per GSD convention. `project_code` is NOT part of the phase ID — phases are plain `Phase N` (config `phase_id_convention` absent → sequential).

### Phases

Execution is strictly sequential (53 → 59); the order respects the natural port dependency + de-risking sequence (spike first, testing bedrock next, then pure core → verbs → provisioner → distribution → full-matrix validation gate).

- [x] **Phase 53: Rust Scaffold + De-Risking Spike** - Stand up the cargo workspace + musl target + CI; port classify + divergence + one gnarly provisioner unit behind the existing bats tests; instrument agent-loop metrics. Establishes the GATE-01 / GATE-05 invariants. (completed 2026-07-28)
- [x] **Phase 54: Testing Bedrock** - proptest (property) + cargo-mutants (mutation gate on the pure core) + schemars schema-gen (kills catalog schema drift) + the node-semver → Rust `semver` parity audit — so the rigor exists before the bulk port. (completed 2026-07-28)
- [x] **Phase 55: Pure-Logic Core Parity** - Port classify/decide, computeDivergence + resolveLatestFor, detect gates, pin-spec parsing, and category derivation to Rust with verdicts identical to TS across a golden corpus. (completed 2026-07-28)
- [ ] **Phase 56: Registry CLI Verbs + Subprocess Dispatcher** - Port list/install/remove/upgrade/pin/adopt + the sudo-u/streaming-tee/timeout/SIGTERM→SIGKILL dispatcher + the generated env-var recipe contract; CLI-* bats green.
- [ ] **Phase 57: Provisioner Port + Logic Consolidation** - Port agent-user/sudoers/nodejs/path-wiring/registry-staging + detect/remediate/reuse/idempotency; delete duplicated CANONICAL_PATHS/GSD_SYSTEM_PATH from Bash; RT-*/AGT-*/DET-* bats green across all six invocation modes on Ubuntu + AlmaLinux.
- [ ] **Phase 58: Distribution — musl Tarball as Sole Channel** - Reproducible x86_64 musl static tarball + `.sha256` fetched/verified/installed by the curl-installer with no Node prerequisite; drop the legacy fpm `.deb` path; flag ADR-006 for update.
- [ ] **Phase 59: Full Validation Gate** - The complete bats contract green on the Rust build across the Docker matrix (Ubuntu 22.04/24.04/26.04 + AlmaLinux 9) AND QEMU; zero uncovered behavior families; the canonical AGT-02 self-update-without-sudo acceptance test green against the live Anthropic CDN.

## Phase Details

### Phase 53: Rust Scaffold + De-Risking Spike

**Goal**: Prove the Rust rewrite is viable end-to-end at small scale — a cargo workspace producing a static musl binary, wired into CI, with `classify` + `divergence` + one gnarly provisioner unit ported behind the existing bats tests and agent-loop cost instrumented — so the remaining port is calibrated by evidence, not estimate. This phase also establishes the two cross-cutting invariants (green-bats-per-phase, master-stays-shippable) that every later phase re-asserts.
**Depends on**: Nothing (first v0.4.0 phase; builds on the shipped v0.3.6 codebase + bats suite)
**Requirements**: RUST-01, RUST-02, RUST-03, GATE-01, GATE-05
**Success Criteria** (what must be TRUE):

  1. `cargo build --release --target x86_64-unknown-linux-musl` produces a single fully-static `agentlinux` binary — `ldd` reports "not a dynamic executable" (RUST-01).
  2. CI builds, `clippy`-lints, `rustfmt`-checks, and unit-tests the Rust binary on every PR; the Rust job is added to the Docker matrix (RUST-02).
  3. The spike ports `classify` + `divergence` + one gnarly provisioner unit (e.g. `detect/nodejs.sh` or npm-prefix reconciliation) to Rust; the **full bats behavior suite is green** on the Rust build for that ported surface, with **no newly-skipped tests** (RUST-03, GATE-01).
  4. Measured agent-loop metrics — iterations-to-green, token cost, cargo-timeout + crate-hallucination incidents — are recorded to calibrate the remaining port (RUST-03).
  5. The spike lands on a **parallel track**; `master` remains shippable and a per-phase rollback path exists (a broken spike never blocks a `master` hotfix) (GATE-05).

**Plans**: 2 plans

Plans:

- [x] 53-01-PLAN.md — Cargo workspace + static-musl build (RUST-01) + port classify/divergence + semver_shim into agentlinux-core with the TS golden corpus (RUST-03 pure core)
- [x] 53-02-PLAN.md — Port reuse::agent_decision behind the agents.sh shim + bats acceptance checkpoint (RUST-03 provisioner, GATE-01) + gated rust CI job (RUST-02) + 53-METRICS.md agent-loop cost & GATE-05 rollback note

### Phase 54: Testing Bedrock

**Goal**: Stand up the property + mutation + schema-generation + semver-parity machinery on the pure-logic core *before* the bulk port, so the practice that motivated the whole rewrite is operational — not aspirational — and every later port lands behind a real testing gate.
**Depends on**: Phase 53
**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04, GATE-01, GATE-05
**Success Criteria** (what must be TRUE):

  1. The pure-logic core has `proptest` property tests asserting its invariants — classify is total & deterministic; `sticky ⇒ status ∈ {synced, pinned-override}`; latest-resolution output always satisfies the constraint or returns a typed error (TEST-01).
  2. `cargo-mutants` runs on the pure-logic crate in CI and reports a mutation score gated at an agreed threshold (advisory → gate) (TEST-02).
  3. The catalog JSON Schema is generated from the Rust catalog types via `schemars` (single source of truth); CI fails if committed `schema.json` drifts from the generated output — schema drift check green (TEST-03).
  4. A `node-semver` → Rust `semver` behavior-parity audit documents every range/prerelease case the catalog uses, backed by a golden test asserting identical `satisfies`/`maxSatisfying`/`valid` verdicts on the current catalog (TEST-04).
  5. The **full bats behavior suite stays green** on the Rust build for the ported surface with **no behavior-contract regression and no newly-skipped tests** (GATE-01); `master` stays shippable with a rollback path (GATE-05).

**Plans**: 3 plans

- [x] 54-01-PLAN.md — proptest invariants (TEST-01) + node-semver parity audit doc & golden test (TEST-04) on the pure core; stages Cargo.toml deps [Wave 1]
- [x] 54-02-PLAN.md — schemars-generated catalog schema + drift-check, functional-equivalence gate keeping the 3 ajv consumers/12 fixtures green (TEST-03) [Wave 2]
- [x] 54-03-PLAN.md — cargo-mutants per-PR --in-diff gate in the guarded rust job + full-crate nightly score (TEST-02, GATE-05) [Wave 2]

### Phase 55: Pure-Logic Core Parity

**Goal**: Port the entire I/O-free decision core (six-state classification, divergence + latest-resolution, detect gates, pin-spec parsing, category derivation) to Rust with byte-for-byte-equivalent verdicts to the TS implementation across a golden corpus — the highest-value, most-testable slice, now guarded by the Phase 54 bedrock.
**Depends on**: Phase 54
**Requirements**: CORE-01, CORE-02, CORE-03, GATE-01, GATE-05
**Success Criteria** (what must be TRUE):

  1. Six-state version classification returns verdicts identical to TS `classify` across a golden corpus of `(sentinel, installed, pinned, sticky)` inputs (CORE-01).
  2. `computeDivergence` + `resolveLatestFor` (semver `maxSatisfying`) match TS outputs across the golden corpus, including the zero-match error path (CORE-02).
  3. Detect gates (reuse/remediate/presence), pin-spec parsing, and category derivation match TS outputs across the golden corpus (CORE-03).
  4. The ported core is exercised by the Phase 54 proptest + cargo-mutants gates (mutation score ≥ threshold on the pure core), and the **full bats suite is green** on the Rust build for the ported surface with **no newly-skipped tests** (GATE-01).
  5. `master` stays shippable throughout; the core port is reversible per-phase (GATE-05).

**Plans**: 3 plans

- [x] 55-01-PLAN.md — Extend semver_shim (valid/satisfies + golden) + types.rs (DetectedAgent/tags/source_kind/Category) — the wave-1 unblocker
- [x] 55-02-PLAN.md — Port category.rs + pin_spec.rs + detect_gates.rs, each with its verbatim TS golden corpus + proptests (CORE-03)
- [x] 55-03-PLAN.md — CORE-01/02 re-assert + fold in decide_version (5-row golden), closing the classify.test.ts corpus

### Phase 56: Registry CLI Verbs + Subprocess Dispatcher

**Goal**: Port the user-facing registry CLI — list/install/remove/upgrade/pin/adopt — plus the subprocess dispatcher and the typed env-var recipe contract, so `agentlinux <verb>` produces contract-equivalent stdout + exit codes to the TS CLI and the ~25 unchanged Bash recipes still run correctly against a single generated source of truth.
**Depends on**: Phase 55 (verbs consume the ported pure core)
**Requirements**: VERB-01, VERB-02, VERB-03, GATE-01, GATE-05
**Success Criteria** (what must be TRUE):

  1. `list / install / remove / upgrade / pin / adopt` produce contract-equivalent stdout + exit codes to the TS CLI — the existing `CLI-*` and `50-agents`/list/upgrade/pin bats tests are green on the Rust `list`/`install`/... (VERB-01).
  2. The subprocess dispatcher runs recipes as the target user (`sudo -u`), streams output (tee), enforces a timeout, and escalates SIGTERM→SIGKILL — the dispatcher/streaming behavior tests are green (VERB-02).
  3. The recipe env-var contract (the six `AGENTLINUX_*` names) is generated from a single typed Rust source, and the ~25 unchanged Bash recipes run correctly against it — a rename cannot silently desync CLI and recipes (VERB-03).
  4. The **full bats behavior suite is green** on the Rust build for the CLI surface with **no behavior-contract regression / no newly-skipped tests** (GATE-01).
  5. `master` stays shippable; the verb port is reversible per-phase (GATE-05).

**Plans**: 4 plans

- [x] 56-01-PLAN.md — Wave 0 scaffold: clap CLI skeleton + `RecipeEnv` typed source + the subprocess dispatcher (6-case parity) + the flag-gated Rust-bin bats staging override
- [x] 56-02-PLAN.md — Wave 1 read-only/state-only verbs: `list`/`pin`/`adopt` + the catalog/sentinel/cache/guard adapters (list+adopt green on 40-registry-cli vs the staged Rust bin; pin unit-green, bats-blocked only by the Plan-03 `install` setup fixture)
- [x] 56-03-PLAN.md — Wave 2 mutating verbs: `install`/`remove`/`upgrade` + probe/npm/rewire adapters (real recipe dispatch; VERB-02/03 end-to-end)
- [x] 56-04-PLAN.md — Wave 3 closeout: full CLI bats green on the Rust build + dispatcher-floor re-assert + Phase-59-deferred gated-case record (GATE-01/05)

### Phase 57: Provisioner Port + Logic Consolidation

**Goal**: Port the ~4.3k LOC of pre-Node provisioner logic — agent-user creation, sudoers drop-in, NodeSource Node, PATH/env wiring, registry-CLI staging, and the detect/remediate/reuse/idempotency decision layer — into the Rust binary, consolidating the duplicated Bash maps into a single Rust source of truth, with identical observable system state across all six invocation modes on both distro families.
**Depends on**: Phase 56 (provisioner stages the ported CLI binary; shares the dispatcher + pure core)
**Requirements**: PROV-01, PROV-02, PROV-03, GATE-01, GATE-05
**Success Criteria** (what must be TRUE):

  1. Provisioning (agent-user, sudoers, NodeSource Node, PATH/env wiring to `/etc/agentlinux.env`, registry-CLI staging) leaves the system in the same observable state as the Bash provisioner — the `RT-*` / `AGT-*` bats are green across all six invocation modes (interactive login, non-interactive SSH, cron, systemd `User=agent`, `sudo -u`, `sudo -u -i`) (PROV-01).
  2. Detect/remediate/reuse/idempotency logic is consolidated into the Rust binary; the duplicated `CANONICAL_PATHS` / `GSD_SYSTEM_PATH` maps are deleted from Bash (single source of truth in Rust) (PROV-02).
  3. Distro detection and the aware-install reuse/remediate/bail paths behave identically to today on Ubuntu 22.04/24.04/26.04 **and** AlmaLinux 9 — `DET-*` / `REUSE-*` / `REMEDIATE-*` bats green (PROV-03).
  4. The **full bats behavior suite is green** on the Rust build for the provisioner surface with **no behavior-contract regression / no newly-skipped tests** (GATE-01).
  5. `master` stays shippable; the provisioner port is reversible per-phase — a broken provisioner phase never blocks a `master` hotfix (GATE-05).

**Plans**: TBD

### Phase 58: Distribution — musl Tarball as Sole Channel

**Goal**: Ship the Rust binary through the curl-installer as the single distribution channel — a reproducible x86_64 musl static tarball + `.sha256`, fetched, verified, and installed with **no Node prerequisite for the CLI/provisioner itself** — and remove the legacy optional fpm `.deb` path entirely (the chicken-and-egg is gone).
**Depends on**: Phase 57 (the full binary — CLI + provisioner — must exist to package)
**Requirements**: DIST-01, DIST-02, GATE-01, GATE-05
**Success Criteria** (what must be TRUE):

  1. `scripts/build-release.sh` produces a reproducible x86_64 musl static tarball + `.sha256`; the curl-installer fetches it, verifies the sha256, and installs it — with **no Node prerequisite for the CLI/provisioner itself**; this is the **sole** distribution channel (DIST-01).
  2. The legacy optional fpm `.deb` path is removed — `packaging/deb/`, the `build-release.sh` `--deb`/`fpm` branch, and the `.deb` postinst bridge are deleted; ADR-006 is flagged for an update to the tarball-only channel (DIST-02).
  3. The **full bats behavior suite (incl. the curl-installer INST-* tests) is green** on the Rust build with **no behavior-contract regression / no newly-skipped tests** (GATE-01).
  4. `master` stays shippable; the distribution change is reversible per-phase (GATE-05).

**Plans**: TBD

### Phase 59: Full Validation Gate

**Goal**: Prove the rewrite is complete and behavior-preserving at full matrix scale — the entire bats behavior contract green on the Rust build across every supported distro on both Docker and QEMU, every behavior family still covered, and the canonical self-update-without-sudo acceptance test green against the live Anthropic CDN — so v0.4.0 can ship as a like-for-like reimplementation with zero observable change.
**Depends on**: Phase 58 (validates the fully-ported, distributed Rust build)
**Requirements**: GATE-02, GATE-03, GATE-04, GATE-01, GATE-05
**Success Criteria** (what must be TRUE):

  1. The complete bats behavior contract passes on the Rust build across the Docker matrix (Ubuntu 22.04/24.04/26.04 + AlmaLinux 9) **and** the QEMU release gate (GATE-02).
  2. Every existing requirement ID / behavior family (BHV/RT/AGT/CLI/CAT/INST/HRN/TST/DOC) retains behavior or harness evidence on the Rust build — `behavior-coverage-auditor` reports zero uncovered (GATE-03).
  3. The canonical acceptance test — agent `claude` self-update without sudo, zero EACCES — passes on the Rust build against the live Anthropic CDN (GATE-04).
  4. The whole-matrix run confirms **no behavior-contract regression / no newly-skipped tests** relative to the TS/Bash baseline (GATE-01).
  5. `master` is shippable at gate close — the Rust track is ready to become `master`, with the pre-cutover TS/Bash build retained as the rollback path (GATE-05).

**Plans**: TBD

## Progress (v0.4.0)

**Execution Order:** Phases execute strictly in numeric order: 53 (spike) → 54 (testing bedrock) → 55 (pure core) → 56 (CLI verbs) → 57 (provisioner) → 58 (distribution) → 59 (full validation gate).

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 53. Rust Scaffold + De-Risking Spike | 2/2 | ✅ Complete (verdict GO) | 2026-07-28 |
| 54. Testing Bedrock | 3/3 | ✅ Complete | 2026-07-28 |
| 55. Pure-Logic Core Parity | 3/3 | ✅ Complete | 2026-07-28 |
| 56. Registry CLI Verbs + Dispatcher | 2/4 | In progress | 56-01 (scaffold+dispatcher), 56-02 (list/pin/adopt + adapters) |
| 57. Provisioner Port + Logic Consolidation | 0/? | Not started | - |
| 58. Distribution — musl Tarball as Sole Channel | 0/? | Not started | - |
| 59. Full Validation Gate | 0/? | Not started | - |

## Current Milestone: v0.3.6 Catalog Expansion

**Milestone goal:** Grow the AgentLinux catalog from its 3 shipped entries (claude-code, gsd, playwright) with the most trusted/popular AI-agent-community tools — *availability only* (CAT-02 holds: nothing installed by default) — so first-release users don't hit "I miss tool X." A documented gates+scoring funnel (agent-relevance · clean per-user install + symmetric uninstall, no root, no `/usr/local` shim · free license · liveness ≤6mo release & ≤3mo commits · maturity) shortlisted **26 candidates**; **22 ship** after 4 in-flight drops (gitlab/brave failed the source-selection free-tier gate; claude-flow/bmad dropped on first-cohort demand — spec-kit/GSD cover that need).

**Structure (owner's always-shippable preference): ONE TOOL PER PHASE.** Each catalog phase ends with exactly one working, tested, installable+removable catalog entry. Phase 50 is the milestone-close integration-QA capstone and intentionally ships workflow machinery plus a recorded sweep, not a catalog entry. Phase 51 is the unified remediation follow-up for Phase 50's package findings and does not add a catalog entry. The 4 machinery enablers are **folded into their first-consumer phase** (marked 🔧): those phases deliver both the enabler *and* a working tool. Every entry carries ≥1 bats @test (catalog `install` → `post_install_verify` → symmetric `remove`, no residue) per the project's TST-07 phase-close gate; every tool is pinned per ADR-011 (pins in REQUIREMENTS.md Appendix A).

**Machinery tags:** `[npm]` global install via `as_user` (per-user npm prefix; pre-existing since v0.3.0) · `[bin]` prebuilt-binary fetch+checksum → `~/.local/bin` (ENABLE-01) · `[mcp]` `claude mcp add/remove --scope user` (ENABLE-02) · `[uv]` per-user `uv` bootstrap (ENABLE-03) · `[daemon]` per-user background service (ENABLE-04) · `[meta]` catalog-wide UX/contributor work.

> **Parallel-milestone note (numbering rationale — KEEP).** v0.3.5 (AlmaLinux 9 support, AL-64..68, Epic AL-48) is in flight on the **`worktree-almalinux-support`** branch and **owns phases 18–22**. Catalog Expansion was deliberately numbered **v0.3.6 / phases 23–49** so the two parallel milestones never collide on version *or* phase number at merge. Phases 18–22 are RESERVED for v0.3.5; do not reuse them here. PROJECT.md / MILESTONES.md / ROADMAP.md will need merge reconciliation between the two branches when both land.

### Phases

Execution is strictly sequential (23 → 51); each phase ships independently. 🔧 = also delivers a folded machinery enabler.

- [x] **Phase 23: codex** 🔧 `[npm]` - OpenAI Codex CLI + self-updater-coexistence enabler (ENABLE-05) ✓ COMPLETE
- [x] **Phase 24: antigravity-cli** `[bin]` - Google Antigravity CLI installable + removable ✓ COMPLETE (replaced sunset Gemini CLI)
- [x] **Phase 25: opencode** `[npm]` - opencode CLI installable + removable ✓ COMPLETE
- [x] **Phase 26: qwen-code** `[npm]` - Qwen Code CLI installable + removable ✓ COMPLETE
- [x] **Phase 27: ccusage** `[npm]` - read-only Claude cost reporter installable + removable ✓ COMPLETE
- [x] **Phase 28: rtk** 🔧 `[bin]` - Rust Token Killer + prebuilt-binary installer enabler (ENABLE-01)
- [x] **Phase 29: gh** `[bin]` - GitHub CLI installable + removable ✓ COMPLETE (also generalized the ENABLE-01 helper: GitHub+GitLab hosts, Go-style asset naming)
- [x] **Phase 30: glab** `[bin]` - GitLab CLI (gitlab-org/cli) installable + removable ✓ COMPLETE
- [x] **Phase 31: trivy** `[bin]` - Trivy scanner (no-Docker fs/repo scans) installable + removable ✓ COMPLETE
- [x] **Phase 32: gitleaks** `[bin]` - Gitleaks secret scanner installable + removable ✓ COMPLETE
- [x] **Phase 33: sentry-cli** `[npm]` - Sentry CLI (FSL) installable + removable ✓ COMPLETE
- [x] **Phase 34: chrome-devtools-mcp** 🔧 `[mcp]` - Chrome DevTools MCP + MCP-recipe-pattern enabler (ENABLE-02) ✓ COMPLETE
- [ ] **Phase 35: context7** `[mcp]` - Context7 MCP server registerable + deregisterable
- [ ] **Phase 36: github-mcp** `[mcp]` - GitHub MCP (remote-http/PAT or Go-binary stdio, never Docker)
- [ ] **Phase 37: sentry-mcp** `[mcp]` - Sentry MCP (npx+token or hosted OAuth; FSL)
- [ ] **Phase 38: gitlab-mcp** `[mcp]` - GitLab MCP registerable + deregisterable
- [ ] **Phase 39: brave-search-mcp** `[mcp]` - DROPPED 2026-07-14 (Feb-2026 free tier removed; mandatory card + metered billing) — MCP-06 deferred
- [x] **Phase 40: firecrawl-mcp** `[mcp]` - Firecrawl MCP registerable + deregisterable ✓ COMPLETE (hosted OAuth bare-URL, ADR-017 thin installer)
- [x] **Phase 41: slack-mcp** `[mcp]` - Slack MCP registerable + deregisterable ✓ COMPLETE (official first-party hosted `mcp.slack.com`, ADR-017 thin installer; supersedes the third-party stealth-token plan)
- [x] **Phase 42: linear-mcp** `[mcp]` - Linear MCP registerable + deregisterable ✓ COMPLETE (official first-party hosted `mcp.linear.app`, ADR-017 thin installer; free-tier confirmed; OAuth enabler already shipped in 36/37)
- [x] **Phase 43: jira-atlassian-mcp** `[mcp]` - Atlassian Rovo MCP registerable + deregisterable ✓ COMPLETE (official first-party hosted `mcp.atlassian.com`, ADR-017 thin installer; free-tier 500 calls/hr confirmed; cloud-only)
- [x] **Phase 44: spec-kit** 🔧 `[uv]` - GitHub Spec Kit + Python+uv-bootstrap enabler (ENABLE-03) ✓ COMPLETE (Docker 3/3; uv bootstrap + git-tag `uv tool install`; pin corrected 0.11.9→v0.12.11)
- [ ] **Phase 45: claude-flow** `[npm]` - DROPPED 2026-07-14 (maintainer: niche for the first-release cohort) — WORK-04 deferred
- [ ] **Phase 46: bmad** `[npm]` - DROPPED 2026-07-14 (maintainer: spec-kit/GSD cover the need, far more popular) — WORK-05 deferred
- [x] **Phase 47: openclaw** 🔧 `[daemon]` - OpenClaw + AI-assistant daemon-lifecycle enabler (ENABLE-04) ✓ COMPLETE (Docker 4/4; systemd-user QEMU-gated)
- [x] **Phase 48: hermes-agent** `[daemon]` - Hermes Agent (official installer pinned to commit + per-user daemon/gateway, reuses ENABLE-04) ✓ COMPLETE (Docker 3/3; systemd-user QEMU-gated)
- [x] **Phase 49: catalog growth kit** `[meta]` - `list` category/tags UX (ENABLE-06) + contributor template & selection-rubric doc (ENABLE-07)
- [x] **Phase 50: integration QA** 🧪 `[qa]` - build the reusable `qa-testing` skill (scoped · productive-time/latest-10 regression-to-zero stop condition · representative TUI session) AND run it as the milestone-close integration sweep across the co-installed catalog ✓ COMPLETE (2026-07-19; available-scope gate met; residual credential/OAuth/systemd boundaries documented; findings routed to Phase 51)
- [x] **Phase 51: unified integration-QA remediation** 🛠️ `[fix]` - fix all Phase 50 confirmed findings, known issues, and prerequisite boundaries; add regression coverage, re-run affected package workflows, and repeat the `qa-testing` sweep (completed 2026-07-19)

## Phase Details

### Phase 23: codex

**Goal**: Make codex (OpenAI Codex CLI) installable + removable via the catalog, AND deliver the self-updater-coexistence enabler (ENABLE-05).
**Depends on**: v0.3.0 catalog + registry CLI (shipped); npm install machinery (pre-existing). First v0.3.6 phase.
**Requirements**: AGT-07, ENABLE-05
**Machinery**: `[npm]` · 🔧 ENABLE-05 self-updater coexistence · pin `@openai/codex@0.142.3`
**Success Criteria** (what must be TRUE):

  1. `agentlinux install codex` installs `@openai/codex@0.142.3` as the agent user (no root, zero EACCES/permission-denied); `codex` resolves on PATH under the agent home (no `/usr/local` shim).
  2. ENABLE-05: codex's built-in self-updater does not silently clobber the pin — the in-app updater is disabled or documented, and AgentLinux's pinned version stays authoritative after a self-update attempt (re-exercises the AGT-02 canonical concern).
  3. Secrets are NOT baked — codex auth is supplied post-install (login/env), never in the recipe/snapshot.
  4. `agentlinux remove codex` is symmetric (npm global gone, no residue) and idempotent.
  5. ≥1 bats @test (install → version-pin verify → self-updater-coexistence → remove) is green — TST-07 phase-close gate.

**Plans**: TBD

### Phase 24: antigravity-cli

**Goal**: Make antigravity-cli (Google Antigravity CLI) installable + removable via the catalog, replacing the sunset Gemini CLI package.
**Depends on**: Phase 23 (catalog install lifecycle and self-updater-coexistence convention)
**Requirements**: AGT-06
**Machinery**: `[bin]` · pin `antigravity-cli@1.1.4`, bin `agy`, official SHA-512-verified Linux archive
**Success Criteria** (what must be TRUE):

  1. `agentlinux install antigravity-cli` installs Google's pinned 1.1.4 binary as the agent user (no root, zero EACCES); `agy` resolves under `~/.local/bin`.
  2. `post_install_verify` passes — `agy --version` reports the pinned `1.1.4`.
  3. Secrets are NOT baked — Google auth is supplied post-install.
  4. `agentlinux remove antigravity-cli` is symmetric and idempotent — no binary residue; `~/.gemini` user state is preserved.
  5. ≥1 bats @test covers install → verify → remove — TST-07 gate.

**Plans**: TBD

### Phase 25: opencode

**Goal**: Make opencode installable + removable via the catalog.
**Depends on**: Phase 24
**Requirements**: AGT-05
**Machinery**: `[npm]` · pin `opencode-ai@1.18.3`, bin `opencode`
**Success Criteria** (what must be TRUE):

  1. `agentlinux install opencode` installs `opencode-ai@1.18.3` as the agent user (no root, zero EACCES); `opencode` resolves on PATH.
  2. `post_install_verify` passes — the pinned `1.18.3` is the resolved version.
  3. Secrets are NOT baked — provider auth supplied post-install.
  4. `agentlinux remove opencode` is symmetric and idempotent — no residue.
  5. ≥1 bats @test covers install → verify → remove — TST-07 gate.

**Plans**: TBD

### Phase 26: qwen-code

**Goal**: Make qwen-code (Qwen Code CLI) installable + removable via the catalog.
**Depends on**: Phase 25
**Requirements**: AGT-08
**Machinery**: `[npm]` · pin `@qwen-code/qwen-code@0.19.2`, bin `qwen`
**Success Criteria** (what must be TRUE):

  1. `agentlinux install qwen-code` installs `@qwen-code/qwen-code@0.19.2` as the agent user (no root, zero EACCES); `qwen` resolves on PATH.
  2. `post_install_verify` passes — `qwen --version` reports the pinned `0.19.2`.
  3. Secrets are NOT baked — provider auth supplied post-install.
  4. `agentlinux remove qwen-code` is symmetric and idempotent — no residue.
  5. ≥1 bats @test covers install → verify → remove — TST-07 gate.

**Plans**: TBD

### Phase 27: ccusage

**Goal**: Make ccusage (read-only Claude cost reporter) installable + removable via the catalog.
**Depends on**: Phase 26
**Requirements**: WORK-01
**Machinery**: `[npm]` · pin `ccusage@20.0.14` · LICENSE shows GitHub `NOASSERTION` but is MIT (Appendix B)
**Success Criteria** (what must be TRUE):

  1. `agentlinux install ccusage` installs `ccusage@20.0.14` as the agent user (no root, zero EACCES); `ccusage` resolves on PATH.
  2. `post_install_verify` passes — the pinned `20.0.14` runs; it is read-only (no token/secret required — reads local Claude usage).
  3. `agentlinux remove ccusage` is symmetric and idempotent — no residue.
  4. ≥1 bats @test covers install → verify → remove — TST-07 gate.

**Plans**: TBD

### Phase 28: rtk

**Goal**: Make rtk (RTK / Rust Token Killer) installable + removable via the catalog, AND deliver the prebuilt-binary installer enabler (ENABLE-01).
**Depends on**: Phase 27. First consumer of the prebuilt-binary entry kind.
**Requirements**: WORK-02, ENABLE-01
**Machinery**: `[bin]` · 🔧 ENABLE-01 prebuilt-binary kind · pin `rtk-ai/rtk@0.42.4` (binary) · crates.io "Rust Type Kit" collision — source-pinned to `rtk-ai/rtk`, NEVER `cargo install rtk`
**Success Criteria** (what must be TRUE):

  1. ENABLE-01: the catalog supports a prebuilt-binary entry kind — `install` fetches the pinned `rtk-ai/rtk@0.42.4` release, verifies its checksum, and installs the binary to `~/.local/bin` (agent-owned, no root, no `/usr/local` shim).
  2. `agentlinux install rtk` resolves the correct upstream (`rtk-ai/rtk`) — NOT the crates.io "Rust Type Kit" collision (`cargo install rtk` is never used); `rtk --version` reports `0.42.4`.
  3. The optional `rtk init` hook into `~/.claude` is opt-in; `remove` reverts the binary AND the hook symmetrically (`--uninstall`) — no residue.
  4. `agentlinux remove rtk` deletes the binary + its config/cache symmetrically; idempotent.
  5. ≥1 bats @test (binary fetch → checksum → version → optional-hook → remove) is green — TST-07 gate.

**Plans**: 4 plans

Plans:

- [x] 28-01-PLAN.md — Add "binary" to the source_kind enum (schema.json + types.ts) + unit test
- [x] 28-02-PLAN.md — Shared prebuilt-binary helper (arch-detect + verify-before-extract + install + version-lock)
- [x] 28-03-PLAN.md — rtk recipe pair (install/uninstall) + catalog.json entry (source_kind binary, pin 0.42.4)
- [x] 28-04-PLAN.md — ENABLE-01/WORK-02/OPS-01 bats lifecycle test + docs/internals/catalog.md note

### Phase 29: gh

**Goal**: Make gh (GitHub CLI) installable + removable via the catalog.
**Depends on**: Phase 28 (ENABLE-01 prebuilt-binary kind)
**Requirements**: DEVT-01
**Machinery**: `[bin]` · pin `2.95.0` · removes `~/.config/gh`
**Success Criteria** (what must be TRUE):

  1. `agentlinux install gh` fetches + checksum-verifies the pinned `2.95.0` binary into `~/.local/bin` as the agent user (no root, zero EACCES); `gh --version` reports `2.95.0`.
  2. Secrets are NOT baked — `gh auth login` is run post-install by the user.
  3. `agentlinux remove gh` deletes the binary + `~/.config/gh` symmetrically; idempotent — no residue.
  4. ≥1 bats @test covers install → verify → remove — TST-07 gate.

**Plans**: TBD

### Phase 30: glab

**Goal**: Make glab (GitLab CLI) installable + removable via the catalog.
**Depends on**: Phase 29 (ENABLE-01 prebuilt-binary kind)
**Requirements**: DEVT-02
**Machinery**: `[bin]` · pin `1.105.0` · source `gitlab-org/cli` (NOT the archived `profclems/glab`) · removes `~/.config/glab`
**Success Criteria** (what must be TRUE):

  1. `agentlinux install glab` fetches the pinned `1.105.0` binary from `gitlab-org/cli` (NOT `profclems/glab`) into `~/.local/bin` as the agent user (no root, zero EACCES); `glab --version` reports `1.105.0`.
  2. Secrets are NOT baked — `glab auth login` is run post-install by the user.
  3. `agentlinux remove glab` deletes the binary + `~/.config/glab` symmetrically; idempotent — no residue.
  4. ≥1 bats @test covers install (correct upstream) → verify → remove — TST-07 gate.

**Plans**: TBD

### Phase 31: trivy

**Goal**: Make trivy (vulnerability/secret scanner) installable + removable via the catalog.
**Depends on**: Phase 30 (ENABLE-01 prebuilt-binary kind)
**Requirements**: DEVT-04
**Machinery**: `[bin]` · pin `0.71.2` · removes `~/.cache/trivy`
**Success Criteria** (what must be TRUE):

  1. `agentlinux install trivy` fetches + checksum-verifies the pinned `0.71.2` binary into `~/.local/bin` as the agent user (no root, zero EACCES); `trivy --version` reports `0.71.2`.
  2. `post_install_verify` passes — a `trivy fs`/repo scan runs with no Docker daemon required.
  3. `agentlinux remove trivy` deletes the binary + `~/.cache/trivy` symmetrically; idempotent — no residue.
  4. ≥1 bats @test covers install → no-Docker scan verify → remove — TST-07 gate.

**Plans**: TBD

### Phase 32: gitleaks

**Goal**: Make gitleaks (secret scanner) installable + removable via the catalog.
**Depends on**: Phase 31 (ENABLE-01 prebuilt-binary kind)
**Requirements**: DEVT-05
**Machinery**: `[bin]` · pin `8.30.1`
**Success Criteria** (what must be TRUE):

  1. `agentlinux install gitleaks` fetches + checksum-verifies the pinned `8.30.1` binary into `~/.local/bin` as the agent user (no root, zero EACCES); `gitleaks version` reports `8.30.1`.
  2. `post_install_verify` passes — `gitleaks` runs a scan on a sample repo/dir.
  3. `agentlinux remove gitleaks` deletes the binary symmetrically; idempotent — no residue.
  4. ≥1 bats @test covers install → verify → remove — TST-07 gate.

**Plans**: TBD

### Phase 33: sentry-cli

**Goal**: Make sentry-cli installable + removable via the catalog.
**Depends on**: Phase 32 (npm machinery, or ENABLE-01 binary path)
**Requirements**: DEVT-03
**Machinery**: `[npm]` (`@sentry/cli`, or binary) · pin `@sentry/cli@3.6.0` · **FSL-1.1-MIT** license — passes the "free to use" gate; flag in entry metadata if an OSI-only catalog is ever required (Appendix B)
**Success Criteria** (what must be TRUE):

  1. `agentlinux install sentry-cli` installs the pinned `@sentry/cli@3.6.0` as the agent user (no root, zero EACCES); `sentry-cli --version` reports `3.6.0`.
  2. The FSL-1.1-MIT license flag is recorded in the catalog entry (license-gate honesty).
  3. Secrets are NOT baked — `SENTRY_AUTH_TOKEN` is supplied post-install.
  4. `agentlinux remove sentry-cli` is symmetric and idempotent — no residue.
  5. ≥1 bats @test covers install → verify → remove — TST-07 gate.

**Plans**: TBD

### Phase 34: chrome-devtools-mcp

**Goal**: Make chrome-devtools-mcp registerable + deregisterable via the catalog, AND deliver the MCP-recipe-pattern enabler (ENABLE-02).
**Depends on**: Phase 33. First consumer of the MCP-server entry kind.
**Requirements**: MCP-01, ENABLE-02
**Machinery**: `[mcp]` · 🔧 ENABLE-02 MCP recipe pattern (npx-stdio + remote-http shapes; secret convention) · pin `chrome-devtools-mcp@1.4.0` · npx, no secret · requires Chrome present (documented)
**Success Criteria** (what must be TRUE):

  1. ENABLE-02: the catalog supports MCP-server entries — `install` registers via `claude mcp add --scope user` (npx-stdio shape working); entries declare `requires_secret`/`secret_env` and `install` prints a post-install token/login instruction (secrets never baked); `remove` deregisters via `claude mcp remove`.
  2. `agentlinux install chrome-devtools-mcp` registers the pinned `1.4.0` server (npx, no secret) — it appears in `~/.claude.json` / `claude mcp list`.
  3. The Chrome-present requirement is documented in the entry and surfaced by `install`.
  4. `agentlinux remove chrome-devtools-mcp` deregisters cleanly — no residue in `~/.claude.json`.
  5. ≥1 bats @test (register → `~/.claude.json` verify → deregister) is green — TST-07 gate.

**Plans**: TBD

### Phase 35: context7

**Goal**: Make context7 (Context7 MCP) registerable + deregisterable via the catalog.
**Depends on**: Phase 34 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-02
**Machinery**: `[mcp]` · pin `@upstash/context7-mcp@3.2.3` · npx · optional `CONTEXT7_API_KEY` per ENABLE-02
**Success Criteria** (what must be TRUE):

  1. `agentlinux install context7` registers the pinned `@upstash/context7-mcp@3.2.3` via `claude mcp add --scope user` as the agent user (no root, zero EACCES); it appears in `~/.claude.json`.
  2. The optional `CONTEXT7_API_KEY` is NOT baked — `install` prints the post-install instruction; the server works keyless by default.
  3. `agentlinux remove context7` deregisters symmetrically — no residue.
  4. ≥1 bats @test covers register → verify → deregister — TST-07 gate.

**Plans**: TBD

### Phase 36: github-mcp

**Goal**: Make github-mcp (GitHub MCP server) registerable + deregisterable via the catalog, with secret/PAT handling.
**Depends on**: Phase 35 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-03
**Machinery**: `[mcp]` · pin `github-mcp@1.5.0` · remote-http + PAT header, OR Go-binary stdio — **never** the Docker recipe
**Success Criteria** (what must be TRUE):

  1. `agentlinux install github-mcp` registers the GitHub MCP server (remote-http + PAT header, or Go-binary stdio — NEVER the Docker recipe) — it appears in `~/.claude.json`.
  2. The PAT is supplied post-install (`requires_secret`/`secret_env`) — never baked into the recipe/snapshot; `install` prints the token instruction.
  3. `agentlinux remove github-mcp` deregisters symmetrically — no residue, no leaked PAT.
  4. ≥1 bats @test (register, no-Docker shape → verify → deregister, secret-not-baked grep) is green — TST-07 gate.

**Plans**: TBD

### Phase 37: sentry-mcp

**Goal**: Make sentry-mcp (Sentry MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 36 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-04
**Machinery**: `[mcp]` · **hosted remote** `https://mcp.sentry.dev/mcp` · pin `0.37.0` (curated `@sentry/mcp-server` release the endpoint is validated against) · **FSL-1.1-ALv2** license (Appendix B) · **thin installer per ADR-017** (bare URL, no credential; user auths in-client). *(Reconciled 2026-07-13: chose the hosted-remote shape over npx-stdio; the ADR-017 reframe replaced the "npx + SENTRY_ACCESS_TOKEN / token-not-baked" model.)*
**Success Criteria** (what must be TRUE):

  1. `agentlinux install sentry-mcp` registers the bare hosted URL `https://mcp.sentry.dev/mcp` into every installed MCP-capable agent via `claude mcp add --transport http --scope user` (+ the codex/antigravity/opencode/qwen equivalents) — no root, zero EACCES; it appears in each present agent's config.
  2. NO credential is baked (ADR-017): the entry stores only the URL; `install` prints the in-client-auth pointer (Sentry OAuth on first use); the **FSL-1.1-ALv2** flag is recorded in the entry (`requires_secret: true` as a doc flag, no `secret_env`).
  3. `agentlinux remove sentry-mcp` deregisters symmetrically across all agents — no residue.
  4. ≥1 bats @test covers register → verify → deregister — TST-07 gate.

**Plans**: 37-01 (recipe pair + entry + helper retrofit + bats)

### Phase 38: gitlab-mcp

**Goal**: Make gitlab-mcp (GitLab MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 37 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-05
**Status**: **DROPPED 2026-07-13.** GitLab's official hosted MCP endpoint is paywalled (Premium/Ultimate; free users 404), and the maintainer declined the free third-party `@zereight/mcp-gitlab`. No entry shipped; MCP-05 deferred. See ADR-017 source-selection addendum. May revisit if GitLab frees the endpoint or the third-party is later accepted.
**Machinery** (not shipped): `[mcp]` · official hosted `https://gitlab.com/api/v4/mcp` (paywalled) OR third-party npx `@zereight/mcp-gitlab` (free, declined).
**Success Criteria** (what must be TRUE):

  1. `agentlinux install gitlab-mcp` registers the bare `https://gitlab.com/api/v4/mcp` into every installed MCP-capable agent via `claude mcp add --transport http --scope user` (+ codex/antigravity/opencode/qwen equivalents) — no root, zero EACCES; it appears in each present agent's config.
  2. NO credential is baked (ADR-017): the entry stores only the URL; `install` prints the in-client-auth pointer (GitLab OAuth on first use); `requires_secret: true` as a doc flag, no `secret_env`.
  3. `agentlinux remove gitlab-mcp` deregisters symmetrically across all agents — no residue.
  4. ≥1 bats @test covers register → verify → deregister — TST-07 gate.

**Plans**: 37-... reuse; 38-01 (recipe pair + entry + bats)

### Phase 39: brave-search-mcp

**Goal**: Make brave-search-mcp (Brave Search MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 38 (ENABLE-02 MCP entry kind)
**Requirements**: MCP-06
**Status**: **DROPPED 2026-07-14.** The phase premise "(free tier)" is falsified: Brave removed the card-free Search API tier in Feb 2026. New users now get only a metered ~$5/mo credit (~1,000 queries) that **requires a mandatory credit card as a live billing instrument** (no disclosed spend cap on overages) plus a Brave-attribution condition. Per the ADR-017 source-selection policy (free first-party = auto; everything else = per-case review) the maintainer dropped it — same gate GitLab failed. The server itself is official + MIT + a clean thin-installer fit; may revisit if Brave restores a genuine no-card free tier. No entry shipped; MCP-06 deferred.
**Machinery** (not shipped): `[mcp]` · `@brave/brave-search-mcp-server@2.0.85` (MIT) · stdio or self-host HTTP · `BRAVE_API_KEY` (paid/metered, card required — NOT free)
**Plans**: n/a (dropped)

### Phase 40: firecrawl-mcp ✓ COMPLETE

**Goal**: Make firecrawl-mcp (Firecrawl MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 37 (ADR-017 thin-installer + credential-free remote-http helper)
**Requirements**: MCP-07
**Machinery**: `[mcp]` · **hosted remote-http** (ADR-017 prefer-hosted) · bare OAuth endpoint `https://mcp.firecrawl.dev/v2/mcp` · `pinned_version 3.22.3` (the validated upstream `firecrawl-mcp` release) · MIT
**Source decision (2026-07-14)**: Firecrawl's hosted endpoint is the preferred thin-installer target. The recipe registers the bare OAuth URL via the shared `al_mcp_register_http` helper (cross-agent fan-out, ADR-017); compatible clients complete OAuth, while clients without compatible OAuth may use a user-supplied API-key URL at runtime. AgentLinux stores no credential.
**Success Criteria** (what must be TRUE):

  1. `agentlinux install firecrawl-mcp` registers the bare OAuth `https://mcp.firecrawl.dev/v2/mcp` into every installed MCP-capable agent (claude/codex/antigravity/opencode/qwen) — no root, zero EACCES; it appears in each present agent's config. ✓
  2. NO credential is baked (ADR-017): the entry stores only the URL; `install` prints the client-owned OAuth/API-key fallback pointer; `requires_secret: true`, no `secret_env`. ✓
  3. `agentlinux remove firecrawl-mcp` deregisters symmetrically across all agents — no residue; idempotent re-remove. ✓
  4. ≥1 bats @test (register bare URL → verify no-credential fan-out → deregister) is green — TST-07 gate. ✓ (`tests/bats/62-catalog-firecrawl-mcp.bats`)

**Plans**: executed inline (recipe pair + catalog entry + bats 62 + docs); offline smoke green.

### Phase 41: slack-mcp ✓ COMPLETE

**Goal**: Make slack-mcp (Slack MCP server) registerable + deregisterable via the catalog.
**Depends on**: Phase 37 (ADR-017 thin-installer + credential-free remote-http helper)
**Requirements**: MCP-08
**Machinery**: `[mcp]` · **official first-party hosted remote-http** · bare endpoint `https://mcp.slack.com/mcp` · `pinned_version 2026.2.17` (GA date; no downloadable release to pin) · no package license (proprietary hosted service)
**Source decision (2026-07-14)**: The roadmap's plan (third-party `slack-mcp-server@1.3.0` npx + `xoxp`/stealth-token warning) is **superseded**. Research found that **Slack shipped an official first-party hosted MCP server (GA Feb 2026)** at `https://mcp.slack.com/mcp` — Streamable HTTP, Slack-brokered OAuth 2.0, **workspace-admin-governed by design**, and **free** for workspace members (no paywall — not a gitlab/brave repeat). This is a "free official first-party hosted endpoint" → **auto-GO**. Using it **sidesteps the korotovsky stealth-token (xoxc/xoxd) governance-bypass footgun entirely** — we ship the admin-governed official endpoint only. ADR-017-aligned: bare URL, no baked credential, user OAuths in-client (subject to admin approval).
**Success Criteria** (what must be TRUE):

  1. `agentlinux install slack-mcp` registers the bare `https://mcp.slack.com/mcp` into every installed MCP-capable agent — no root, zero EACCES; it appears in each present agent's config. ✓
  2. NO credential is baked (ADR-017): the entry stores only the URL; `install` prints the in-client-auth pointer (Slack OAuth, admin-approved); `requires_secret: true` as a doc flag, no `secret_env`. NO Slack token (xoxb/xoxp/xoxc/xoxd) in any config. ✓
  3. `agentlinux remove slack-mcp` deregisters symmetrically across all agents — no residue; idempotent re-remove. ✓
  4. ≥1 bats @test (register bare URL → verify no-token fan-out → first-party-only recipe → deregister) is green — TST-07 gate. ✓ (`tests/bats/63-catalog-slack-mcp.bats`)

**Plans**: executed inline (recipe pair + catalog entry + bats 63 + docs); offline smoke green.

### Phase 42: linear-mcp ✓ COMPLETE

**Goal**: Make linear-mcp (official Linear MCP) registerable + deregisterable via the catalog.
**Depends on**: Phase 37 (ADR-017 thin-installer + credential-free remote-http helper)
**Requirements**: MCP-09
**Machinery**: `[mcp]` · **official first-party hosted remote-http** · bare endpoint `https://mcp.linear.app/mcp` · `pinned_version 2025.5.1` (GA date; no downloadable release) · no package license (proprietary hosted service)
**Source decision (2026-07-14)**: **Auto-GO** — Linear ships an official first-party hosted MCP (GA May 2025) at `https://mcp.linear.app/mcp` (Streamable HTTP, OAuth 2.1), and research **confirmed it is free-tier usable** (MCP rides on Linear's GraphQL API, a Free-plan core feature — NOT gated behind a paid plan, unlike the dropped gitlab endpoint; a pricing-table "MCP=Business" claim was verified to be a page-scrape hallucination). The roadmap's 🔧 "remote-http/OAuth **enabler**" is moot — that machinery shipped in Phase 36/37 (`al_mcp_register_http`, credential-free). Per **ADR-017** the recipe does NOT drive `claude mcp login`/`logout`: it registers the bare URL and bakes nothing; the user OAuths in-client; `remove` just deregisters (there is no AgentLinux-held token to log out).
**Success Criteria** (what must be TRUE):

  1. `agentlinux install linear-mcp` registers the bare `https://mcp.linear.app/mcp` into every installed MCP-capable agent — no root, zero EACCES; it appears in each present agent's config. ✓
  2. NO credential is baked (ADR-017): entry stores only the URL; `install` prints the in-client Linear-OAuth pointer; `requires_secret: true` doc flag, no `secret_env`; no Linear token (`lin_api_`/`lin_oauth_`) in any config. ✓
  3. `agentlinux remove linear-mcp` deregisters symmetrically across all agents — no residue; idempotent re-remove. ✓
  4. ≥1 bats @test (register bare URL → verify no-token fan-out → hosted-only recipe → deregister) is green — TST-07 gate. ✓ (`tests/bats/64-catalog-linear-mcp.bats`)

**Plans**: executed inline (recipe pair + catalog entry + bats 64 + docs); offline smoke green.

### Phase 43: jira-atlassian-mcp ✓ COMPLETE

**Goal**: Make jira-atlassian-mcp (official Atlassian Rovo MCP) registerable + deregisterable via the catalog.
**Depends on**: Phase 37 (ADR-017 thin-installer + credential-free remote-http helper)
**Requirements**: MCP-10
**Machinery**: `[mcp]` · **official first-party hosted remote-http** · bare endpoint `https://mcp.atlassian.com/v1/mcp/authv2` (Streamable-HTTP; SSE `/v1/sse` deprecated) · `pinned_version 2026.2.4` (GA date) · `license Apache-2.0` (official repo) · **cloud-only**
**Source decision (2026-07-14)**: **Auto-GO** — Atlassian ships an official first-party hosted MCP (the Rovo MCP Server, GA Feb 4 2026) covering Jira + Confluence at GA (more Atlassian products rolling out); OAuth 2.1 in-client. Research **confirmed free-tier usable**: Atlassian's platform page lists Free at 500 calls/hour and states *all* Cloud customers have access — NOT gated behind a paid plan or paid Rovo add-on (unlike the dropped gitlab endpoint). Per **ADR-017** the recipe registers the bare URL and bakes nothing; the user OAuths in-client; `remove` just deregisters (no AgentLinux-held token to log out — supersedes the roadmap's `claude mcp logout` step). **Modeling first:** this hosted endpoint has NO downloadable release (→ GA-date pin, like slack/linear) but DOES have an official Apache-2.0 repo (→ record `license: Apache-2.0`, like github/sentry) — version and license are independent axes.
**Success Criteria** (what must be TRUE):

  1. `agentlinux install jira-atlassian-mcp` registers the bare `https://mcp.atlassian.com/v1/mcp/authv2` into every installed MCP-capable agent — no root, zero EACCES; it appears in each present agent's config. ✓
  2. NO credential is baked (ADR-017): entry stores only the URL; `install` prints the in-client Atlassian-OAuth pointer + the cloud-only note; `requires_secret: true` doc flag, no `secret_env`; no Atlassian token (`ATATT`/`ATCTT`) in any config. ✓
  3. `agentlinux remove jira-atlassian-mcp` deregisters symmetrically across all agents — no residue; idempotent re-remove. ✓
  4. ≥1 bats @test (register bare URL → verify no-token fan-out → hosted-only recipe → deregister) is green — TST-07 gate. ✓ (`tests/bats/65-catalog-jira-atlassian-mcp.bats`)

**Plans**: executed inline (recipe pair + catalog entry + bats 65 + docs); offline smoke green.

### Phase 44: spec-kit

**Goal**: Make spec-kit (GitHub Spec Kit) installable + removable via the catalog, AND deliver the Python+uv-bootstrap enabler (ENABLE-03).
**Depends on**: Phase 43. First consumer of the Python+uv entry kind.
**Requirements**: WORK-03, ENABLE-03
**Machinery**: `[uv]` · 🔧 ENABLE-03 Python+uv bootstrap · **source_kind `script`** (no new enum — the CLI runs script/binary/mcp recipes identically) · pin **`v0.12.11` git tag** (roadmap's `specify-cli@0.11.9` was stale + wrong shape — spec-kit installs `uv tool install specify-cli --from git+…@vX.Y.Z`, verified vs upstream README + a real smoke) · uv binary bootstrap pin `0.11.28` (static musl) · project `.specify/` user-owned · **git is a host prereq** (uv installs from a git ref; recipe preflights it)
**Source decision (2026-07-14)**: **Auto-GO** — GitHub Spec Kit is an official first-party GitHub project, MIT, free, actively maintained. Free-first-party = no maintainer review needed. No credential dimension (offline/local dev tool).
**Success Criteria** (what must be TRUE):

  1. ENABLE-03: the catalog supports Python+uv entries — a per-user `uv` bootstraps into `~/.local/bin` (no root); install uses `uv tool`; uninstall is symmetric. ✓
  2. `agentlinux install spec-kit` installs `specify-cli` (git tag v0.12.11) via uv as the agent user (no root, zero EACCES); `specify` resolves at `~/.local/bin`. ✓
  3. Project `.specify/` is user-owned and is NOT removed by `agentlinux remove`. ✓
  4. `agentlinux remove spec-kit` uninstalls the uv tool symmetrically + tears down the AgentLinux-managed uv (marker-gated, only if no uv tools remain), never a user-brought uv; idempotent. ✓
  5. ≥1 bats @test (uv bootstrap → install → OPS-01 `specify init` → symmetric remove) green — TST-07 gate. ✓ (`tests/bats/66-catalog-spec-kit.bats`, Docker 3/3)

**Plans**: executed inline (uv-bootstrap helper + recipe pair + catalog entry + bats 66 + docs); real end-to-end smoke + Docker 3/3 green.

### Phase 45: claude-flow

**Goal**: Make claude-flow (Claude-Flow) installable + removable via the catalog, with full-footprint symmetric remove.
**Depends on**: Phase 44 (npm machinery)
**Requirements**: WORK-04
**Status**: **DROPPED 2026-07-14 (maintainer decision).** Judged too niche for the first-release cohort — the structured multi-agent-workflow need is already covered by spec-kit (Phase 44) and GSD, both far more popular. This is a demand/prioritization drop, **not** a source-gate failure (unlike gitlab/brave): `claude-flow@3.14.4` is npm, MIT, and a clean per-user install fit. Revisitable later — cheaply addable via the Phase 49 growth-kit contributor template (ENABLE-07) without touching CLI source. WORK-04 deferred.
**Machinery** (not shipped): `[npm]` · pin `claude-flow@3.14.4` · remove would clean `.claude`/`.swarm`/`.hive-mind`, MCP regs, hooks
**Plans**: n/a (dropped)

### Phase 46: bmad

**Goal**: Make bmad (BMAD-METHOD) installable + removable via the catalog.
**Depends on**: Phase 45 (npm machinery)
**Requirements**: WORK-05
**Status**: **DROPPED 2026-07-14 (maintainer decision).** Same rationale as Phase 45 — too niche for the first-release cohort; spec-kit (Phase 44) and GSD cover the spec-driven-workflow need and are far more popular. Demand/prioritization drop, **not** a source-gate failure: `bmad-method@6.9.0` is npm and MIT (GitHub shows `NOASSERTION`; MIT per Appendix B), a clean install fit. Revisitable via the Phase 49 growth-kit template (ENABLE-07) without CLI edits. WORK-05 deferred.
**Machinery** (not shipped): `[npm]` · pin `bmad-method@6.9.0` · remove would be symmetric over installed agents/packs
**Plans**: n/a (dropped)

### Phase 47: openclaw

**Goal**: Make openclaw (OpenClaw) installable + removable via the catalog, AND deliver the AI-assistant daemon-lifecycle enabler (ENABLE-04).
**Depends on**: Phase 44 (npm machinery; Phases 45–46 dropped). First consumer of the AI-assistant daemon entry kind.
**Requirements**: ASST-01, ENABLE-04
**Machinery**: `[daemon]` · 🔧 ENABLE-04 AI-assistant daemon lifecycle · pin `openclaw@2026.6.10` (npm + per-user daemon) · self-updater coexistence per ENABLE-05
**Source decision (2026-07-14)**: **GO (maintainer: build both ASST tools)**. openclaw = `openclaw/openclaw` (steipete), MIT, ~383k stars, self-hosted per-user daemon, BYO provider key, no paid backend — vetted per policy (daemon-class = not auto-GO, reviewed + approved). Node engines `>=22.19.0` satisfied by AgentLinux's Node 22 (latest v22.23.1).
**De-risk research (2026-07-14, container probe — findings for the build):**

  - Install: `npm install -g openclaw@2026.6.10` works as agent (agent npm prefix, no root, 297 pkgs, `openclaw` on PATH). Has a `postinstall` script (benign in probe).
  - Daemon lifecycle commands: `openclaw daemon {install,start,stop,restart,status,uninstall}` (native launchd/systemd), `openclaw gateway …` (run gateway as a plain process — testable without systemd), `openclaw health` / `openclaw status`, `openclaw doctor`. State dir `~/.openclaw` (mode 0700).
  - **Non-interactive + no-secret**: `openclaw onboard --non-interactive --accept-risk --auth-choice skip` sets up without baking any provider key (secrets NOT baked ✓).
  - **KEY CONSTRAINT**: `openclaw daemon install` uses **systemd `--user`** (linger) — the **Docker harness masks `systemd-logind`** (no `/run/user`, no user bus), so the systemd-user daemon path is **NOT testable in Docker** → it is a **QEMU-gated behavior** (ADR-007). Docker bats must verify the daemon via the **process-level `openclaw gateway` + `openclaw health`** path; the systemd-user install/linger lifecycle gets a QEMU test.
  - ENABLE-04 helper (proposed): `plugin/catalog/lib/daemon-lifecycle.sh` — enable-linger (agent sudo per ADR-012) + `openclaw daemon install/start`, a health-probe, and a symmetric `daemon uninstall` + `~/.openclaw` teardown + linger revert. Disable openclaw auto-update for ENABLE-05.

**Success Criteria** (what must be TRUE):

  1. ENABLE-04: the catalog supports AI-assistant daemon entries — `install` sets up a per-user background service (no root); `remove` tears it down with no stray daemon, unit, or state.
  2. `agentlinux install openclaw` installs `openclaw@2026.6.10` (npm + per-user daemon) as the agent user (no root, zero EACCES); the daemon runs per-user.
  3. Self-updater coexistence (ENABLE-05) holds — openclaw's pin stays authoritative; secrets are NOT baked.
  4. `agentlinux remove openclaw` tears down the daemon + state symmetrically — no stray unit/process/files; idempotent.
  5. ≥1 bats @test (install → daemon-up verify → remove → daemon-gone) is green — TST-07 gate.

**Status**: ✓ COMPLETE 2026-07-14 — Docker 4/4 green (ubuntu-24.04); ENABLE-04 helper `plugin/catalog/lib/daemon-lifecycle.sh` (linger + XDG + marker-gated revert) + openclaw recipe (`source_kind: script`, npm install + no-secret `onboard --auth-choice skip --skip-health` + `config patch` self-updater freeze `update.auto.enabled=false` + daemon lifecycle). Docker verifies the process-level `openclaw gateway run` path (credential-free HTTP-200 + `health ok:true`); the systemd-user daemon lifecycle self-gates with `skip` and runs under QEMU (ADR-007). `~/.openclaw` preserved on remove (CAT-04). Corrections vs research: config key is `update.auto.enabled` (not `autoUpdate`), written via `config patch --stdin`; onboard needs `--skip-health` for RC 0. AL-94 → Done.
**Plans**: 1/1 (main-agent direct execution, milestone convention).

### Phase 48: hermes-agent

**Goal**: Make hermes-agent (Hermes Agent) installable + removable via the catalog.
**Depends on**: Phase 47 (ENABLE-04 AI-assistant daemon entry kind)
**Requirements**: ASST-02
**Machinery**: `[daemon]` · pin `2026.6.19` (curl installer + per-user daemon/gateway)
**Source decision (2026-07-14)**: **GO (maintainer: build both ASST tools)**. Official = **`NousResearch/hermes-agent`** (Nous Research), open-source, ~214k stars, official curl installer `curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash` (installs uv + Python 3.11 + clones repo, no sudo), per-user daemon/gateway, BYO provider key. **Do NOT use the npm `hermes-agent`** (wyrtensi) — that is an UNOFFICIAL third-party bridge (v0.18.2), a different artifact. Supply-chain note: the official install is curl-pipe-bash; assess pinning/verification against AgentLinux's own installer bar (the curl-installer verifies sha256). Reuses ENABLE-04 from Phase 47.
**Success Criteria** (what must be TRUE):

  1. `agentlinux install hermes-agent` installs `hermes-agent` `2026.6.19` (official Nous Research curl installer + per-user daemon/gateway) as the agent user (no root, zero EACCES); the daemon/gateway runs per-user.
  2. Secrets are NOT baked — any gateway credentials supplied post-install.
  3. `agentlinux remove hermes-agent` tears down the daemon + gateway + state symmetrically — no residue; idempotent.
  4. ≥1 bats @test (install → daemon/gateway-up verify → remove → gone) is green — TST-07 gate.

**Status**: ✓ COMPLETE 2026-07-14 — Docker 3/3 green (ubuntu-24.04). Reuses the Phase 47 ENABLE-04 helper. `source_kind: script`, pin `2026.6.19`, MIT. **Supply-chain decision (maintainer, "build it, pin-to-commit"):** the official installer is a third-party HTTPS curl-installer with no script checksum — mitigated by download-then-run over pinned TLS + pinning the CODE to the immutable commit `2bd1977d8fad185c9b4be47884f7e87f1add0ce3` (peeled `v2026.6.19` tag) via the installer's `--commit` flag, `--non-interactive` (no baked key), no-root agent-owned dirs (no /usr/local shim). Version-lock: `hermes --version` contains `2026.6.19`. OPS-01 real op = `hermes doctor`. Surgical CAT-04 remove (strip `~/.hermes/hermes-agent` checkout + `~/.local/bin/hermes` launcher; preserve `~/.hermes` user data/secrets; --purge wipes). systemd-user Gateway lifecycle QEMU-gated (ADR-007). AL-95 → Done.
**Plans**: 1/1 (main-agent direct execution, milestone convention).

### Phase 49: catalog growth kit

**Goal**: Deliver the `list` category/tags UX (ENABLE-06) and the catalog growth kit — a contributor recipe template + the selection-rubric doc (ENABLE-07). Milestone capstone — no new tool.
**Depends on**: Phases 23–48 (needs the full shipped catalog — 22 new entries after the gitlab/brave/claude-flow/bmad drops — to categorize and to validate template-only additions against)
**Requirements**: ENABLE-06, ENABLE-07
**Machinery**: `[meta]` · catalog-wide UX + contributor surface (extends CAT-03)
**Success Criteria** (what must be TRUE):

  1. ENABLE-06: `agentlinux list` groups catalog entries by category/tags (coding-agent · mcp · devops · token/workflow · assistant) — all 22 new entries appear under the correct category.
  2. ENABLE-07: a contributor recipe template + the selection-rubric doc are published — a new catalog entry can be added without touching CLI source (extends CAT-03).
  3. The growth kit is exercised end-to-end: a sample entry added via the template alone passes validate-catalog + install/remove with zero TypeScript edits.
  4. ≥1 bats @test covers `list` category grouping + the template-only-add path — TST-07 gate; milestone-close: all 22 new catalog entries install → verify → remove green across the Docker + QEMU gates.

**Plans**: TBD

### Phase 50: integration QA

**Goal**: Deliver a **reusable `qa-testing` Claude Code skill** (the primary artifact — invokable on demand at any future milestone close), then **run it** as this milestone's final integration sweep. The bats/Docker/QEMU gates prove each entry works *in isolation*; this phase hunts the bugs those gates structurally can't see — **emergent problems when the shipped tools are installed together and driven like a human would drive them** (e.g. gsd + codex + an MCP server co-installed; cross-agent MCP fan-out collisions; PATH/config clobbering; `list`/`install`/`remove` UX and TUI rendering at a default terminal). Not a fixed test list — an open-ended, judgment-driven QA session that runs until it stops finding bugs. Milestone verification capstone; no new catalog entry.
**Status**: ✓ COMPLETE 2026-07-19 — available-scope stop gate met (33m12s productive activity and 10 latest clean ideas after the latest confirmed finding); residual credential/OAuth and systemd/QEMU boundaries are explicitly documented; all findings and known issues are routed to Phase 51.
**Depends on**: Phases 23–49 (needs the full co-installable shipped catalog to exercise together; runs after the catalog is feature-complete)
**Requirements**: TST-08 (new — reusable QA-session skill + milestone-close integration sweep); exercises the full AGT/MCP/DEVT/WORK/ASST/ENABLE surface end-to-end
**Machinery**: `[qa]` · new `.claude/skills/qa-testing/` skill · representative-TUI test session (real PTY, default width, color, live I/O) · findings triaged to fixes (trivial → fix inline) or new decimal phases / AL tickets (deeper)
**Success Criteria** (what must be TRUE):

  1. **The skill exists and is self-sufficient.** `.claude/skills/qa-testing/SKILL.md` instructs Claude Code to run an on-demand QA session with three codified pillars:
     - **(a) Scoped.** QA scope is derived from what the unit-under-test (release / milestone / phase) *touched*: the direct deliverables get heavy, creative, varied exercise; adjacent/possibly-impacted surfaces get a lighter sanity pass. The skill explains how to derive that scope (diff, roadmap, requirement IDs).
     - **(b) Regression-to-zero stop condition.** Instead of a fixed checklist, testing continues until both at least 30 minutes of productive QA activity and the latest 10 distinct test ideas are classified clean for new-issue discovery since the latest finding. Productive time excludes chat idle, usage-limit pauses, user-input waits, and external blocks. Known-issue replays are neither new nor clean; blocked ideas do not advance the gate. Free-form invocation text may override the defaults. Planning/notes are encouraged, but the stop signal is bug-arrival-rate plus active-work duration, not checklist completion.
     - **(c) Representative TUI session.** The skill mandates a setup that faithfully reproduces what a real user sees — a real interactive PTY (not a captured pipe that makes interactive prompts render as a frozen script), default terminal geometry (~80-col width behavior + a documented wider case), color/ANSI on, and observation of live/streaming output vs apparent freezes while work happens in the background. Documents *how* to stand this session up reliably (which harness — e.g. `tests/docker/rc-sandbox.sh` or a PTY wrapper — env, TERM, width).
  2. **Co-installed integration is actually exercised.** At least the high-traffic combinations are driven together (e.g. two coding agents such as gsd + codex; a coding agent + ≥1 MCP server across the cross-agent fan-out; a `[bin]` + `[npm]` + `[daemon]` mix) — verifying no install-order dependence, no config/PATH clobbering, symmetric `remove` with a co-installed sibling still present, and no cross-tool residue. (Extends the order-independence concern already tracked from the v0.3.6 dogfood feedback.)
  3. **The run happened and is recorded.** A QA session was actually run against the feature-complete catalog; findings are captured as a triaged report (bug · severity · repro · scope-bucket direct/adjacent), each routed to an outcome: fixed inline, or filed as a decimal phase / AL ticket. The session reached its stop condition (30 productive minutes plus the latest 10 clean-by-novelty ideas) or an explicit maintainer hand-off.
  4. **Handback is honest about limits.** The report states what was and was NOT covered (which combinations, which invocation modes, Docker-vs-QEMU reachability) so the maintainer's own final pass is scoped — no silent "tested everything" claim.
  5. Skill is registered where the other project skills live (CLAUDE.md skills list + `.claude/skills/`), so it is invocable on demand for future milestones, not one-shot scaffolding. ≥1 lightweight self-check that the skill is discoverable/loads (TST-07-style gate, adapted — this phase ships a workflow, not a catalog recipe).

**Plans**: TBD

## Progress

**Execution Order:** Phases execute strictly in numeric order: 23 → 24 → … → 49 → 50 (integration-QA capstone) → 51 (unified remediation) → 52 (priority-package QA sweep).

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 23. codex 🔧 | 1/1 | Complete | 2026-06-29 |
| 24. antigravity-cli | 1/1 | Complete | 2026-07-19 |
| 25. opencode | 1/1 | Complete | 2026-06-29 |
| 26. qwen-code | 1/1 | Complete | 2026-06-29 |
| 27. ccusage | 1/1 | Complete | 2026-06-29 |
| 28. rtk 🔧 | 4/4 | Complete | 2026-06-30 |
| 29. gh | 1/1 | Complete | 2026-07-02 |
| 30. glab | 1/1 | Complete | 2026-07-02 |
| 31. trivy | 1/1 | Complete | 2026-07-02 |
| 32. gitleaks | 1/1 | Complete | 2026-07-02 |
| 33. sentry-cli | 1/1 | Complete | 2026-07-02 |
| 34. chrome-devtools-mcp 🔧 | 1/1 | Complete | 2026-07-12 |
| 35. context7 | 1/1 | Complete | 2026-07-12 |
| 36. github-mcp 🔧 | 1/1 | Complete | 2026-07-13 |
| 37. sentry-mcp | 1/1 | Complete | 2026-07-13 |
| 38. gitlab-mcp | 0/0 | Dropped | 2026-07-13 |
| 39. brave-search-mcp | 0/0 | Dropped | 2026-07-14 |
| 40. firecrawl-mcp | 1/1 | ✓ Complete (Docker 2/2 green) | 2026-07-14 |
| 41. slack-mcp | 1/1 | ✓ Complete (Docker 2/2 green) | 2026-07-14 |
| 42. linear-mcp | 1/1 | ✓ Complete (Docker 2/2 green) | 2026-07-14 |
| 43. jira-atlassian-mcp | 1/1 | ✓ Complete (Docker 2/2 green) | 2026-07-14 |
| 44. spec-kit 🔧 | 1/1 | ✓ Complete (Docker 3/3 green) | 2026-07-14 |
| 45. claude-flow | 0/0 | Dropped | 2026-07-14 |
| 46. bmad | 0/0 | Dropped | 2026-07-14 |
| 47. openclaw 🔧 | 1/1 | ✓ Complete (Docker 4/4 green; systemd-user QEMU-gated) | 2026-07-14 |
| 48. hermes-agent | 1/1 | ✓ Complete (Docker 3/3 green; systemd-user QEMU-gated) | 2026-07-14 |
| 49. catalog growth kit | 1/1 | ✓ Complete (Docker 4/4 green) | 2026-07-14 |
| 50. integration QA | 1/1 | ✓ Complete (available-scope gate met; residual credential/OAuth/systemd boundaries documented; findings routed to Phase 51) | 2026-07-19 |
| 51. unified integration-QA remediation | 4/4 | ✓ Complete | 2026-07-19 |
| 52. priority-package QA sweep 🧪 | 0/0 | Not planned | — |

### Phase 51: Fix all Phase 50 integration-QA findings, known issues, and prerequisite boundaries

**Goal:** Fix every actionable issue recorded by Phase 50, including the Firecrawl auth, OpenCode GitHub MCP OAuth, and Playwright invalid-target findings; the GSD/Codex configuration and Playwright runtime-library known issues; and the Spec Kit `git` and Chrome runtime prerequisite boundaries. Add regression coverage and revalidate the affected user workflows.
**Requirements**: TBD
**Depends on:** Phase 50
**Plans:** 4/4 plans complete

**Exit gate:** After remediation and targeted regression checks are complete, run the `qa-testing` workflow again across the Phase 50 in-scope packages and representative workflows—not only the fixed paths. Record whether each known issue is resolved, any remaining blockers, and every newly discovered problem. Phase 51 is not complete until this follow-up QA sweep and its findings are recorded; `openclaw` and `hermes-agent` remain excluded unless a systemd-capable test environment becomes available.

Plans:

- [x] 51-01-PLAN.md — hosted Firecrawl and OpenCode/GitHub MCP diagnostics and regression coverage
- [x] 51-02-PLAN.md — browser prerequisites and Playwright status/launch hardening
- [x] 51-03-PLAN.md — Open GSD migration and Codex/runtime wiring
- [x] 51-04-PLAN.md — follow-up QA sweep and durable evidence handback

### Phase 52: Priority-package QA sweep

**Goal:** Run the reusable `qa-testing` skill as a **focused, high-effort QA loop scoped to the owner's highest-value catalog packages** — not the whole 23-entry catalog. Phases 50/51 gave the full catalog a broad integration sweep; this phase spends extra QA budget where it matters most to the maintainer, driving each priority tool (and its realistic co-install combinations) like a human would until the regression-to-zero stop rule fires, so the maintainer has high confidence these specific tools work smoothly at ship.
**Priority packages (the QA scope):** `claude-code`, `opencode`, `codex`, `gsd`, `spec-kit`, `playwright-cli`, `gh`, `jira-atlassian-mcp`, `rtk`, `context7`. Everything else in the catalog is out of scope for this phase (already covered by Phase 50/51's broad sweep).
**Depends on:** Phase 51 (reuses the `.claude/skills/qa-testing/` skill built in Phase 50 and the remediated baseline from Phase 51; runs after the priority tools' known issues are fixed so this sweep starts from a clean slate).
**Requirements**: TST-08 (re-exercised — reusable QA-session skill, scoped invocation); exercises the AGT (claude-code/opencode/codex), WORK (gsd/rtk), MCP (jira-atlassian-mcp/context7), DEVT (gh), and `[uv]`/skill-wiring (spec-kit/playwright-cli) surfaces for the priority subset only.
**Machinery**: `[qa]` · re-invokes the existing `.claude/skills/qa-testing/` skill with a scope override to the 10 priority packages · representative-TUI session (real PTY, default width, color, live I/O) · findings triaged to fixes (trivial → fix inline) or a follow-up decimal phase / AL tickets (deeper), same routing convention as Phase 50→51.
**Success Criteria** (what must be TRUE):

  1. **The sweep is scoped to the priority set.** The `qa-testing` skill is invoked with an explicit scope override naming the 10 priority packages; each gets heavy, creative, varied exercise (install → real operation(s) → representative interactive session → symmetric remove), not just an install smoke. Co-install combinations that reflect how the owner actually uses them are driven together (e.g. gsd + codex; claude-code + context7/jira-atlassian-mcp cross-agent MCP fan-out; a `[bin]` gh + `[npm]` opencode + `[uv]` spec-kit mix) — verifying no install-order dependence, no config/PATH clobbering, and residue-free removal with a co-installed sibling still present.
  2. **The regression-to-zero stop rule is honored.** Testing continues until both ≥30 minutes of productive QA activity and the latest 10 distinct new-issue ideas classify clean since the last confirmed finding (per the Phase 50 skill contract). Known-issue replays don't count as new or clean; blocked ideas don't advance the gate.
  3. **The run happened and is recorded.** A QA session was actually run against the 10 priority packages on the Phase 51 baseline; findings are captured as a triaged report (bug · severity · repro · package), each routed to an outcome: fixed inline, or filed as a decimal phase / AL ticket. The session reached its stop condition or an explicit maintainer hand-off.
  4. **Handback is honest about limits.** The report states what was and was NOT covered per package (which invocation modes, which co-install combos, credential/OAuth reachability for `jira-atlassian-mcp`/`context7`, the `spec-kit` `git` prerequisite, Docker-vs-QEMU reachability) — no silent "all green" claim. Any priority tool that could not be fully exercised (e.g. an auth-gated MCP path) is named explicitly.

**Plans**: TBD (run `/gsd-plan-phase 52` to break down)

---

## Milestones

<details>
<summary>Phase 17: Changes Delivery and Release Candidate ✓ COMPLETE (v0.3.4 SHIPPED 2026-06-08)</summary>

### Phase 17: Changes Delivery and Release Candidate ✓ COMPLETE (v0.3.4 shipped)

**Goal:** Ship the feature-complete v0.3.4 "Aware Installation Process" to a maintainer-testable release candidate and gate the final release on live brownfield review. Polish the worktree branch diff (tests green, commit hygiene), merge to master, cut `v0.3.4-rc1` (tarball + sibling `.sha256` via `scripts/build-release.sh`; push the rc tag to exercise `release.yml` end-to-end — the shipping event), hand the maintainer concrete live-test instructions for his real brownfield VM, then await maintainer feedback as an explicit checkpoint. Outcome: 4 rc iterations (rc1→rc4) each fixing a maintainer-found bug (AL-60/AL-61/AL-62), then LGTM → promoted to final v0.3.4.

**Requirements:** Delivery gate — no new behavior requirements. Re-exercised AGT-02 (zero-EACCES `claude update`) on the maintainer's real brownfield VM.

**Depends on:** Phase 16 (v0.3.4 feature-complete, GATE: GREEN)
**Anchor:** [AL-38](https://copiedwonder.atlassian.net/browse/AL-38)

**Plans:** 3 plans (3 waves — strict delivery ordering with 2 human checkpoints)

Plans:

- [x] 17-01-PLAN.md — DEL-02a + DEL-01: lockstep version bump 0.3.2→0.3.4 + merge-integrate origin/master + full suite green
- [x] 17-02-PLAN.md — DEL-01b/DEL-02b/DEL-03/DEL-04: push branch + open PR → merge PR → push rc tag + watch release → brownfield-VM runbook → VM validation
- [x] 17-03-PLAN.md — DEL-05: promote-or-iterate decision gate. Outcome: 4 rc iterations then LGTM → promoted to final v0.3.4.

</details>

## Shipped / Feature-Complete Milestones

| Version | Name | Phases | Status | Archive |
|---------|------|--------|--------|---------|
| v0.3.5 | AlmaLinux 9 Support | 5 (Phase 18-22) | **SHIPPED 2026-07-11** (Docker ×4 incl. almalinux-9 + nightly-QEMU green) | [v0.3.5-ROADMAP.md](milestones/v0.3.5-ROADMAP.md) · [v0.3.5-REQUIREMENTS.md](milestones/v0.3.5-REQUIREMENTS.md) · phases archived under [milestones/v0.3.5-phases/](milestones/v0.3.5-phases/) |
| v0.3.4 | Aware Installation Process | 6 (Phase 12-17) | **SHIPPED 2026-06-08** (final v0.3.4, Latest; rc1→rc4 maintainer-validated) | [v0.3.4-ROADMAP.md](milestones/v0.3.4-ROADMAP.md) · [v0.3.4-REQUIREMENTS.md](milestones/v0.3.4-REQUIREMENTS.md) · [v0.3.4-MILESTONE-AUDIT.md](v0.3.4-MILESTONE-AUDIT.md) |
| v0.3.3 | Agenda Redefinition | 5 (Phase 13-17) | shipped 2026-05-24 (docs/vision/website) | [v0.3.3-ROADMAP.md](milestones/v0.3.3-ROADMAP.md) · [v0.3.3-REQUIREMENTS.md](milestones/v0.3.3-REQUIREMENTS.md) · phases archived under [milestones/v0.3.3-phases/](milestones/v0.3.3-phases/) |
| v0.4.0 | Open-Source Release | 5 (Phase 7-11) | feature-complete (formal closeout pending) | [v0.4.0-ROADMAP.md](milestones/v0.4.0-ROADMAP.md) · [v0.4.0-REQUIREMENTS.md](milestones/v0.4.0-REQUIREMENTS.md) |
| v0.3.0 | AgentLinux Plugin (Ubuntu) | 6 + 1 inserted (Phase 1-6, 5.1) | shipped 2026-04-20 | [v0.3.0-ROADMAP.md](milestones/v0.3.0-ROADMAP.md) · [v0.3.0-REQUIREMENTS.md](milestones/v0.3.0-REQUIREMENTS.md) |
| v0.2.0 | First Distro Image | 4 (Phase 1-4) | retired 2026-04-18 (pivot) | [v0.2.0-ROADMAP.md](milestones/v0.2.0-ROADMAP.md) · [v0.2.0-REQUIREMENTS.md](milestones/v0.2.0-REQUIREMENTS.md) |
| v0.1.0 | (initial) | — | — | [v0.1.0-ROADMAP.md](milestones/v0.1.0-ROADMAP.md) · [v0.1.0-REQUIREMENTS.md](milestones/v0.1.0-REQUIREMENTS.md) |

> **Phase-numbering note (parallel-milestone overlap).** Two layers of overlap are recorded here:
>
> 1. **Historical (already shipped):** v0.3.3 (Agenda Redefinition, phases **13–17**) and v0.3.4 (Aware Installation, phases **12–17**) were developed concurrently on separate branches and **reused phase numbers** — frozen in immutable git commit prefixes (`feat(13-…)` etc.). Reconciliation: v0.3.3's completed phase dirs are **archived** under `milestones/v0.3.3-phases/`, leaving the active `phases/` dir to v0.3.4's 12–17. One residual reuse remains — **phase 12** is both v0.3.4's `12-detection-layer` and v0.4.0's AL-22 addendum `12-developer-documentation-…`; both completed, distinguished by dir-slug. This mirrors v0.2.0's archived 1–4 vs v0.3.0's 1–6.
> 2. **Current (in flight, two parallel branches):** v0.3.5 (AlmaLinux 9 support) owns phases **18–22** on `worktree-almalinux-support`; v0.3.6 (Catalog Expansion, this file) owns phases **23–49** on its own branch. The 18–22 / 23–49 split was chosen up front so the two never collide on version *or* phase number. Phases 18–22 are RESERVED for v0.3.5 and must not be reused by Catalog Expansion. Merge reconciliation (PROJECT.md / MILESTONES.md / ROADMAP.md) is expected when both branches land.

## Next Milestone Candidates

- **v0.3.5 AlmaLinux support** — port the aware-install pipeline (Phase 12-15 detection + REUSE/REMEDIATE) to AlmaLinux 9. Anchored under [AL-47](https://copiedwonder.atlassian.net/browse/AL-47) (grouped with AL-38 under Epic AL-48 — maintainer-VM daily-driver readiness). *In flight on `worktree-almalinux-support` as v0.3.5 / phases 18–22.*
- **AL-59 alt-user hollow-install** (carried forward from v0.3.4, under Epic AL-48): the installer's alt-user path needs end-to-end wiring (20-sudoers.sh / 30-nodejs.sh / 40-path-wiring.sh still hardcode `agent`).
