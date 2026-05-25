# AgentLinux — Vision

> Last reviewed: 2026-05-16

## Mission

AgentLinux gives coding agents a stable and effective place to run on Linux,
without asking the user to set it up or operate it themselves. The decisions,
the integration work, and the ongoing care that an agent-friendly environment
needs — runtime, permissions, toolchain compatibility, and the things we
learn the hard way over time — AgentLinux carries on the user's behalf. The
user installs once and uses their agents; the environment underneath is
something we maintain so the user does not have to.

### Positioning

For developers and operators who want their agents to work on Linux without
owning the environment themselves, AgentLinux is an installable Ubuntu plugin
that ships a dedicated agent environment and a curated, stability-tested
toolchain. Unlike assembling such an environment piece by piece, AgentLinux
ships the assembly already built, tested, and maintained against upstream
churn.

## The two pillars

AgentLinux optimizes for two values, in this order. Pillar 1 is what gets a
user running. Pillar 2 is what keeps them running.

### Pillar 1 — Time-to-productive

AgentLinux ships the assembly, not the building blocks. The agent user, its
permissions, the Node.js runtime, the self-update path, the curated catalog
— all decisions made, all best practices encoded. Where a
`sudo npm install -g claude` on a stock distribution hands the user a string
of small decisions and the EACCES errors that follow, AgentLinux ships one
working environment. The user installs once and starts working with
the agent; the setup pain is something we absorbed for them.

### Pillar 2 — Stability

The curated toolchain stays compatible across upstream churn. When an
upstream release breaks the combination with the agent's other tools,
AgentLinux does not pass that breakage on to the user. The default version
set holds at the last-known-good combination; the bump waits for verified
compatibility. The user does not learn about an upstream regression by
waking up to a broken environment.

## Guiding principles

These are the things AgentLinux holds true about itself, separate from any
specific feature or roadmap.

### We are infrastructure, not an agent product

AgentLinux provisions the environment in which agents run. It does not run,
score, sandbox, or guardrail agents at the model layer. The agents on the
machine are products we host; we are not in the agent-building business.

### We meet users on their distribution

AgentLinux installs on top of an existing Linux distribution. We do not ask
the user to migrate, reinstall, or boot a custom image. The distribution
maintainer's work is the foundation; we build on top of it.

### We curate, we do not aggregate

The catalog ships a small, deliberately chosen set of agents and tools that
have been tested as a combination. We do not race to add everything —
admission requires a behavior test, a maintainer reputation signal, and a
considered decision. The smaller catalog is the point.

### Value arrives automatically

What a user gets from AgentLinux is what shows up on install, not what they
have to assemble themselves. The default version set is the tested combo.
The agent user has correct permissions out of the box. Self-update works the
first time. The user is not asked to configure trust.

## What we're explicitly not

These are deliberate limits on the product. They keep the surface area small
and the promises honest.

- **Not an agent product.** We do not build coding agents, prompt-injection
  guardrails, or model-layer defenses. Those belong to agent and model
  vendors.
- **Not a sandbox runtime.** We do not ship kernel- or userspace-level
  sandboxing primitives (capability-scoped sudoers, bubblewrap wrappers,
  Landlock profiles, iptables egress allowlists). Those primitives exist in
  the kernel and elsewhere; a user who wants that posture composes them
  themselves.
- **Not an observability vendor.** Tools like Helicone or Langfuse belong as
  opt-in catalog entries, never as bundled defaults. We do not brand or
  compete on agent observability.
- **Not a Linux-distribution-style upstream maintainer.** We pin, we hold,
  we wait for upstream fixes. We do not carry backports, forks, or
  downstream patches.
- **Not an agent benchmark publisher.** Terminal-bench, SWE-bench,
  tau-bench, and similar measure the agents that run on top of AgentLinux.
  We cite them as landscape, never as commitments.
