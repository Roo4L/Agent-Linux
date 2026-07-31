# AgentLinux Decision Records (ADRs)

Architecture Decision Records capture *why* a choice was made — the context, the
decision, and the alternatives rejected — so a later reader (human or agent) does
not re-litigate settled ground or contradict it by accident.

**This index is the navigation layer.** Scan the **Tags** column for your topic,
follow the link, read the one ADR that applies. Reviewer subagents are pointed
here rather than carrying copies of project invariants in their prompts. If code
contradicts an Accepted decision, that contradiction is a finding — and where an
ADR records an accepted trade-off, re-filing that trade-off is noise. An ADR whose
claims no longer describe the code is itself a finding: it grants immunity, so a
stale one is worse than none.

Format and rationale for the ADR itself: [`../HARNESS.md`](../HARNESS.md) §2.3.
New ADR: copy [`000-template.md`](000-template.md) and add a row below.

**Tag vocabulary:** `product` · `packaging` · `installer` · `nodejs` · `cli` ·
`catalog` · `versioning` · `mcp` · `security` · `privilege` · `testing` ·
`review` · `process` · `docs` · `licensing` · `release` · `distro` · `vision` ·
`reliability`

| ADR | Decision | Tags | Status |
|-----|----------|------|--------|
| [001](001-pivot-distro-to-plugin.md) | Pivot from a custom distro to an installable Ubuntu plugin (v0.2.0 → v0.3.0) | product, packaging | Accepted |
| [002](002-behavior-contract-framing.md) | Requirements are behaviors (BHV-XX), not implementation steps; tests are the spec | testing, process | Accepted |
| [003](003-no-default-agents-installed.md) | No agents installed by default; users opt in via the catalog | catalog, product | Accepted |
| [004](004-per-user-npm-prefix.md) | Per-user npm prefix as the keystone ownership decision (eliminates EACCES) | nodejs, security, privilege | Accepted |
| [005](005-system-nodejs-over-version-managers.md) | System Node.js (NodeSource) over version managers (nvm/fnm/volta) | nodejs, installer | Accepted |
| [006](006-curl-pipe-bash-plus-deb.md) | curl-pipe-bash primary distribution + optional .deb; SHA256-verified tarball | packaging, security | Accepted — .deb channel superseded |
| [007](007-docker-plus-qemu-harness.md) | Docker (fast PR) + QEMU (release gate) harness; Docker-only is disqualified | testing | Accepted |
| [008](008-commander-js-for-cli.md) | Commander.js for the registry CLI | cli | Superseded — the CLI is Rust + `clap` |
| [009](009-snap-disqualified.md) | Snap is structurally disqualified as a distribution mechanism | packaging | Accepted |
| [010](010-review-loop-via-claude-md.md) | Review loop triggered by project instructions, not a Stop hook | review, process | Accepted |
| [011](011-stability-first-version-pinning.md) | Stability-first version pinning with explicit reconciliation | catalog, versioning | Accepted |
| [012](012-agent-user-full-sudo.md) | Agent user gets passwordless sudo (ALL commands); supersedes zero-sudo lock | security, privilege | Accepted |
| [013](013-license-mit.md) | MIT license for AgentLinux | licensing, release | Accepted |
| [014](014-secret-remediation-noop.md) | Secret remediation for v0.4.0 — no rotation required | security, release | Accepted |
| [015](015-developer-internals-docs.md) | Developer internals docs embedded in the review loop, no new hook | docs, review, process | Accepted |
| [016](016-agenda-redefinition.md) | Agenda redefinition — two pillars, vision-only doc | product, vision | Accepted |
| [017](017-distro-family-bucket.md) | Distro-family bucket (`AGENTLINUX_DISTRO_FAMILY`) + single `pkg.sh` dispatch | distro, installer | Accepted |
| [018](018-mcp-thin-installer-in-client-auth.md) | MCP entries are thin client-config installers; auth happens in-client | catalog, mcp, security | Accepted |
| [019](019-idempotent-convergence-over-completion-markers.md) | Provisioner steps converge and self-verify; no per-step completion markers | installer, reliability | Accepted |
| [020](020-bounded-degradation-under-hostile-io.md) | Every wait is bounded; on expiry the tool degrades loudly rather than blocking | installer, cli, reliability | Accepted |
