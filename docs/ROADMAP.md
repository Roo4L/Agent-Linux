# AgentLinux — Roadmap

> Last reviewed: 2026-08-01

> Companion to [docs/STRATEGY.md](STRATEGY.md). The strategy doc names
> the gaps we exist to close, the bets we are making, and the guiding
> policy. This doc names the time-ordered work that follows. Expected to
> churn faster than the strategy.

## Where we are now

v0.3.6 ships against Ubuntu 22.04 / 24.04 / 26.04 and AlmaLinux 9, with
25 catalog entries. The next goal is the first publicly available alpha
release — put in front of a small selected group to gather the project's
first outside feedback. Four things block it.

1. **Stability.** Too many commands do not behave the way they should,
   and there are bugs throughout.

2. **Release speed.** Packages in this ecosystem update constantly. The
   Claude Code version we currently curate is far behind upstream, and
   that is a non-starter. Users have to be able to stay in sync with our
   curated version set instead of being forced onto the latest version
   of everything.

3. **Installation flexibility.** Installation is rigid today — the only
   thing the user chooses is the agent user name. But a user may want to
   restrict what the agent user can do: no package installs, no
   `systemctl`. The maintainer's own use case likely does not map onto
   everyone else's, and that mismatch is an adoption risk. The alpha has
   to strip that rigidity out for good. Grant sudo or not? Let Claude
   Code bypass permissions or not? Every provisioning decision we
   currently hardcode on the user's behalf becomes a choice they make.
   This does not contradict the strategy of getting agents running as
   fast and easily as possible, as long as the wizard ships reasonable
   defaults. The wizard has to be both interactive and flag-driven, so
   AgentLinux fits user-driven and automation-driven installs alike.

4. **Update notification and transparency.** Release speed means nothing
   if releases are not (a) delivered or surfaced to users automatically
   and (b) clear about the value they carry — which package updates the
   user gets, which bugs are fixed. So the release-speed work covers not
   only automated package-update testing but a communication channel to
   users, such as a shell prompt on every terminal opened on an
   AgentLinux host. It needs a clear update command too.

Summing up: the first alpha serves one purpose — easy agentic-tool
management and updates, with high reliability. Everything else —
security, presets and profiles, token savings — comes later in this
roadmap. The goal is to test the theory that AgentLinux actually solves
a real problem for real users.

## What's next

### Themes for next releases

#### Security Hardening

We carry an opportunistic security-hardening theme from the Phase 14
exploration: a capability-scoped sudoers profile replacing the current
passwordless-sudo-for-everything default, cosign-signed catalog releases,
npm provenance verification at install time, a bubblewrap-based per-recipe
sandbox, and an iptables egress allowlist for catalog recipes.
**Sequencing rationale:** The v0.3.4 brownfield work has now surfaced
which capabilities the agent actually needs in practice — that was the
gating signal for which NOPASSWD scope we can honestly cut. The alpha's
configurable installer (blocker #3) asks the same question at install
time, so it decides the default; this theme hardens the profile behind
that default afterwards.

#### Preset / profile framework + compat-guarded update flow

The Phase 13 differentiators: `bare` / `must-haves` / `optimum` presets,
`web-development`-style profiles, and a hold-and-wait-on-upstream-breakage
policy for the catalog update pipeline.
**Sequencing rationale:** Builds on the `pinned_version` foundation
already in v0.3.0; the work is mechanism design plus UX, not new product
surface. It sits behind the alpha because presets are a convenience layer
over the tool management the alpha has to make reliable first.

#### Public engagement

A low-overhead opt-in mailing list for release announcements, structured
feedback collection (issue templates, contributor invite paths in
CONTRIBUTING.md), and community-platform basics once the catalog warrants
them.
**Sequencing rationale:** Gated on the alpha shipping. v0.3.6 grew the
catalog from 3 to 25 entries, so surface area is no longer the
bottleneck — reliability is. We go broad once the alpha's stability and
update story survive contact with the first feedback group.

## Related

- [docs/STRATEGY.md](STRATEGY.md) — the strategy this roadmap operationalizes.
- [docs/VISION.md](VISION.md) — the canonical "what we want to be" doc.
- [Jira AL-7](https://copiedwonder.atlassian.net/browse/AL-7) — v0.3.3 agenda redefinition epic.
- [Jira AL-38](https://copiedwonder.atlassian.net/browse/AL-38) — v0.3.4 Aware Installation Process, shipped 2026-06-08.
