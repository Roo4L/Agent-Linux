# 006: curl-pipe-bash primary + optional .deb distribution

**Status:** Accepted (2026-04-18) — **Superseded-in-part (v0.4.0):**
channel (2), the optional fpm `.deb`, is **removed**. The sole distribution channel
is now the reproducible x86_64-musl tarball + its sibling `.sha256`. Channel (1)
(curl-pipe-bash) and the mandatory `.sha256`-before-exec consequence **survive and
are reinforced** — see the note under "Consequences" below.
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

## Superseded-in-part (v0.4.0)

The v0.4.0 Rust rewrite makes the static x86_64-musl `agentlinux` binary the shipped
artifact and removes the optional fpm `.deb` channel entirely:

- **Channel (2) removed.** `packaging/deb/` (the fpm postinst bridge), the
  `build-release.sh` fpm branch (`--no-deb`/`SKIP_DEB`), the `release.yml` "Install fpm"
    step + `agentlinux_*.deb` publish glob are all deleted. The `.deb` was best-effort and unused; a single
  reproducible channel avoids drift.
- **Channel (1) survives and is reinforced.** `curl -fsSL … | bash` remains the
  primary (now sole) path. The installer still verifies the tarball's sibling
  `.sha256` **before** executing — the "every release tarball MUST ship with a
  sibling `.sha256`" consequence above is unchanged and mandatory.
- **New:** the shipped tarball is byte-reproducible (SOURCE_DATE_EPOCH-pinned tar +
  a `strip`/`--remap-path-prefix`/`--build-id=none` musl bin), so the artifact a user
  receives is bit-provable against source — strengthening the same tamper-resistance
  goal the original `.sha256` decision served.

This ADR is retained as the historical record of the original two-channel decision.
