# 014: Secret remediation for v0.4.0 — no rotation required

**Status:** Accepted
**Date:** 2026-04-26

## Context

Before opening the repository, we scanned its full history for credentials and committed to a remediation rule up front: every real secret found (as opposed to a false positive) gets rotated upstream — new token issued, old token revoked — and the choice between accepting rotation as sufficient versus rewriting history with `git filter-repo` gets recorded here.

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

If a future audit — or the gitleaks gate on every commit — flags a *real* secret:

1. **Default action: rotate without rewriting history.** Rotation invalidates the leaked credential immediately. History rewriting is destructive (breaks every existing clone, fork, and PR ref) and only adds value if the secret cannot be revoked from upstream — e.g. a long-lived API key on a service that does not let the owner invalidate keys.
2. **Escalate to history rewrite only when:**
   - The leaked credential grants ongoing access that cannot be revoked from upstream (rare), OR
   - Compliance or regulatory framework explicitly requires the leaked value to be removed from version-controlled history (rarer).
3. **Document the decision** in a follow-up ADR (`docs/decisions/0NN-secret-leak-<date>.md`) with the rotation timestamp, the upstream service's invalidation evidence, and any history-rewrite plan.

### Pre-flip posture

The pre-flip checklist cites this ADR as the secret-remediation closure. The visibility flip can proceed without remediation overhead.

## References

Raw scanner output is not committed; the findings are stated inline above.
To reproduce them against current history:

```bash
gitleaks detect --no-banner --redact --source . --log-opts="--all"
trufflehog git file://. --since-commit="$(git rev-list --max-parents=0 HEAD)" --only-verified
```

- `.gitleaks.toml` — allowlist scoping `.planning/*.md` plus the specific false-positive fingerprint
- `.pre-commit-config.yaml` + `.github/workflows/test.yml` — the gitleaks gate that keeps this baseline enforced
