# PUB-04 — First public release notes

**Date:** 2026-04-26
**Status:** ✅ DONE

## What ships under v0.4.0

The v0.4.0 milestone's deliverable is the visibility flip itself. The repository
is now public. There is no v0.4.0 source tarball — the flip is the release.

## Where the public release notes live

A non-tarball "v0.4.0" GitHub Release was published at:

```
https://github.com/Roo4L/Agent-Linux/releases/tag/v0.4.0
```

It points readers at:

- [`LICENSE`](../../../LICENSE) — MIT, ADR-013.
- [`CONTRIBUTING.md`](../../../CONTRIBUTING.md) — quick-start, behavior-test contract, DCO-equivalent affirmation.
- [`README.md`](../../../README.md) — public-facing usage + curated agent combos.
- The full v0.4.0 milestone audit trail under [`docs/audits/v0.4.0/`](.).

The pre-existing release-candidate pages (`v0.3.0-rc1`..`v0.3.0-rc12`) became
publicly browsable the moment the visibility flip happened, so "first public
release notes" is satisfied in two ways: the rc page chain *and* the v0.4.0
launch tag.

## What does NOT ship in v0.4.0

- No source tarball is attached to the v0.4.0 release.
- The end-to-end `curl … | sudo bash` install path remains gated on the
  v0.3.0 *final* release event (see PUB-03 §"What was deliberately deferred").
- `agentlinux.org` install URL plumbing is owned by the v0.3.0 release
  shipping event, not v0.4.0.

## Status

- [x] Public release page exists at `https://github.com/Roo4L/Agent-Linux/releases/tag/v0.4.0`
- [x] Release notes link to LICENSE, CONTRIBUTING, README, audit trail
- [x] No misleading source tarball attached
