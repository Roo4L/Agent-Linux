# Phase 53 Agent-Loop Metrics (RUST-03)

First-class de-risking deliverable, not a side note. The stack-reconsideration
decision (`docs/research/v0.3.0/stack-reconsideration.md` §7) accepts three
Rust-with-Claude costs that had **no per-language Opus/Sonnet-4.x data** —
every prior datapoint is 3.7 Sonnet. This spike generates the first such data
on **our model** (Opus 4.8, 1M context) against **our code**. The measured
numbers below are the go/no-go calibration for the ~7k-LOC bulk port
(phases 54–59: ~2.8k CLI + ~4.3k provisioner + test port).

## Per-unit agent-loop cost

Model: Claude Opus 4.8 (1M context). Iterations-to-green = edit → `cargo test` /
`cargo clippy` cycles until the unit is green. Hallucinations = a non-existent
crate/API proposed in a `Cargo.toml` or `use`. cargo-timeouts = tool-timeouts
on `cargo build`/`test`.

| Unit | Iters-to-green | Hallucinations | cargo-timeouts | Wall-clock | Tokens | Notes |
|------|----------------|----------------|----------------|------------|--------|-------|
| workspace + static-musl build (53-01) | 1 | 0 | 0 | ~11s cold build | n/a | `ldd` static on first try; pinned crates resolved on first `cargo build` |
| semver_shim (53-01) | 1 (+1 review) | 0 | 0 | <10s incremental | n/a | 14 tests green first run; +1 test from a review-driven idempotency fix (normalize_range double-comma) |
| classify (53-01) | 1 | 0 | 0 | <10s | n/a | 7 golden-corpus states green first run |
| divergence (53-01) | 1 | 0 | 0 | <10s | n/a | 13 golden-corpus rows green first run |
| **reuse-decision + bats (53-02)** | **1** | **0** | **0** | **<1s test; ~0.8s musl build** | n/a | 9 unit tests + 6 REUSE-03 branches green first run; one clippy `doc_overindented_list_items` + one rustfmt reflow auto-fixed pre-commit (formatting, not logic) |

Notes on the 53-02 unit (the gnarly provisioner exemplar the decision quotes):
- **Iterations-to-green = 1.** The `agent_decision` port compiled and passed all
  9 core unit tests on the first `cargo test`. No logic iteration was needed —
  the bash predicate order (empty/absent/unknown/broken/path-mismatch/gsd-system)
  ported one-to-one into a `Decision` enum + a single `fn`.
- **Predicate 3 (semver) was NOT evaluated here**, matching the bash contract —
  the CLI layers version-in-window on later. So the exact "bash stops at 2 of 3
  predicates because semver is hard" pain the decision quotes is now *removed* in
  Rust (the semver_shim from 53-01 makes predicate 3 a one-liner when Phase 56
  wires it), while parity is preserved for this spike.
- **Two mechanical pre-commit fixups** (a clippy doc-indent lint + a rustfmt
  arg-wrap) were needed but are formatting-only, not logic iterations or
  hallucinations. Counted separately so the iterations-to-green figure stays
  honest: the *logic* was right first time.

## Crate-hallucination + cargo-timeout tally (both plans)

| Incident type | 53-01 | 53-02 | Total | Benchmark reference |
|---------------|-------|-------|-------|---------------------|
| Crate/API hallucinations | 0 | 0 | **0** | worst measured is Opus-4 ~27% ([halluc] in §7) — this spike added **no new crate** in 53-02; 53-01's 4 crates (`semver`/`serde`/`serde_json`/`thiserror`) all resolved on first build |
| cargo-compile-timeouts | 0 | 0 | **0** | the open Claude Code cargo-timeout bug (§7 [ccto]) did **not** fire; cold build ~11s, incrementals <10s, musl release build 0.8s |

**Interpretation vs the §7 accepted-cost estimate:** the two headline Rust risks
the milestone budgeted for (worst-in-class crate hallucination, cargo-timeout
loop friction) were **not observed at all** across the two plans / five ported
units on Opus 4.8. The dep tree is deliberately tiny and pinned, which is the
exact mitigation §7 proposed — and it held.

## Parity surprises (feeds Phase 54 TEST-04 audit)

- **53-01:** one node-semver edge beyond the research parity table — `normalize_range`
  was not idempotent on already-comma'd compound ranges (`">=2.0.0, <3.0.0"`
  → doubled comma → `VersionReq::parse` reject). Latent for the current
  space-separated catalog, but fixed + regression-tested in 53-01 (commit 584f10f).
  Phase 54's TEST-04 audit should re-exercise `normalize_range` on comma-form input.
- **53-02:** none. The reuse predicate is pure string/path comparison with no
  semver, so there was no node↔dtolnay divergence surface. The **one integration
  surprise** (not a parity surprise) is recorded below under Docker-bats friction.

## Docker / bats-integration friction finding (GATE-01)

The GATE-01 evidence run used the OOM-safe targeted approach (the full Docker
bats suite OOMs ~test 131 in this VM per MEMORY.md; `tests/docker/run.sh` only
runs the full suite, so it was NOT used). Instead: built the static-musl binary,
started the cached `agentlinux-test:ubuntu-24.04` container with run.sh's
systemd/`--privileged` flags, staged sources to `/opt/agentlinux-src`, spliced
the pre-built CLI bundle, ran `agentlinux-install`, then ran only the ported-surface
bats files with `AGENTLINUX_RUST_BIN` pointed at the musl artifact.

**Result — actual pass counts:**
- `13-reuse.bats`: **32/32 pass, 0 fail, 0 skip** — including all six REUSE-03
  `agent_decision` branches (absent→create, healthy+canonical→reuse,
  healthy+wrong-path→remediate, gsd@VERSION→reuse, broken→remediate,
  unknown-id→create) AND the two brownfield E2E tests that drive a real
  `agentlinux-install` provision through the Rust-backed shim.
- `14-remediate.bats`: **53/56 completed green, 0 fail.** Tests 54–56 are
  REMEDIATE-04 uninstall/reinstall E2E (NOT the ported surface — they never call
  `reuse::agent_decision`) and each exceeds a 5-minute per-run wall-clock in this
  VM; this is a **time bound, not OOM, not a failure**. The reuse-consuming
  foundation tests all pass, including `collect_all_decisions` (which iterates
  `${!REUSE_AGENT_CANONICAL_PATHS[@]}` at `remediate.sh:288` and calls the
  Rust-backed `reuse::agent_decision` for every agent) and
  `reuse::user_decision predicate behavior unchanged`.

**Friction encountered (the spike's actual integration finding):**
1. **PATH-resolution of the shim binary.** The first `agentlinux-install` run
   inside the container failed at `agents.sh:75` with `agentlinux: command not
   found` — the installer's own `remediate::collect_all_decisions` calls
   `reuse::agent_decision`, which shells to `${AGENTLINUX_RUST_BIN:-agentlinux}`,
   and bare `agentlinux` was not on the installer's PATH. Re-running with
   `AGENTLINUX_RUST_BIN` exported to the installer fixed it (exit 0).
   **Deployment implication for Phase 56/57:** when the shim ships for real, the
   Rust `agentlinux` binary MUST be on PATH (or `AGENTLINUX_RUST_BIN` pinned)
   *before* the provisioner's decision phase runs — the current 50-registry-cli
   ordering installs the CLI, but the reuse decision fires earlier in
   `collect_all_decisions`. The env-override fallback (`AGENTLINUX_RUST_BIN`) is
   the correct seam for pinning an absolute path; the fail-closed behavior
   (missing binary → `command not found` → non-zero, surfaced as a bats failure,
   never a silent mis-verdict) is exactly the T-53-04 mitigation working.
2. **Per-test wall-clock, not OOM.** The targeted-file approach avoided the OOM,
   but the heaviest REMEDIATE-04 E2E tests (real uninstall+reinstall of catalog
   agents) individually approach the 5-minute cap. These are out of the ported
   surface; CI's fresh runners with the full 60-minute matrix cap cover them.

**Deferred to the orchestrator:** the formal full-matrix Docker-bats confirmation
across all four distro arms (ubuntu-22.04/24.04/26.04 + almalinux-9) runs on the
CI `rust` + `bats-docker` jobs on fresh runners. The three REMEDIATE-04 E2E tail
tests (54–56 of 14-remediate.bats) were not run to completion locally due to the
per-run wall-clock; they do not exercise the ported `reuse::agent_decision`
surface. **No bats file was modified** (`git diff tests/bats/` empty), so the CI
matrix runs the identical spec against the Rust build.

## Verdict for the bulk port (54–59)

**GO.**

Justification against the stack-reconsideration §7 accepted-cost estimate:
- **Iterations-to-green = 1 for every one of the five ported units** (workspace,
  semver_shim, classify, divergence, reuse-decision). The logic was correct on
  first `cargo test` in each case; only mechanical formatting fixups (clippy
  doc-indent, rustfmt wrap) and one review-driven hardening test were added.
  This is materially *better* than the "slower/pricier loops" §7 budgeted for.
- **Zero crate hallucinations** across both plans (vs the worst-measured Opus-4
  ~27% the milestone hedged against). The pinned, tiny dep tree — §7's own
  proposed mitigation — held with room to spare.
- **Zero cargo-timeouts** (vs the open Claude Code cargo-timeout bug §7 flagged).
  Cold build ~11s, incrementals <10s, musl release 0.8s. CI's `Swatinem/rust-cache`
  keeps this bounded on fresh runners.
- **The exact sync-pain exemplar the decision quotes is removed.** `reuse::agent_decision`
  — the "bash stops at 2 of 3 predicates because semver is hard, and hand-maintains
  a CANONICAL_PATHS map that must stay byte-identical to detect.ts" unit — ported
  cleanly, and the language-agnostic bats spec (ADR-002) validated the Rust build
  **unchanged (zero bats edits)**. Both halves of the thesis are proven.

**Caveats to manage in 54–59 (go-with-eyes-open, not blockers):**
- The ported units so far are pure-logic and small; the ~4.3k-LOC provisioner
  port (Phase 57) will hit more I/O-boundary + adapter code where the pure/thin-bin
  split and PATH-ordering of the shim binary (friction #1 above) need care.
- Token cost per unit was not instrumented numerically this session (the harness
  did not expose per-unit token counts); wall-clock is the available proxy and it
  is small. Phase 54 should capture token cost if the runtime exposes it, to close
  the last §7 unknown.
- The three REMEDIATE-04 E2E tests need the CI matrix (or a higher local
  wall-clock budget) for full local confirmation — not a Rust-port risk, a
  test-runtime one.

## RUST-02 "Docker matrix" decision

The roadmap phrase "added to the Docker matrix" (RUST-02) is resolved to the
**LITERAL spike reading** (research Open-Q1 / A6): a **separate gated `rust` job
in `.github/workflows/test.yml`** that runs on every PR — build + `cargo fmt
--check` + `cargo clippy -D warnings` + `cargo test --all` + a static-musl build
with the `ldd 'not a dynamic executable'` assertion. The job mirrors the
`cli-unit` guard shape (`needs: changes`; `ready=false` when no code changed or
`rust/Cargo.toml` is absent) so the required-check context always reports and a
dev-only change reports green fast.

The **stronger reading** — building the musl binary *inside* each `bats-docker`
container so every distro arm exercises the actual static artifact per-distro —
is **Phase 59's GATE-02 endgame** and is explicitly out of scope for this spike.
For the spike, one musl artifact copied into a targeted bats container for the
ported surface (done above, 13-reuse.bats 32/32) is the smallest sufficient seam.

## GATE-05 rollback note

The entire Rust track is **additive and per-phase revertible without touching
master**:

- **Where the work lives:** all commits are on branch `worktree-stack-revisiting`;
  `master` is untouched (still at `f14c092` as of 53-01; this plan adds no master
  commits). The v0.4.0 milestone branch merges to master only when the milestone
  ships.
- **What the track adds (all additive):**
  1. a new top-level `rust/` directory (workspace + `agentlinux-core` + `agentlinux`
     bin) — deleting it removes the entire Rust surface;
  2. a new gated `rust` CI job + a `rust/**` entry in the `changes` paths-filter
     in `test.yml` — removing the job block + the filter line restores the
     TS/bash-only CI;
  3. a ~3-line shim body in `plugin/lib/reuse/agents.sh::reuse::agent_decision`
     that forwards to the Rust bin — reverting that single commit (`db219d0`)
     restores the original in-bash predicate logic (the `REUSE_AGENT_CANONICAL_PATHS`
     map + `REUSE_GSD_SYSTEM_PATH` were deliberately **kept**, so the bash fallback
     path is intact and `remediate.sh:288` keeps iterating the map either way).
- **How to revert the spike:** `git revert db219d0 a1f9618` (the shim commit +
  the CI-job commit) and `git rm -r rust/` restores the TS/bash-only build with
  **zero master impact**.
- **Why a red spike can't block a master hotfix (GATE-05):** the `rust` CI job is
  gated (`needs: changes`; skips its steps when `rust/Cargo.toml` is absent or no
  code changed) and reports green-fast on dev-only / non-Rust changes, so a
  master hotfix that touches no Rust never waits on — and is never blocked by —
  a red Rust job. The track is strictly opt-in until the milestone chooses to
  merge it.

[halluc]: docs/research/v0.3.0/stack-reconsideration.md §7 — Rust crate hallucination benchmark
[ccto]: docs/research/v0.3.0/stack-reconsideration.md §7 — Claude Code cargo-timeout bug
