# Pillar 2 Exploration — Stability + Time-to-Productive

> Phase 12 verdict. Phase 14 lifts the `## Decision summary` section verbatim
> into `docs/STRATEGY.md` Pillar 2.
>
> Locked: 2026-05-10. Source raw material: `.planning/research/SUMMARY.md` §4
> (agent-evaluation landscape survey), `.planning/research/FEATURES.md`
> (candidate pillar substance), `.planning/research/PITFALLS.md` (voice-rule
> and rejected-alternatives discipline). Locked decisions:
> `.planning/phases/12-pillar-2-exploration/12-CONTEXT.md`.

## Framing

AgentLinux is *infrastructure*, not an agent product. We provision the
environment in which agents run; we do not run, score, or compare agents
ourselves. That distinction is load-bearing for everything that follows: the
research raw material surfaced an agent-evaluation landscape (terminal-bench,
Multi-Docker-Eval, τ-bench `pass^k`, SWE-bench Verified / Live, Aider
polyglot, Helicone, Langfuse) as candidate pillar-2 substance, but those
suites measure agents that would run *on top of* AgentLinux, not the value
AgentLinux delivers. Landscape we cite, not territory we compete in.

The value the user gets is what they get *automatically* on install: a
vetted, opinionated environment where the agents they run are more reliable
and more productive than on a hand-rolled `npm install -g` setup. The
mechanism is **curated default version sets + compat-guarded updates +
opinionated bundles** — three positions an infrastructure product can take
that a thin wrapper cannot. Pillar 2's name — **stability + time-to-productive**
— captures both halves: stability keeps the curated combo from breaking under
upstream drift; time-to-productive is the user-visible payoff (an agent that
"just works" the first time, with the right tools already there).

## What pillar 2 commits to

Two table-stakes (already shipped, delivered-fact voice) and three
differentiators (forward-looking, voice rule applies). The canonical
statement of each is in the **Decision summary** below; this section provides
the framing context.

**Table-stakes** are the keystone pain points AgentLinux already eliminates:
- **T-1 — AGT-02 zero-EACCES self-update.** Per ADR-004 (per-user npm prefix
  as the keystone ownership decision), the curated `claude` binary
  self-updates against the live Anthropic CDN with zero EACCES and zero sudo
  prompts. Release-gated by the AGT-02 bats test against the live CDN.
- **T-2 — ADR-011 stability model.** Each catalog agent carries
  `pinned_version`; the curated combo is what we test, ship, and serve as
  default. The TST-08 4-gate release pipeline gates every release.

**Differentiators** are the positions our roadmap commits to:
- **D-1** — compat-guarded default version set: hold last-known-good on
  upstream breakage, roll forward only after verified-compatible CI.
- **D-2** — preset framework: `bare` / `must-haves` / `optimum` selectable
  at install time.
- **D-3** — profile framework: orthogonal use-case bundles composable with
  presets.

The mechanism for each (CI policy vs `agentlinux upgrade` reconciliation vs
both for D-1; specific contents for D-2 and D-3) locks at the
`next-milestone` framework-spec deliverable.

## Considered and rejected — agent-focused benchmarks

Per Pitfall #13 (every rejected pillar candidate gets one named line so future
readers don't re-litigate), we considered and rejected the agent-evaluation
landscape — terminal-bench, Multi-Docker-Eval, tau-bench `pass^k`, SWE-bench
Verified / Live, Aider polyglot, Helicone, Langfuse — as load-bearing pillar
substance. Shared rejection rationale: they measure the agents that run on
top of AgentLinux, not the infrastructure underneath. Per the
time-to-productive vs SWE-bench-Verified honesty rule, we do not claim to
change Claude's SWE-bench Verified score; we change time-to-productive (time
from install to first useful agent run on a fresh box). Observability vendors
(Helicone, Langfuse), if catalogued, belong as opt-in entries per ADR-003 —
never pillar commitments.

## Decision summary

**Pillar name:** Stability + time-to-productive.

**Priority tag:** `next-milestone` (locked at milestone-open 2026-05-09;
reaffirmed in this exploration 2026-05-10).

**Table-stakes (already shipped, delivered-fact voice):**

- **T-1 — AGT-02 zero-EACCES self-update.** The curated `claude` binary
  self-updates against the live Anthropic CDN with zero EACCES and zero sudo
  prompts. Release-gated via TST-08; the AGT-02 bats test
  (`tests/bats/51-agt02-release-gate.bats`) is the evidence and runs against
  the live CDN every release. Recipe:
  `plugin/catalog/agents/claude-code/install.sh`.
- **T-2 — ADR-011 stability model.** `pinned_version` per catalog agent +
  curated combo (claude-code + gsd + playwright-cli) + TST-08 4-gate release
  pipeline (pre-commit → docker matrix → QEMU matrix → pinned-combo re-run).
  Docker and QEMU matrices both cover Ubuntu 22.04 + 24.04 + 26.04; the
  pinned-combo gate re-runs the catalog combo end-to-end on Ubuntu 24.04
  Docker as a distinct release-gate signal. See
  [`docs/STABILITY-MODEL.md`](../STABILITY-MODEL.md).

**Differentiators (forward-looking, voice rule applies):**

- **D-1 — Compat-guarded default version set.** We will hold the default
  version set at last-known-good when upstream breaks a curated combo, and
  our roadmap commits to rolling forward only after a verified-compatible
  upstream fix lands in CI. Position: most `npm install -g` paths hand the
  user the latest immediately, even when "latest" is broken with the rest of
  the toolchain; we take the opposite position. *Mechanism (CI matrix vs
  `agentlinux upgrade` reconciliation vs both) locks at `next-milestone`
  framework-spec.*
- **D-2 — Preset framework.** Our roadmap ships three install-time presets
  (`bare` / `must-haves` / `optimum`); RTK (Rust Token Killer —
  token-efficiency proxy) is the canonical `optimum` example; `bare`
  preserves the ADR-003 no-default-agents invariant. *Specific contents lock
  at `next-milestone` framework-spec.*
- **D-3 — Profile framework.** Our roadmap ships orthogonal use-case
  profiles (e.g. `web-development` = playwright-cli + browser deps),
  composable with presets, e.g. `agentlinux install --preset optimum
  --profile web-development`. *Specific profile list locks at `next-milestone`
  framework-spec.*

**Explicit non-goals (≥2):**

- **NG-1 — Not running, scoring, or comparing agents.** Agent-focused
  benchmarks (terminal-bench, Multi-Docker-Eval, tau-bench, SWE-bench, Aider
  polyglot) are landscape we cite, not pillar substance.
- **NG-2 — Not maintaining backports, forks, or downstream patches of
  upstream packages.** We pin, hold, and wait for upstream fixes. Deliberate
  scope-shrink: we are not signing up for distribution-style maintenance.
- **NG-3 — Not publishing per-model performance scores.** Stronger
  restatement of NG-1's specific case for clarity.
- **NG-4 — Not becoming an agent observability product.** Helicone /
  Langfuse, if catalogued, belong as opt-in entries (per ADR-003), not as
  pillar commitments.

**Today / Direction content seed:**

- **Today (v0.3.0 reality, delivered-fact voice):** AGT-02 zero-EACCES
  self-update release-gate green; ADR-011 `pinned_version` + TST-08 4-gate
  release pipeline; curated combo (claude-code + gsd + playwright-cli)
  tested in Docker + QEMU on Ubuntu 22.04 + 24.04 + 26.04 every release. No
  preset framework yet; no profile framework yet; no formal compat-guarded
  update flow beyond TST-08's manual gate.
- **Direction (`next-milestone`, forward-looking voice):** Our roadmap
  commits to a preset framework (`bare` / `must-haves` / `optimum`), a
  profile framework (orthogonal use-case bundles), and a compat-guarded
  update flow (we hold the default set on upstream breakage and roll forward
  only after a CI-verified fix). The `next-milestone` priority tag is
  reaffirmed.
