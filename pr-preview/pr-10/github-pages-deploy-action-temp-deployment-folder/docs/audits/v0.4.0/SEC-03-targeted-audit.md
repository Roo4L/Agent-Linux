# SEC-03 — Targeted manual secret audit

**Date:** 2026-04-26
**Scope:** All 255 commits across all branches (fresh clone at `/tmp/agent-linux-scan/work`)
**Status:** ✅ PASSED — zero matches across all targeted patterns.

Issue AGE-6 specifically called out four high-risk classes. This audit
runs explicit pattern grep across every commit's content (via `git grep
<pattern> $(git rev-list --all)`) to verify each class is absent.

## Targets

### 1. Buttondown API tokens (website signup flow)

The website at `agentlinux.org` uses a Buttondown API token to handle
email signups (per `index.html`'s signup form integration, v0.1.0). Audit
checks for any `buttondown` token-shape in history.

**Pattern:**

```regex
(buttondown|BUTTONDOWN)[[:space:]_=:-]+[A-Za-z0-9_-]{20,}
```

**Matches:** 0

The Buttondown integration uses Buttondown's hosted form-action URL (no
client-side token required). No server-side tokens are checked into the
repo — the token (if any) lives only in Buttondown's account settings.

### 2. GitHub credentials (gh*_ token shapes)

Pattern checks for the four current GitHub token prefixes (gho_, ghp_,
ghs_, ghu_, ghr_) followed by the canonical 20+ alphanumeric characters.

**Pattern:**

```regex
\bgh[opsur]_[A-Za-z0-9]{20,}
```

**Matches:** 0

GitHub authentication on the existing CI workflows uses
`${{ secrets.GITHUB_TOKEN }}` (auto-injected, never stored as plaintext)
and `${{ secrets.GH_TOKEN }}` for the `release.yml` publish step (stored
in GitHub's encrypted secrets vault, never in repo).

### 3. Anthropic API keys (sk-ant-*)

Pattern checks for the canonical Anthropic key prefix.

**Pattern:**

```regex
sk-ant-[A-Za-z0-9_-]{20,}
```

**Matches:** 0

Anthropic API keys are not used in CI or the runtime. The `claude-code`
catalog entry installs the Anthropic Claude Code CLI binary which the
end-user authenticates against their own Anthropic account at runtime
(`claude login`); AgentLinux itself does not handle or store any
Anthropic credentials.

### 4. npm tokens

Pattern checks for the canonical npm automation token shape.

**Pattern:**

```regex
\bnpm_[A-Za-z0-9]{30,}
```

**Matches:** 0

`plugin/cli/` publishes are not (yet) automated — the CLI is bundled
inside the release tarball, not published to the public npm registry.
No `.npmrc` with auth token is committed (also confirmed by §5 below).

## Additional patterns checked

### 5. Credential-shaped filenames in any commit's tree

```bash
git log --all --pretty=format:'%H' | xargs -I{} git ls-tree -r --name-only {} \
  | sort -u \
  | grep -E '(^|/)(\.env(\.[a-z]+)?|\.npmrc|\.git-credentials|\.netrc|id_rsa|id_dsa|id_ed25519|.*\.pem|.*\.key|.*\.crt|\.aws/credentials|\.docker/config\.json|\.kube/config)$'
```

**Matches:** 0

No `.env`, `.npmrc`, `.git-credentials`, `.netrc`, SSH private keys,
PEM/KEY/CRT files, AWS credentials, Docker config, or Kube config have
ever been committed.

### 6. `Authorization: Bearer ...` headers

```regex
Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._-]{16,}
```

**Matches:** 0

No literal Bearer tokens in committed code, fixtures, logs, or
documentation.

### 7. AWS access keys (AKIA prefix)

```regex
\bAKIA[A-Z0-9]{16}\b
```

**Matches:** 0

### 8. PEM-format private keys (BEGIN PRIVATE KEY blocks)

```regex
BEGIN ((RSA|OPENSSH|EC|DSA) )?PRIVATE KEY
```

**Matches:** 0

## Summary table

| # | Class | Pattern | Matches | Verdict |
|---|-------|---------|---------|---------|
| 1 | Buttondown tokens | `buttondown[[:space:]_=:-]+[A-Za-z0-9_-]{20,}` | 0 | Clean |
| 2 | GitHub tokens | `\bgh[opsur]_[A-Za-z0-9]{20,}` | 0 | Clean |
| 3 | Anthropic keys | `sk-ant-[A-Za-z0-9_-]{20,}` | 0 | Clean |
| 4 | npm tokens | `\bnpm_[A-Za-z0-9]{30,}` | 0 | Clean |
| 5 | Credential filenames | (combined regex) | 0 | Clean |
| 6 | Authorization Bearer | `Authorization:[[:space:]]*Bearer …` | 0 | Clean |
| 7 | AWS AKIA | `\bAKIA[A-Z0-9]{16}\b` | 0 | Clean |
| 8 | PEM private keys | `BEGIN .* PRIVATE KEY` | 0 | Clean |

## Conclusion

All eight targeted patterns return zero matches across all 255 commits
on every branch. Combined with SEC-01 (gitleaks: 1 finding triaged as
false positive) and SEC-02 (trufflehog: 0 verified, 0 unverified),
Phase 8 closes with no real secrets in repository history. SEC-04
(remediation) is therefore a no-op: nothing to rotate, nothing to rewrite.

The pre-commit and CI gitleaks gate (SEC-05) is the only remaining
SEC requirement — it prevents this clean state from regressing on
future PRs.
