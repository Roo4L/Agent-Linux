# AgentLinux — Strategy

> Last reviewed: 2026-05-23

## What we're solving

No one is currently responsible for making the agent-on-Linux story work
end to end. The distro maintainer ships Linux; the language vendor ships
Node.js; the agent vendor ships Claude Code. Each works correctly on its
own. The gaps between them do not — and the gaps are where users live:
install ownership (EACCES on `sudo npm install -g`), version compatibility
(upstream releases that break the combo with the rest of the agent
toolchain), distro fragmentation (apt vs dnf vs pacman),
brownfield migration (every host has its own pre-existing setup),
supply-chain trust (npm provenance, Sigstore, SLSA, and cosign exist as
partial solutions, but coverage is sparse and no aggregated signal tells
you which release of the curated combo is safe to bump to).

Each user is forced to be the integrator, and each user gets the
integration wrong in their own way.

AgentLinux exists to own those gaps. The v0.3.0 plugin closed the
install-ownership gap on clean Ubuntu hosts (AGT-02 green against the
live Anthropic CDN). The other gaps remain open; closing them as a
coherent set — not as one-off workarounds — is the multi-year work that
justifies the project beyond v0.3.0.

## Our bets

- **Installable plugin over custom distro.** v0.2.0 was a custom Ubuntu
  spin. The v0.2.0 → v0.3.0 pivot on 2026-04-18 traded the boot-image
  surface for a curl-pipe-bash plugin that meets users where they are.
  (ADR-001; VISION.md "We meet users on their distribution.")
- **Behaviors as spec, not implementation.** The bats suite at
  `tests/bats/` is the contract. Implementation can change freely as long
  as the BHV / RT / AGT / CLI / CAT / INST tests stay green. (ADR-002.)
- **Curated combos over user-assembled stacks.** Every release ships a
  `pinned_version` set we have exercised together on the Docker + QEMU
  matrix. We hold at the last-known-good combination; the user decides
  when to move. ([ADR-011](decisions/011-stability-first-version-pinning.md),
  [STABILITY-MODEL.md](STABILITY-MODEL.md).)
- **Infrastructure, not an agent product.** We provision the environment
  in which agents run. We do not build agents, prompt-injection guardrails,
  or model-layer defenses. The catalog stays narrow as a consequence.
  (VISION.md non-goal.)

These choices reinforce each other. The plugin format (bet #1) lets us
version a curated combo (bet #3) without owning a distribution
maintainer's work. Behavior-test contracts (bet #2) make the curated
combo (bet #3) safe to bump — implementation can change as long as the
contracts hold. Infrastructure framing (bet #4) keeps the catalog small
enough for one maintainer plus AI agents to keep curated combos green.

## Guiding policy

The policy decides which gap to close next and what to say no to until
that work lands.

**What we prioritize:**

- Close the gaps that bite the maintainer first. First-person friction
  is the canonical signal for which gap to attack next; without it we are
  guessing. Today that means brownfield Ubuntu support followed by
  AlmaLinux (the maintainer's work environment).
- Close each gap as infrastructure that other gap-closing work can build
  on, not as a one-off workaround. A brownfield detector that hardcodes
  Claude Code paths is a workaround; one that exposes a typed reuse /
  remediate / consent primitive is infrastructure.
- Extend what already works rather than build parallel mechanisms. The
  per-user npm prefix becomes the brownfield-aware installer's reuse
  primitive; the curated combo becomes the per-distro snapshot.

**What we downprioritize (and therefore say no to):**

- Closing gaps we don't have first-person friction on. Supply-chain trust
  is a real gap — we will not commit to closing it until we have felt a
  supply-chain attack, because the work otherwise drifts toward
  aspirational defenses.
- Growing surface area before the current gap is closed. Broader catalog
  admission, more distros, public engagement — all wait until brownfield
  and AlmaLinux land.
- Owning gaps that belong to other actors. Model-layer guardrails belong
  to model vendors; upstream package source review belongs to package
  maintainers; kernel hardening belongs to the distro. Our gaps are the
  ones nobody else is sitting on.
- Closing gaps with workarounds rather than primitives. If the brownfield
  work ships as a pile of one-off checks that hardcode catalog package
  names, it is technical debt, not infrastructure.

**How we'd know the strategy was wrong:**

- If a vendor (Anthropic, OpenAI, etc.) closes the gaps themselves — a
  native Linux runtime that owns install, update, and version
  compatibility — AgentLinux becomes redundant. The integration thesis
  was right but someone else got there first.
- If users prefer hand-install velocity over curated stability — they'd
  rather get the latest upstream release immediately than wait for a
  CI-verified combo — the curated-combo bet was wrong.
- If brownfield + AlmaLinux land and the maintainer still does not use
  AgentLinux daily, the diagnosis was wrong about the integration
  framing (it wasn't an integration problem, it was something else).

Time-ordered work against these conditions lives in
[docs/ROADMAP.md](ROADMAP.md).

## Execution principles

- **First-person friction wins.** We work on problems we have personally
  hit while running agents on Linux. Outside requests, market signals,
  and competitor moves inform our thinking; they do not authorize work.
  Maintainer friction is the canonical signal.

- **Human-first surfaces.** Every surface a user touches — installer,
  CLI, documentation, landing page — is designed for a human to operate
  directly, not for an agent to drive on the user's behalf. Install is
  one command. Commands read like English. Documentation is progressive:
  a user reads what they need at their current depth without slogging
  through reference manuals. We refuse complexity in user-facing surfaces
  even when the implementation underneath is intricate.

- **Three dimensions of package readiness.** A catalog package is ready
  to ship when we have verified all three:
  1. **Clean install** — no warnings, errors, or recovery prompts.
  2. **Clean usage path** — the package works as advertised on first
     use. Claude Code is ready to run; GSD's commands surface inside
     Claude Code; nothing prints `✗ Auto-update failed · Try claude
     doctor or npm i -g …`. If we disable an upstream auto-update, we
     do it the way the package expects — not by leaving the user with a
     broken-looking message.
  3. **Clean uninstall** — no orphan dependencies, config residue, or
     polluted state. User data may be preserved behind an interactive
     confirmation so the user can reinstall later without losing their
     settings.

- **Survives without the maintainer.** We build AgentLinux to keep its
  current feature surface alive without maintainer attention in the
  loop. Adding new capabilities needs a human; keeping shipped
  capabilities alive does not. Our roadmap commits to upstream updates
  landing automatically, the curated combo retesting itself on a
  schedule, and regressions surfacing to a queue rather than a person.
  Autonomy infrastructure comes before new features.

## Related

- [docs/VISION.md](VISION.md) — the canonical "what we want to be" doc this strategy operationalizes.
- [docs/ROADMAP.md](ROADMAP.md) — the time-ordered work that follows from this strategy.
- [ADR-015](decisions/015-agenda-redefinition.md) — the framing decision (two pillars + vision/strategy split, 2026-05-16).
- [ADR-002](decisions/002-behavior-contract-framing.md) — behavior tests are the spec.
- [ADR-004](decisions/004-per-user-npm-prefix.md) — per-user npm prefix (no `sudo npm install -g`).
- [ADR-011](decisions/011-stability-first-version-pinning.md) — stability-first version pinning.
- [docs/STABILITY-MODEL.md](STABILITY-MODEL.md) — the user companion to ADR-011; mechanizes the "curated combos" bet.
- [docs/HARNESS.md](HARNESS.md) — review feedback loop + reviewer-by-file-type matrix.
- [Jira AL-7](https://copiedwonder.atlassian.net/browse/AL-7) — v0.3.3 agenda redefinition epic.
