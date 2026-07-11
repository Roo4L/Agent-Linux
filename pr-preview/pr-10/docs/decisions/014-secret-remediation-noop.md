# 014: Secret remediation for v0.4.0 — no rotation required

**Status:** Accepted
**Date:** 2026-04-26
**Drives:** v0.4.0 SEC-04
**Companion to:** SEC-01-gitleaks-report.md, SEC-02-trufflehog-report.md, SEC-03-targeted-audit.md

## Context

v0.4.0 SEC-04 specifies the remediation path for any secret found in git history during Phase 8 scans:

> For every secret found by SEC-01..03 that was real (not a false positive), the secret is rotated upstream (new token issued, old token revoked) AND the decision between "accept rotation as the remediation" vs. "rewrite history with `git filter-repo`" is recorded in this ADR.

After running gitleaks (1 finding, triaged false positive — OpenNebula API hostname matching the `generic-api-key` regex), trufflehog (0 verified + 0 unverified findings), and an explicit targeted audit covering Buttondown / GitHub / Anthropic / npm tokens plus credential-shaped filenames and Bearer headers (8 patterns, all 0 matches), the repository's git history is verifiably free of credentials.

## Decision

**No rotation required. No history rewrite required.**

The single false-positive flagged by gitleaks (`generic-api-key` matching the literal token `API: api.nebula.k8s.svcs.io` in `.planning/.continue-here.md` line 65, commit 44a7f03) is suppressed via a `.gitleaks.toml` allowlist scoped to `.planning/*.md` plus the specific fingerprint. The hostname is internal infrastructure for the retired v0.2.0 OpenNebula deploy target; it is not a credential and was never one.

## Consequences

### Action items closed

| Item | Status |
|------|--------|
| Rotate Buttondown API token | Not required — none committed |
| Rotate GitHub credentials | Not required — none committed (CI uses GitHub-injected `${{ secrets.GITHUB_TOKEN }}` and vaulted `${{ secrets.GH_TOKEN }}`) |
| Rotate Anthropic credentials | Not required — none committed (Claude Code CLI authenticates via end-user `claude login`) |
| Rotate npm tokens | Not required — none committed (CLI is bundled in release tarball, not published to npm) |
| Rewrite git history (`git filter-repo`) | Not required — no real secrets to redact |

### Decision rule for future leaks

If a future audit (or the SEC-05 gitleaks gate) flags a *real* secret:

1. **Default action: rotate without rewriting history.** Rotation invalidates the leaked credential immediately. History rewriting is destructive (breaks every existing clone, fork, and PR ref) and only adds value if the secret cannot be revoked from upstream — e.g. a long-lived API key on a service that does not let the owner invalidate keys.
2. **Escalate to history rewrite only when:**
   - The leaked credential grants ongoing access that cannot be revoked from upstream (rare), OR
   - Compliance or regulatory framework explicitly requires the leaked value to be removed from version-controlled history (rarer).
3. **Document the decision** in a follow-up ADR (`docs/decisions/0NN-secret-leak-<date>.md`) with the rotation timestamp, the upstream service's invalidation evidence, and any history-rewrite plan.

### Pre-flip posture

The Phase 11 pre-flip checklist (PUB-01) cites this ADR as the SEC-04 closure. The visibility flip can proceed without secret-remediation overhead.

## References

- `docs/audits/v0.4.0/SEC-01-gitleaks-report.md` — full gitleaks output and false-positive triage
- `docs/audits/v0.4.0/SEC-02-trufflehog-report.md` — trufflehog clean signal (0 verified + 0 unverified)
- `docs/audits/v0.4.0/SEC-03-targeted-audit.md` — 8 targeted patterns, 0 matches
- `.gitleaks.toml` — allowlist scoping `.planning/*.md` plus the specific false-positive fingerprint
