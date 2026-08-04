# 006: curl-pipe-bash primary + optional .deb distribution

**Status:** Accepted
**Date:** 2026-04-18

## Context

The v0.3.0 installer needs a distribution mechanism that is (a) zero-infrastructure
on the maintainer side (no public PPA, no package-signing key ceremony for a
pre-1.0 project), (b) one-command on the user side, and (c) verifiable against
tampering. `curl-pipe-bash` with a SHA256 check on the downloaded tarball meets
all three; a `.deb` wrapper via fpm gives apt-managed updates for users who
prefer that path.

## Decision

Ship two distribution channels: (1) `curl -fsSL https://agentlinux.org/install | bash`
as the primary one-command path (the installer verifies the release tarball's
sibling `.sha256` before executing it), and (2) an optional fpm-built `.deb`
uploaded to each GitHub Release.

## Consequences

- Every release tarball MUST ship with a sibling `.sha256` file; the curl-installer
  refuses to execute if verification fails.
- Snap is structurally disqualified (see ADR-009); no Snap channel, ever.
- `.deb` is best-effort — we don't run a public apt repo, so users install via
  `dpkg -i` from the GitHub Release asset, not via `apt install`. Promoting to a
  real PPA is deferred to post-v0.3.0.
