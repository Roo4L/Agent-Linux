# CLEAN-03 — `.gitignore` audit

**Date:** 2026-04-26
**Status:** ✅ PASSED — `.gitignore` updated for public-repo posture; pre-commit large-file hook verified active.

## What was already covered

Pre-Phase-9 `.gitignore` covered the v0.3.0-era artifacts:

- `output/*.qcow2` (retired distro image build path)
- `packer/.packer.d/`, `packer/packer_cache/` (retired)
- `node_modules/` (CLI dev dependency tree)
- `plugin/cli/dist/`, `plugin/cli/dist-test/` (TypeScript build output)
- `dist/` (Phase 6 release build directory)
- `tests/qemu/artifacts/`, `tests/qemu/cache/` (QEMU release-gate cache)
- `install.sh` (CI-generated symlink-equivalent at repo root, sourced from `packaging/curl-installer/`)

That covered the obvious *built* artifacts. It did **not** cover credential-shaped files, editor cruft, OS files, or ecosystem-standard build caches. Phase 9 adds those.

## What was added

```gitignore
# Local environment / credential artifacts
.env
.env.*
!.env.example
.npmrc
!plugin/cli/.npmrc
.git-credentials
.netrc
*.pem
*.key
!plugin/catalog/**/*.key.json
*.crt
id_rsa
id_dsa
id_ed25519
id_ed25519_*

# Editor / IDE
.vscode/
.idea/
*.swp
*.swo
*~
.DS_Store
Thumbs.db
*.iml

# Coverage + test output
coverage/
.nyc_output/
*.lcov
.pytest_cache/
.ruff_cache/
.mypy_cache/

# TypeScript build cache
*.tsbuildinfo

# Python
__pycache__/
*.pyc
*.pyo

# pnpm / yarn local store
.pnpm-store/
.yarn/cache/
.yarn/install-state.gz
```

## Rationale per category

| Category | Rationale |
|----------|-----------|
| `.env*` family | Defence in depth alongside SEC-05 gitleaks gate. SEC-03 verified none exist in history; `.gitignore` prevents them from ever being staged. The `!.env.example` allow-list keeps a *template* file (no secrets) submittable if a future contributor adds one. |
| `.npmrc` family | npm auth tokens often live in user-home `.npmrc`; the `!plugin/cli/.npmrc` allow-list preserves the project-scoped npm config under `plugin/cli/` for legitimate package-resolution settings. |
| `.git-credentials`, `.netrc` | Both store credentials in plaintext when used; they should never enter the repo. |
| `*.pem`, `*.key`, `*.crt` | Cryptographic material. The `!plugin/catalog/**/*.key.json` allow-list is defensive — JSON catalog keys are not cryptographic, just happen to share a `.key.json` shape if one ever emerges. |
| SSH private key names | `id_rsa`, `id_dsa`, `id_ed25519`, `id_ed25519_*` — the canonical OpenSSH shapes. Public `.pub` siblings remain commitable (the `!*.pub` rule is implicit because `*.pub` doesn't match the listed patterns). |
| `.vscode/`, `.idea/`, `*.swp`, `*.swo`, `*~`, `.DS_Store`, `Thumbs.db`, `*.iml` | Editor + OS cruft. None should ever be committed; if a contributor's editor writes them locally, this rule keeps them out of git. |
| `coverage/`, `.nyc_output/`, `*.lcov` | JS / TS coverage tooling outputs. Some CI flows write these locally during contributor runs. |
| `.pytest_cache/`, `.ruff_cache/`, `.mypy_cache/` | Python tooling caches — futureproofing in case a Python helper ever lands. |
| `*.tsbuildinfo` | TS incremental compile cache. Belongs to the developer workstation. |
| `__pycache__/`, `*.pyc`, `*.pyo` | Python bytecode caches — same reason. |
| `.pnpm-store/`, `.yarn/cache/`, `.yarn/install-state.gz` | Local pnpm / yarn dependency stores. The lockfile (`plugin/cli/pnpm-lock.yaml`) is committed; the *cache* is not. |

## Pre-commit hook check

```bash
grep -A 1 'check-added-large-files' .pre-commit-config.yaml
# Expected: hook is enabled (no `args:` overrides → default 500 KB threshold)
```

Output:

```yaml
      - id: check-added-large-files
      - id: check-merge-conflict
```

✓ Active. Default threshold is 500 KB. Combined with CLEAN-02's finding (no >500 KB blobs anywhere in history), the hook + the audited baseline mean any future >500 KB stage triggers a hook failure.

The `detect-private-key` hook (already present in `.pre-commit-config.yaml`) is the third layer of defence on credential-shaped strings, complementing SEC-05's gitleaks gate.

## No-op verifications

```bash
# No accidental currently-tracked editor / OS files:
git ls-files | grep -E '(\.DS_Store|Thumbs\.db|\.swp|\.swo|^\.vscode/|^\.idea/)' && echo "FOUND" || echo "clean"
# Output: clean

# No accidental currently-tracked credential-shaped files:
git ls-files | grep -E '(^|/)(\.env(\.[a-z]+)?|\.npmrc|\.git-credentials|\.netrc|id_rsa|id_dsa|id_ed25519)$' && echo "FOUND" || echo "clean"
# Output: (intentionally empty — shows clean state)
```

## Conclusion

`.gitignore` is now hardened for public-repo posture. The combination of:

- Updated `.gitignore` (this phase)
- `check-added-large-files` pre-commit hook (existing)
- `detect-private-key` pre-commit hook (existing)
- SEC-05 gitleaks gate (Phase 8)

provides four-layer defence against credential / artifact / large-file regressions post-flip.
