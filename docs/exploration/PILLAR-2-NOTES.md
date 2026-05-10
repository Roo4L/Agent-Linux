# Pillar 2 Exploration — Stability + Time-to-Productive

> Phase 12 verdict. Phase 14 lifts the `## Decision summary` section verbatim
> into `docs/STRATEGY.md` Pillar 2.
>
> Locked: 2026-05-10. Source raw material: `.planning/research/SUMMARY.md` §4 +
> `.planning/research/FEATURES.md` + `.planning/research/PITFALLS.md`. Locked
> decisions: `.planning/phases/12-pillar-2-exploration/12-CONTEXT.md`.

## Framing

AgentLinux is *infrastructure*, not an agent product. We provision the
environment in which agents run; we do not run, score, or compare agents
ourselves. That distinction is load-bearing for everything that follows: the
research raw material in `.planning/research/SUMMARY.md` §4 surfaced an
agent-evaluation landscape (terminal-bench, Multi-Docker-Eval, τ-bench
`pass^k`, SWE-bench Verified / Live, Aider polyglot, Helicone, Langfuse) as
candidate pillar-2 substance, but those suites measure the agents that would
run *on top of* AgentLinux, not the value AgentLinux delivers. We treat them
as landscape we cite, not territory we compete in.

The value the user gets from AgentLinux — the value pillar 2 commits to — is
what they get *automatically* when they install us: a vetted, opinionated
environment where the agents they run are more reliable and more productive
than they would be on a hand-rolled `npm install -g` setup. The mechanism is
**curated default version sets + compat-guarded updates + opinionated
bundles** — three concrete positions an infrastructure product can take that
a thin wrapper or a single-tool installer cannot. Pillar 2's name —
**stability + time-to-productive** — captures both halves: stability is what
keeps the curated combo from breaking under upstream drift; time-to-productive
is the user-visible payoff (an agent that "just works" the first time, with
the right tools already there).

## What pillar 2 commits to

Pillar 2's substance is two table-stakes (already shipped) and three
differentiators (forward-looking, locked in concept). The canonical list lives
in the trailing **Decision summary** — Phase 14 lifts that section verbatim.
This subsection introduces the load-bearing pieces and points at their
evidence.

### Table-stakes (already shipped)

**T-1 — AGT-02 zero-EACCES self-update.** The curated `claude` binary
self-updates against the live Anthropic CDN with zero EACCES errors and zero
sudo prompts. This is the keystone pain point AgentLinux exists to eliminate
(per ADR-004 — per-user npm prefix as the keystone ownership decision); the
AGT-02 bats test in `tests/bats/51-agt02-release-gate.bats` is the release
gate that proves it on every release, against the live CDN. Recipe at
`plugin/catalog/agents/claude-code/install.sh` uses the native installer path
to avoid the recursive-shim trap. T-1 is delivered fact, not aspiration.

**T-2 — ADR-011 stability model.** Each catalog agent carries a
`pinned_version`; the curated combo (claude-code + gsd + playwright +
agentlinux-cli) is what we test, what we ship, and what users get by default.
The TST-08 4-gate release pipeline (pre-commit → docker matrix → QEMU matrix
→ pinned-combo verification) gates every release; the pinned combo runs on
Ubuntu 22.04 + 24.04 in QEMU before the tarball ships. See
[`docs/STABILITY-MODEL.md`](../STABILITY-MODEL.md) for the user companion.
T-2 is delivered fact.

### Differentiators (forward-looking — voice rule applies)

**D-1 — Compat-guarded default version set.** Most `npm install -g` paths
hand the user the latest immediately, even when "latest" is broken with the
rest of the toolchain. Our roadmap takes the opposite position: when an
upstream package update breaks the curated combo (e.g. a Claude Code update
breaks GSD), we will hold the default set at last-known-good, monitor for the
upstream fix, verify compatibility on the new combo via CI, and roll forward
only when a verified-compatible combo emerges. The user gets a stable
environment without tracking upstream issues themselves. Side-effect, not a
commitment: our CI matrix may surface upstream breakage first and we may
file the upstream issue — good citizenship, not a pillar promise. D-1
commits to the *position*; the mechanism (CI matrix vs `agentlinux upgrade`
reconciliation policy vs both) locks in the implementation milestone.

**D-2 — Preset framework: `bare` / `must-haves` / `optimum`.** Our roadmap
ships three install-time presets selectable at install time. `bare` installs
nothing — preserving the ADR-003 no-default-agents invariant for users who
want to opt in tool-by-tool. `must-haves` installs canonical universal
coding-agent tools (Claude Code, Codex named illustratively; the specific
list locks when the framework ships). `optimum` is `must-haves` plus
opinionated, well-tested extras that improve the agent experience without the
user having to know about each one individually — RTK (Rust Token Killer —
token-efficiency proxy) is the canonical `optimum` example. v0.3.3 commits
to the *concept*; specific contents lock when the framework ships.

**D-3 — Profile framework: orthogonal to presets.** Our roadmap ships
use-case-specific bundles orthogonal to presets — `web-development` (the
canonical example: playwright-cli + browser deps) is one such profile.
Profiles compose with presets at install time, e.g. `agentlinux install
--preset optimum --profile web-development`. v0.3.3 commits to the *shape*;
the specific profile list and exact tools lock when the framework ships.

## Considered and rejected — agent-focused benchmarks

The research SUMMARY.md §4 surfaced an agent-evaluation landscape as
candidate pillar-2 substance. We reject the entire framing as load-bearing
pillar substance — AgentLinux is infrastructure, not an agent product, and
agent-focused benchmarks measure the wrong thing for our pillar. We document
each suite below as research raw material with a one-line rejection rationale,
honoring Pitfall #13's rejected-alternatives discipline.

- **terminal-bench** — measures agents operating real CLI environments.
  Closest analog to "agent runs on top of AgentLinux", but still measures
  the agent, not the infrastructure. Considered as a possible measurement
  layer for `time-to-productive`; rejected as pillar substance because the
  credible measurable claims AgentLinux can make are not benchmark scores.
- **Multi-Docker-Eval** — env-build efficiency reporting (token + wall-clock
  + image size). Methodologically the closest precedent to "what AgentLinux
  would even measure if it measured anything", but AgentLinux is not a build
  product; we provision agent-user environments, not Docker images.
- **tau-bench / `pass^k`** — Sierra Research's reliability-first metric (vs
  `pass@k`). Cited as landscape because `pass^k` is the right metric *if* a
  stability-pillar product ever publishes reliability scores. v0.3.3 commits
  to no such publication; a future milestone may revisit.
- **SWE-bench Verified / SWE-bench Live / Aider polyglot** — the field's
  reference benchmarks. Cited as the dominant landscape AgentLinux is *not*
  trying to climb. Per the time-to-productive vs SWE-bench-Verified honesty
  rule from research, we do not claim to change Claude's SWE-bench Verified
  score; we change time-to-productive (the time from install to first useful
  agent run on a fresh box).
- **Helicone / Langfuse** — agent observability vendors. They remain opt-in
  catalog entries (per ADR-003 no-default-agents); not pillar commitments.
  AgentLinux does not bundle, brand, or compete on observability — if a user
  wants observability, the catalog makes it one command away.

## Decision summary

**Pillar name:** Stability + time-to-productive.

**Priority tag:** `next-milestone` (locked per user direction at
milestone-open 2026-05-09; reaffirmed in this exploration 2026-05-10).

**Table-stakes (already shipped, delivered-fact voice):**

- **T-1 — AGT-02 zero-EACCES self-update.** The curated `claude` binary
  self-updates against the live Anthropic CDN with zero EACCES and zero sudo
  prompts. Release-gated via TST-08; the AGT-02 bats test
  (`tests/bats/51-agt02-release-gate.bats`) is the evidence and runs against
  the live CDN every release. Recipe:
  `plugin/catalog/agents/claude-code/install.sh`.
- **T-2 — ADR-011 stability model.** `pinned_version` per catalog agent +
  curated combo (claude-code + gsd + playwright + agentlinux-cli) + TST-08
  4-gate release pipeline (pre-commit → docker matrix → QEMU matrix →
  pinned-combo). Tested on Ubuntu 22.04 + 24.04 in QEMU every release. See
  [`docs/STABILITY-MODEL.md`](../STABILITY-MODEL.md).

**Differentiators (forward-looking, voice rule applies):**

- **D-1 — Compat-guarded default version set.** We will hold the default
  version set at last-known-good when upstream breaks a curated combo, and
  our roadmap commits to rolling forward only after a verified-compatible
  upstream fix lands in CI. Position: most `npm install -g` paths hand the
  user the latest immediately, even when "latest" is broken with the rest of
  the toolchain; we take the opposite position.
- **D-2 — Preset framework.** Our roadmap ships three install-time presets
  (`bare` / `must-haves` / `optimum`); RTK is the canonical `optimum`
  example; `bare` preserves the ADR-003 no-default-agents invariant.
- **D-3 — Profile framework.** Our roadmap ships orthogonal use-case
  profiles (e.g. `web-development` = playwright-cli + browser deps),
  composable with presets, e.g. `agentlinux install --preset optimum
  --profile web-development`.

**Explicit non-goals (≥2):**

- **NG-1 — Not running, scoring, or comparing agents.** Agent-focused
  benchmarks measure the wrong thing for our pillar; AgentLinux is
  infrastructure. We cite terminal-bench / Multi-Docker-Eval / tau-bench /
  SWE-bench / Aider polyglot as landscape and explicitly reject them as
  pillar-2 substance.
- **NG-2 — Not maintaining backports, forks, or downstream patches of
  upstream packages.** We pin, hold, and wait for upstream fixes. We do not
  carry patches downstream. Deliberate scope-shrink: we are not signing up
  to become a Linux-distribution-style maintenance burden.
- **NG-3 — Not publishing per-model performance scores.** Stronger
  restatement of NG-1's specific case for clarity.
- **NG-4 — Not becoming an agent observability product.** Helicone /
  Langfuse remain opt-in catalog entries (per ADR-003 no-default-agents),
  not pillar commitments. AgentLinux does not bundle, brand, or compete on
  observability.

**Today / Direction content seed:**

- **Today (v0.3.0 reality, delivered-fact voice):** AGT-02 zero-EACCES
  self-update release-gate green; ADR-011 `pinned_version` + TST-08 4-gate
  release pipeline; curated combo (claude-code + gsd + playwright +
  agentlinux-cli) tested in QEMU on Ubuntu 22.04 + 24.04 every release. No
  preset framework yet; no profile framework yet; no formal compat-guarded
  update flow beyond TST-08's manual gate.
- **Direction (`next-milestone`, forward-looking voice):** Our roadmap
  commits to a preset framework (`bare` / `must-haves` / `optimum`), a
  profile framework (orthogonal use-case bundles), and a compat-guarded
  update flow (we hold the default set on upstream breakage and roll forward
  only after a CI-verified fix). The `next-milestone` priority tag is
  reaffirmed.
