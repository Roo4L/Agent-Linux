# AgentLinux Decision Records (ADRs)

Architecture Decision Records capture *why* a choice was made — the context, the
decision, and the alternatives rejected — so a later reader (human or agent) does
not re-litigate settled ground or contradict it by accident.

**This index is the navigation layer.** Scan the **Tags** column for your topic,
follow the link, read the one ADR that applies. Reviewer subagents are pointed
here rather than carrying copies of project invariants in their prompts. If code
contradicts an Accepted decision, that contradiction is a finding.

Format and rationale for the ADR itself: [`../HARNESS.md`](../HARNESS.md) §2.3.
New ADR: copy [`000-template.md`](000-template.md) and add a row below.

**Tag vocabulary:** `product` · `packaging` · `installer` · `nodejs` · `cli` ·
`catalog` · `versioning` · `mcp` · `security` · `privilege` · `testing` ·
`review` · `process` · `docs` · `licensing` · `release` · `distro` · `vision`

| ADR | Decision | Tags | Status |
|-----|----------|------|--------|
| [001](001-pivot-distro-to-plugin.md) | Pivot from a custom distro to an installable Ubuntu plugin (v0.2.0 → v0.3.0) | product, packaging | Accepted |
| [002](002-behavior-contract-framing.md) | Requirements are behaviors (BHV-XX), not implementation steps; tests are the spec | testing, process | Accepted |
| [003](003-no-default-agents-installed.md) | No agents installed by default; users opt in via the catalog | catalog, product | Accepted |
| [004](004-per-user-npm-prefix.md) | Per-user npm prefix as the keystone ownership decision (eliminates EACCES) | nodejs, security, privilege | Accepted |
| [005](005-system-nodejs-over-version-managers.md) | System Node.js (NodeSource) over version managers (nvm/fnm/volta) | nodejs, installer | Accepted |
| [006](006-curl-pipe-bash-plus-deb.md) | curl-pipe-bash primary distribution + optional .deb; SHA256-verified tarball | packaging, security | Accepted |
| [007](007-docker-plus-qemu-harness.md) | Docker (fast PR) + QEMU (release gate) harness; Docker-only is disqualified | testing | Accepted |
| [008](008-commander-js-for-cli.md) | Commander.js for the registry CLI | cli | Accepted |
| [009](009-snap-disqualified.md) | Snap is structurally disqualified as a distribution mechanism | packaging | Accepted |
| [010](010-review-loop-via-claude-md.md) | Review loop triggered by project instructions, not a Stop hook | review, process | Accepted |
| [011](011-stability-first-version-pinning.md) | Stability-first version pinning with explicit reconciliation | catalog, versioning | Accepted |
| [012](012-agent-user-full-sudo.md) | Agent user gets passwordless sudo (ALL commands); supersedes zero-sudo lock | security, privilege | Accepted |
| [013](013-license-mit.md) | MIT license for AgentLinux | licensing, release | Accepted |
| [014](014-secret-remediation-noop.md) | Secret remediation for v0.4.0 — no rotation required | security, release | Accepted |
| [015](015-developer-internals-docs.md) | Developer internals docs embedded in the review loop, no new hook | docs, review, process | Accepted |
| [016](016-agenda-redefinition.md) | Agenda redefinition — two pillars, vision-only doc | product, vision | Accepted |
| [017-a](017-distro-family-bucket.md) | Distro-family bucket (`AGENTLINUX_DISTRO_FAMILY`) + single `pkg.sh` dispatch | distro, installer | Accepted |
| [017-b](017-mcp-thin-installer-in-client-auth.md) | MCP entries are thin client-config installers; auth happens in-client | catalog, mcp, security | Accepted |

## Known numbering issues

These are recorded here rather than silently renumbered (renumbering breaks
inbound cross-references); fix under a dedicated cleanup:

- **Duplicate 017.** Both `017-distro-family-bucket.md` and
  `017-mcp-thin-installer-in-client-auth.md` claim ADR-017. Listed above as
  `017-a` / `017-b`. Renumbering the MCP one to 018 is the pending fix.
- **Stale heading in 016.** `016-agenda-redefinition.md` opens with a `# 015:`
  heading (should be `016`); the filename is authoritative.
