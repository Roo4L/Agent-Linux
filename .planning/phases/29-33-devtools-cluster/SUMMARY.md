# Phases 29–33 — DevOps / git / observability CLI cluster (batch summary)

**Milestone:** v0.3.6 Catalog Expansion · **Requirements:** DEVT-01..05
**Delivered:** 2026-07-02 · one always-shippable catalog entry per phase.

Phases 29–32 are `source_kind: binary` (they reuse the Phase 28 ENABLE-01
prebuilt-binary helper); Phase 33 is `source_kind: npm`. Rather than five full
GSD discuss→plan→execute cycles, the cluster was executed as one batch: the
research below is the ground truth that drove the recipes, and every entry still
lands its own TST-07 bats coverage (`tests/bats/58-catalog-devtools.bats`) and
Docker-green gate.

## ENABLE-01 helper generalization (folded into Phase 29, gh)

The Phase 28 helper was rtk-shaped: it derived the asset name from Rust target
triples, hardcoded `checksums.txt`, and built a `github.com/<repo>` base URL.
gh is the first consumer that breaks every one of those assumptions, so Phase 29
generalized `plugin/catalog/lib/prebuilt-binary.sh`:

- `al_pb_detect_asset <tool>` → **`al_pb_arch <x86_64_token> <aarch64_token>`** —
  the recipe supplies the two arch tokens (they differ per upstream) and the
  helper keeps the uname dispatch + unsupported-arch guard.
- `al_pb_fetch_and_verify` gained a **`<checksums>` filename** parameter
  (upstreams disagree: bare `checksums.txt` vs `<tool>_<ver>_checksums.txt`).
- `al_pb_install` now takes a fully-resolved **`<base_url>`** (GitHub *or*
  GitLab), `<asset>`, `<checksums>`, and explicit `<pinned>` — the recipe owns
  everything tool-specific; the helper owns the security-critical core
  (verify-before-extract, single-member extract, version-lock). rtk's recipe +
  the 57-catalog-binary negative-checksum test were migrated to the new API.

The `--version` grep-for-pin assertion needed no change: gh, glab, trivy, and
gitleaks all echo the version in `--version` output.

## Per-tool ground truth (verified live 2026-07-02)

| Tool | Host / repo | Asset (x86_64 / aarch64) | Checksums | Archive bin path | Config/cache removed |
|------|-------------|--------------------------|-----------|------------------|----------------------|
| gh 2.95.0 | github.com/cli/cli | `gh_<v>_linux_amd64.tar.gz` / `_arm64` | `gh_<v>_checksums.txt` | `gh_<v>_linux_<arch>/bin/gh` (nested, arch in path) | `~/.config/gh` |
| glab 1.105.0 | **gitlab.com**/gitlab-org/cli | `glab_<v>_linux_amd64.tar.gz` / `_arm64` | `checksums.txt` | `bin/glab` (nested) | `~/.config/glab` |
| trivy 0.71.2 | github.com/aquasecurity/trivy | `trivy_<v>_Linux-64bit.tar.gz` / `-ARM64` | `trivy_<v>_checksums.txt` | `trivy` (flat) | `~/.cache/trivy` |
| gitleaks 8.30.1 | github.com/gitleaks/gitleaks | `gitleaks_<v>_linux_x64.tar.gz` / `_arm64` | `gitleaks_<v>_checksums.txt` | `gitleaks` (flat) | (stateless — binary only) |
| sentry-cli 3.6.0 | npm `@sentry/cli` | — (npm) | — | — | (npm package; env/`.sentryclirc` user-owned) |

Notes that shaped the recipes:

- **glab is served from GitLab, not GitHub** — its release download base is
  `gitlab.com/gitlab-org/cli/-/releases/v<v>/downloads`. This is the sole reason
  `al_pb_install` takes a base URL rather than a `<repo>`. DEVT-02 also forbids
  the archived `profclems/glab`; the maintained gitlab-org/cli is the only source
  that ships 1.105.0, so the version-pin match is itself the upstream proof (the
  test also greps the recipe for `gitlab-org/cli` and against `profclems`).
- **gh nests its binary under an arch-named top dir** (`gh_<v>_linux_amd64/bin/gh`),
  so `bin_path_in_archive` is arch-dependent — computed in the recipe from the
  same `al_pb_arch` token.
- **trivy / gitleaks** run their scans with **no Docker daemon** (DEVT-04/05);
  the bats tests drive a real `trivy fs --scanners secret` and `gitleaks dir`
  scan of a seeded dir (both exit 0, verified offline).
- **sentry-cli** is **FSL-1.1-MIT** (free to use, not OSI-approved). The honesty
  flag lives in the entry's `license` field (Appendix B); the test asserts it.

## Coverage

`tests/bats/58-catalog-devtools.bats` — DEVT-01..05, one @test each, full TST-07
lifecycle (install → resolve at agent-owned prefix, no `/usr/local` shim, no
EACCES → `--version`/`version` contains the jq-derived catalog pin → symmetric
remove of binary + config/cache → idempotent re-remove), plus the trivy/gitleaks
no-daemon scans, the glab-upstream guard, and the sentry-cli FSL flag check.
