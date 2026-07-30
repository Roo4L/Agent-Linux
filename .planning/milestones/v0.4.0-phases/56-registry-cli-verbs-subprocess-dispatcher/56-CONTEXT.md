# Phase 56: Registry CLI Verbs + Subprocess Dispatcher - Context

**Gathered:** 2026-07-28
**Status:** Ready for planning
**Mode:** Smart-discuss infrastructure-skip (like-for-like CLI port; contract-equivalent stdout/exit codes — no observable behavior change). Codebase scout below.

<domain>
## Phase Boundary

Port the user-facing registry CLI + the subprocess dispatcher + the typed env-var
recipe contract to Rust, so `agentlinux <verb>` produces contract-equivalent
stdout + exit codes to the TS CLI and the ~25 unchanged Bash recipes still run.

- **VERB-01** — `list / install / remove / upgrade / pin / adopt` produce
  contract-equivalent stdout + exit codes; the existing `CLI-*` + `50-agents` /
  list / upgrade / pin bats are green on the Rust build.
- **VERB-02** — the subprocess dispatcher runs recipes as the target user
  (`sudo -u`), streams output (tee), enforces a timeout, escalates SIGTERM→SIGKILL;
  dispatcher/streaming behavior tests green.
- **VERB-03** — the 6 `AGENTLINUX_*` recipe env vars are generated from a single
  typed Rust source; the ~25 unchanged Bash recipes run against it (a rename can't
  silently desync CLI and recipes).
- **GATE-01 / GATE-05** — full bats green for the CLI surface (no regression / no
  newly-skipped); master shippable; parallel track; per-phase rollback.

Consumes the Phase-55 pure core (classify/divergence/category/pin_spec/detect_gates)
+ the Phase-53 reuse decision. Adds the I/O + CLI-arg + subprocess layer around it.
OUT of scope: the provisioner (Phase 57), distribution (Phase 58).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (infrastructure/port phase)
Like-for-like CLI port; parity pinned by the bats behavior suite (ADR-002) +
contract-equivalent stdout/exit. Recommended shape below; not binding.

### Recommended (planner + research to finalize)
- The Rust `agentlinux` bin (Phase 53 thin bin) grows the real verbs: `list`,
  `install`, `remove`, `upgrade`, `pin`, `adopt`, consuming `agentlinux-core`.
  Use a small arg-parser (the Phase-53 plain-argv match, or `clap` if the verb/flag
  surface warrants — research to weigh; `clap` gives completions but adds a dep).
- The dispatcher (sudo-u / streaming-tee / timeout / SIGTERM→SIGKILL) is the one
  genuinely NEW systems component — port it faithfully (research: locate the TS
  source — likely runner.ts + a dispatcher-stream module — and the behavior tests).
- **VERB-03 env-var contract:** generate the 6 `AGENTLINUX_*` names from ONE typed
  Rust source consumed by both the dispatcher and a manifest the recipes source, so
  a rename can't desync. The 6 names: `PINNED_VERSION`, `CATALOG_DIR`, `AGENT_HOME`,
  `SOURCE_KIND`, `INSTALL_LOG`, `PRESERVE_PATHS` (runner.ts:46-54).
- The cache-read I/O deferred from Phase 55 (readCachedAgentById/detectCachePath)
  lands here as the adapter feeding the ported detect gates.
- Parity oracle: the CLI bats (40-registry-cli, 50-agents, 10-installer,
  23-install-user) + the TS command unit tests (install/list/remove/upgrade/pin/
  adopt .test.ts). Bats must stay green on the Rust build (Docker OOM → targeted
  per-file runs; stage the Rust bin like Phase 53's run.sh does).

### The irreducible boundary (survives the rewrite — do NOT port)
The ~25 per-agent `install.sh`/`uninstall.sh` recipes stay Bash; the Rust
dispatcher shells to them via the 6-var env contract. This is the thin
untyped boundary the research doc flagged as surviving any rewrite.

</decisions>

<code_context>
## Existing Code Insights (from scout)

### Port targets (TS → Rust CLI, ~1400 LOC)
- `plugin/cli/src/commands/`: adopt.ts (130), install.ts (318), list.ts (227),
  pin.ts (168), remove.ts (75), upgrade.ts (262).
- `plugin/cli/src/runner.ts` (121) — the env-var contract (6 AGENTLINUX_* at
  lines 46-54) + recipe dispatch; `plugin/cli/src/index.ts` (108) — Commander
  bootstrap; the subprocess streaming is in a dispatcher-stream module
  (dispatcher-stream.test.ts exists) — research to locate + map VERB-02 behaviors.
- Consumes the ported `agentlinux-core` (Phase 53–55) + the cache-read adapter
  (deferred from Phase 55).

### Acceptance oracle
- CLI bats: tests/bats/40-registry-cli.bats, 50-agents.bats, 10-installer.bats,
  23-install-user.bats. + the TS command unit tests as parity reference.
- Phase-54 machinery (proptest/mutants) covers any new pure helpers; the CLI I/O
  layer is validated by bats behavior.

</code_context>

<specifics>
## Specific Ideas

- This is the second-largest phase (after 57). The dispatcher (sudo-u/tee/timeout/
  kill-escalation) is the one real new systems component — Go would win ergonomics
  here but Rust hand-rolls it (as the TS dispatcher already does); port faithfully.
- Contract-equivalent means byte-compatible stdout + identical exit codes the bats
  assert — NOT necessarily identical internal structure.
- master shippable; all on branch `worktree-stack-revisiting`; recipes stay Bash.

</specifics>

<deferred>
## Deferred Ideas

- Provisioner port (agent-user/sudoers/nodejs/path-wiring/registry-staging +
  detect/remediate/reuse/idempotency) + CANONICAL_PATHS consolidation → Phase 57.
- musl tarball as sole channel + drop fpm .deb → Phase 58.
- Full-matrix bats + QEMU validation gate → Phase 59.

</deferred>
