# AgentLinux — Strategy

> Last reviewed: 2026-05-19

## What we're solving

[docs/VISION.md](VISION.md) names what we want to be. This doc names the
bug-class we exist to eliminate so the bets that follow make sense.

On a stock Ubuntu host, `sudo npm install -g claude` writes binaries that
root owns; the agent then cannot self-update, and `claude update` either
fails with EACCES or silently re-writes a `/usr/local/bin/` shim that
breaks on the next launch. Around that core failure sit smaller ones:
dependency drift from un-curated `npm install -g` paths, inconsistent
agent-friendly defaults the user is expected to maintain, and missing
PATH wiring across cron, systemd, sudo, and non-interactive SSH. The
v0.3.0 plugin folds all of that into one install — agent user, per-user
npm prefix, six invocation modes, curated catalog. The EACCES class is
gone from the install path (AGT-02); the brownfield class is next.

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

## Where we are now

Our current goal is to ship the first usable release of AgentLinux for the
maintainer as canonical user. That means v0.3.4 Aware Installation Process
([AL-38](https://copiedwonder.atlassian.net/browse/AL-38)) — a
brownfield-aware installer that detects existing agent user / Node.js /
catalog packages, reuses what is compatible, remediates what is broken,
with a consent gate for mutations — followed by AlmaLinux support, the
first distro expansion past Ubuntu.

The v0.3.0 plugin ships against Ubuntu 22.04 / 24.04 / 26.04 with the
agent's zero-EACCES self-update behaviour locked by AGT-02; the v0.4.0
license flip made the project OSS-MIT on 2026-05-09. The v0.3.3
milestone — this strategy framing — closes once Phase 16's website
refresh ships.

## What's next

### Near-term

1. Finish v0.3.3 — this strategy doc plus Phase 16's website refresh.
2. Ship v0.3.4 Aware Installation Process
   ([AL-38](https://copiedwonder.atlassian.net/browse/AL-38)) — the
   brownfield installer that adopts existing setups instead of refusing
   to touch them.
3. Add AlmaLinux support — the first distro expansion past Ubuntu and
   the start of Pillar 1's reach.
4. OSS funding application — parallel / meta, not blocking engineering.

### Themes for v0.6+

#### Security Hardening

We carry an opportunistic security-hardening theme from Phase 13: a
capability-scoped sudoers profile replacing ADR-012's NOPASSWD ALL,
cosign-signed catalog releases, npm provenance verification at install
time, a bubblewrap-based per-recipe sandbox, and an iptables egress
allowlist for catalog recipes.
**Sequencing rationale:** Independent of the catalog-expansion track. We
pick the first defense to mature once the AL-38 brownfield work surfaces
which capabilities the agent actually needs in practice — that is the
gating signal for which NOPASSWD scope we can honestly cut.

#### Preset / profile framework + compat-guarded update flow

The Phase 12 differentiators: `bare` / `must-haves` / `optimum` presets,
`web-development`-style profiles, and a hold-and-wait-on-upstream-breakage
policy for the catalog update pipeline.
**Sequencing rationale:** Builds on the `pinned_version` foundation
already in v0.3.0; the work is mechanism design plus UX, not new product
surface. We land it before broader catalog expansion so new agents adopt
the preset / profile framework from day one.

#### Broader agentic-dev catalog

We expand the catalog toward critical mass: Cursor CLI, OpenAI Codex CLI,
aider, Continue, Goose — each admitted via the catalog admission contract
(behavior test, maintainer reputation, considered decision per VISION.md).
The current three-agent catalog is small on purpose, but small is also
the bottleneck for the engagement track below.
**Sequencing rationale:** Gates theme #4 (Public engagement). The current
release surface is too narrow to engage subscribers meaningfully; we
build critical mass first.

#### Public engagement

A low-overhead opt-in mailing list for release announcements, structured
feedback collection (issue templates, contributor invite paths in
CONTRIBUTING.md), and community-platform basics once the catalog warrants
them.
**Sequencing rationale:** Explicitly gated on theme #3 reaching critical mass. The current three-agent release is too tiny to engage subscribers meaningfully; we want a broader catalog before any public announcement.

## Execution principles

- **Voice rule** — Never `AgentLinux + present-tense verb` for unshipped
  behaviour. Forward-looking claims use "we" / "our roadmap" / an
  explicit milestone identifier as grammatical subject. Enforced by an
  automated grep gate on every authored doc. (VIS-07, STRATR-06.)
- **Behavior tests are the spec** — The bats suite at `tests/bats/` is
  the contract; implementation can vary as long as BHV / RT / AGT / CLI
  / CAT / INST tests stay green. ([ADR-002](decisions/002-behavior-contract-framing.md).)
- **Evidence-cite discipline** — Phase-close audits (`<phase-NN>-AUDIT.md`)
  cite file paths, line ranges, commit hashes, and grep transcripts per
  requirement. The audit is the gate. (TST-07; 14-AUDIT.md precedent.)
- **Curated-combo testing** — Every release ships a `pinned_version`
  set tested end-to-end by the 4-gate release pipeline (pre-commit →
  Docker matrix → QEMU matrix → pinned-combo gate). A red combo cannot
  ship. ([ADR-011](decisions/011-stability-first-version-pinning.md),
  TST-08, [STABILITY-MODEL.md](STABILITY-MODEL.md).)
- **No `sudo npm install -g` anywhere** — All catalog installs run as
  `sudo -u agent -H npm install -g`. The whole point of the v0.3.0
  plugin is to eliminate the EACCES + recursive-shim bug class; the
  installer enforces it. ([ADR-004](decisions/004-per-user-npm-prefix.md).)
- **Reviewer feedback loop** — Substantive changes to `plugin/` /
  `tests/` / `docs/` run through the project-scoped review subagents
  (bash-engineer, qa-engineer, security-engineer, ai-deslop, etc.)
  before merge. ([HARNESS.md](HARNESS.md) §4, ADR-010.)

## Related

- [docs/VISION.md](VISION.md) — the canonical "what we want to be" doc this strategy operationalizes.
- [ADR-015](decisions/015-agenda-redefinition.md) — the framing decision (two pillars + vision/strategy split, 2026-05-16).
- [ADR-002](decisions/002-behavior-contract-framing.md) — behavior tests are the spec.
- [ADR-004](decisions/004-per-user-npm-prefix.md) — per-user npm prefix (no `sudo npm install -g`).
- [ADR-011](decisions/011-stability-first-version-pinning.md) — stability-first version pinning.
- [docs/STABILITY-MODEL.md](STABILITY-MODEL.md) — the user companion to ADR-011; mechanizes the "curated combos" bet.
- [docs/HARNESS.md](HARNESS.md) — review feedback loop + reviewer-by-file-type matrix.
- [Jira AL-7](https://copiedwonder.atlassian.net/browse/AL-7) — v0.3.3 agenda redefinition epic.
- [Jira AL-38](https://copiedwonder.atlassian.net/browse/AL-38) — v0.3.4 Aware Installation Process; defines "first usable release."
