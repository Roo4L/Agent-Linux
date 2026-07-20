# Antigravity CLI

Antigravity CLI is Google's terminal coding agent, installed by AgentLinux as
the `agy` command. It is the supported successor to Google's Gemini CLI and is
an opt-in catalog package.

## The problem

Google distributes Antigravity CLI as a Linux archive rather than an npm
package. An unpinned installer would silently follow upstream releases, while
an unverified archive would make the agent installation unnecessarily
dependent on the integrity of a live download. Its Google Sign-In session and
MCP configuration are also user-owned state that must survive a normal package
removal.

## What AgentLinux does

The catalog pins Antigravity CLI to version `1.1.4`, selects the official
Linux x86-64 or ARM64 archive, verifies its published SHA-512 digest before
extraction, and accepts only the single regular-file member named
`antigravity`. The recipe installs it as
`~/.local/bin/agy` with mode `0755`; it never creates a `/usr/local/bin`
wrapper.

Authentication remains in the user's Antigravity session. The recipe prints a
Google Sign-In pointer but does not accept, store, or inject an API key. The
`~/.gemini/` directory is preserved across normal `agentlinux remove` and is
removed only by an explicit purge operation.

Antigravity 1.1.4 exposes `agy update` and upstream documents background
self-updating. AgentLinux provisions the upstream-supported
`AGY_CLI_DISABLE_AUTO_UPDATE=true` variable through the login profile, the
systemd environment file, and the cron environment so the passive path is
disabled in each supported launch mode. The initial artifact remains pinned
and checksum-verified, and AgentLinux never invokes `agy update` itself.

## Value vs the naive approach

1. **Verified binary:** The archive is checksum-checked before extraction, so
   the catalog has a reproducible initial artifact rather than an unbounded
   live installer.
2. **User-owned state:** Google Sign-In, migrated settings, skills, MCP
   profiles, and session data remain available after a normal remove/reinstall
   cycle.
3. **Honest update boundary:** AgentLinux controls the initial package pin and
   uses Antigravity's documented opt-out for passive updates; a user can still
   run the explicit `agy update` command when they choose to leave the catalog
   pin.

## Related

- [Catalog](catalog.md) — stores the Antigravity CLI entry and pin.
- [Google's transition announcement](https://developers.googleblog.com/en/an-important-update-transitioning-gemini-cli-to-antigravity-cli/)
- [Antigravity CLI repository](https://github.com/google-antigravity/antigravity-cli)
- [Antigravity migration guide](https://antigravity.google/docs/gcli-migration)
