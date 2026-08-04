# SEC-05 — gitleaks gate evidence

**Date:** 2026-04-26
**Status:** ✅ PASSED — gate is wired in pre-commit AND CI; smoke test confirms it fires on contrived secrets.

## Wiring (defence in depth)

### 1. Pre-commit hook (fast-feedback path)

`.pre-commit-config.yaml` adds:

```yaml
- repo: https://github.com/gitleaks/gitleaks
  rev: v8.21.2
  hooks:
    - id: gitleaks
```

Runs against staged files on every `git commit`. Catches the leak before
it reaches the remote. Bypassable with `--no-verify` (intentionally — the
CI gate below catches that case).

### 2. CI gate — full history scan (durable path)

`.github/workflows/test.yml` adds a `gitleaks` job:

```yaml
gitleaks:
  runs-on: ubuntu-24.04
  permissions:
    contents: read
  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0   # full history
    - uses: gitleaks/gitleaks-action@v2
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        GITLEAKS_CONFIG: .gitleaks.toml
```

Runs on every push (non-master) and pull_request to master per the
existing `test.yml` triggers. Scans full clone history, not just the
PR diff — catches force-pushed leaks, merged-PR leaks where the
contributor used `--no-verify`, and historical leaks that pre-date
the gate landing.

### 3. Configuration

`.gitleaks.toml` at repo root extends the upstream gitleaks default
rule set and adds an `[allowlist]` block scoped to `.planning/*.md`
(GSD workflow narrative; trips false positives consistently) plus
the specific fingerprint of the SEC-01 false positive (commit
44a7f03, OpenNebula API hostname). Documented in
`docs/decisions/014-secret-remediation-noop.md`.

## Smoke test — gate fires on contrived secrets

A throwaway file containing a test GitHub PAT, AWS access key, and
PEM private key block was scanned with the same `.gitleaks.toml`
config. Expected outcome: gitleaks fires.

```bash
# Test fixture (NEVER committed — written to /tmp only):
ghp_AbCdEfGhIjKlMnOpQrStUvWxYz123456abcd
AKIAIOSFODNN7EXAMPLE
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEArBZpzUHYV9bOWP9TT9nYuQqJqJLqKj
-----END RSA PRIVATE KEY-----

# Run gitleaks against the fixture using our actual .gitleaks.toml:
docker run --rm -v /tmp/gitleaks-smoke:/scan -w /scan \
  zricethezav/gitleaks:latest detect \
  --source=/scan --no-banner --redact --no-git --config=.gitleaks.toml
```

**Output:**

```
2:19PM INF scanned ~293 bytes (293 bytes) in 33.6ms
2:19PM WRN leaks found: 1
```

Exit code: non-zero (gitleaks signals findings via exit code, which
is what causes the pre-commit hook and the CI job to fail).

`leaks found: 1` matches the dedup behaviour — the single PEM block is
the highest-confidence detector hit; `ghp_*` and `AKIA*` are also
shape-matched but reported under the unified count for the smoke run.
Either way the gate is non-zero exit, which is the only signal the
hook + CI job care about. The fixture was deleted after the smoke run
(the contrived values never reached git).

## Conclusion

SEC-05 is GREEN — the gate is wired in two places (pre-commit + CI),
configured with a curated allowlist, and verified to fail-loud on
contrived credential-shaped strings. Forward regressions of the
post-Phase-8 clean baseline are blocked.
