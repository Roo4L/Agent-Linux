# AgentLinux — Roadmap

> Last reviewed: 2026-05-23

> Companion to [docs/STRATEGY.md](STRATEGY.md). The strategy doc names
> the gaps we exist to close, the bets we are making, and the guiding
> policy. This doc names the time-ordered work that follows. Expected to
> churn faster than the strategy.

## Where we are now

Our current goal is to ship the first usable release of AgentLinux for
the maintainer as canonical user. That means v0.3.4 Aware Installation
Process ([AL-38](https://copiedwonder.atlassian.net/browse/AL-38)) — a
brownfield-aware installer that detects existing agent user / Node.js /
catalog packages, reuses what is compatible, remediates what is broken,
with a consent gate for mutations — followed by AlmaLinux support, the
first distro expansion past Ubuntu.

The v0.3.0 plugin ships against Ubuntu 22.04 / 24.04 / 26.04 with the
agent's zero-EACCES self-update verified end-to-end against the live
Anthropic CDN on every release; the v0.4.0 license flip made the project
OSS-MIT on 2026-05-09. The v0.3.3
milestone — the strategy / roadmap framing — closes once Phase 16's
website refresh ships.

## What's next

### Near-term

1. Finish v0.3.3 — the strategy / roadmap split and Phase 16's website
   refresh.
2. Ship v0.3.4 Aware Installation Process
   ([AL-38](https://copiedwonder.atlassian.net/browse/AL-38)) — the
   brownfield installer that adopts existing setups instead of refusing
   to touch them.
3. Add AlmaLinux support — the first distro expansion past Ubuntu.
4. OSS funding application — parallel / meta, not blocking engineering.

### Themes for v0.6+

#### Security Hardening

We carry an opportunistic security-hardening theme from the Phase 13
exploration: a capability-scoped sudoers profile replacing the current
passwordless-sudo-for-everything default, cosign-signed catalog releases,
npm provenance verification at install time, a bubblewrap-based per-recipe
sandbox, and an iptables egress allowlist for catalog recipes.
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
**Sequencing rationale:** Explicitly gated on theme #3 reaching critical
mass. The current three-agent release is too tiny to engage subscribers
meaningfully; we want a broader catalog before any public announcement.

## Related

- [docs/STRATEGY.md](STRATEGY.md) — the strategy this roadmap operationalizes.
- [docs/VISION.md](VISION.md) — the canonical "what we want to be" doc.
- [Jira AL-7](https://copiedwonder.atlassian.net/browse/AL-7) — v0.3.3 agenda redefinition epic.
- [Jira AL-38](https://copiedwonder.atlassian.net/browse/AL-38) — v0.3.4 Aware Installation Process; defines "first usable release."
