# Phase 6: Distribution + Release Pipeline - Research

**Researched:** 2026-04-20
**Domain:** release engineering — bash + GitHub Actions + QEMU + cloud-init + static distribution
**Confidence:** HIGH (stack), HIGH (patterns), MEDIUM (fpm specifics), HIGH (pitfalls)

## Summary

Phase 6 turns Phase 5's locally-green plugin into a tagged, signed-by-SHA256, curl-installable release with a two-runtime (Docker + QEMU) release gate. No novel technology is introduced — every piece is an established Linux-release pattern. The phase's risk is assembly, not invention: six artifacts (tarball, SHA256, catalog snapshot, optional .deb, install.sh, README), four CI gates (Docker matrix, QEMU matrix, AGT-02, pinned-combo TST-08), one static-hosting redirect, and a build script that orchestrates it all.

The stack is prescriptive: GNU `sha256sum --tag` for BSD-style checksums (because `sha256sum -c` reads BSD and GNU format interchangeably); GNU `tar --sort=name --owner=0 --group=0 --mtime=@<epoch>` for a reproducible tarball; Ubuntu cloud images + `cloud-localds` for QEMU seed ISOs; `qemu-system-x86_64 -enable-kvm` with KVM now available on hosted ubuntu-24.04 runners (documented October 2025); `softprops/action-gh-release@v2` for publishing. The curl-installer follows the well-known `main(){}; main "$@"` wrapper pattern so partial downloads never execute, SHA256-verifies before extraction, and fail-fast-exits if verification fails or the Ubuntu version is unsupported.

**Primary recommendation:** Ship 5 plans — (1) `scripts/build-release.sh`, (2) `packaging/curl-installer/install.sh` + `agentlinux.org/install.sh` redirect, (3) `tests/qemu/boot.sh` + cloud-init seeds + nightly-qemu.yml, (4) `release.yml` 4-gate pipeline + catalog snapshot + pinned-combo job, (5) `README.md` + (optional) `docs/STABILITY-MODEL.md`. Defer `.deb` (ADR-006 "optional") to a 6th plan only if fpm integration on the runner is quick; otherwise ship v0.3.0 without and file `INF-02` for v0.4+.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Release Artifact Layout:**
- Tarball: `agentlinux-v<X.Y.Z>.tar.gz` containing `plugin/` directory only (bin + lib + provisioner + cli/dist + cli/node_modules + catalog). Excludes `tests/`, `docs/`, `.planning/`, `.github/`, `website/`, `packer/`.
- Siblings: `agentlinux-v<X.Y.Z>.tar.gz.sha256` (per INST-03) + `catalog-v<X.Y.Z>.json` (per CAT-05, byte-for-byte from `plugin/catalog/catalog.json` at release time).
- Optional `.deb` via `fpm` per ADR-006 — ship if feasible, skip if fpm brittle (documented v0.4+ deferral).
- Build script: `scripts/build-release.sh v<X.Y.Z>` (create it; already referenced in CLAUDE.md + existing `release.yml`). Called by `release.yml` on v* tag push.
- Version source-of-truth: `plugin/cli/package.json` `version` field. Build script verifies arg matches. Release tag must match too.

**curl-pipe-bash Installer (INST-03):**
- Download location: GitHub Releases permalinks — `https://github.com/<org>/agent-linux/releases/download/v<X.Y.Z>/agentlinux-v<X.Y.Z>.tar.gz` + sibling `.sha256`.
- Entry script: `packaging/curl-installer/install.sh` (Phase 1 stub — replace body). Does:
  1. Root check; fail-fast with clear error.
  2. Detect Ubuntu version + fail if unsupported.
  3. Resolve version: `AGENTLINUX_VERSION=v0.3.0` env OR fetch latest from GitHub releases API.
  4. Download tarball + `.sha256` to tmp dir via `curl -fsSL`.
  5. Verify: `sha256sum -c agentlinux-v<X.Y.Z>.tar.gz.sha256` — fail-fast on mismatch with clear message.
  6. Extract tarball to `/opt/agentlinux/install/<X.Y.Z>/`.
  7. `exec /opt/agentlinux/install/<X.Y.Z>/plugin/bin/agentlinux-install "$@"` — pass-through flags.
- Short URL: `https://agentlinux.org/install.sh` redirects (via existing v0.1.0 website GitHub Pages infra) to canonical GitHub Releases location. Documented in README as canonical command.
- Invocation: `curl -fsSL https://agentlinux.org/install.sh | sudo bash` OR `sudo bash -c "$(curl -fsSL https://agentlinux.org/install.sh)"` (README shows both).

**CI Release Pipeline (TST-03, TST-05, TST-08):**
- Trigger: push of `v*` tag to `.github/workflows/release.yml`. Also `workflow_dispatch` for dry-runs.
- Pipeline gates (in order; each blocks):
  1. Pre-commit + Node unit tests (existing test.yml logic reused).
  2. Docker matrix (existing test.yml) — `./tests/docker/run.sh ubuntu-{22,24}.04`. Expected 66/66.
  3. QEMU matrix (TST-03 — NEW): cloud-image VMs for Ubuntu 22.04 + 24.04. `tests/qemu/boot.sh` fleshed out. Cloud-init seed ISO. SSH in, run installer, run bats. Both must exit 0.
  4. AGT-02 release-gate (TST-05): `bats tests/bats/51-*.bats` runs inside BOTH Docker matrix AND QEMU matrix. Non-zero blocks.
  5. Pinned-combo CI (TST-08 — NEW): after Docker + QEMU green, runs dedicated "pinned combo" job — installs every catalog agent at `pinned_version`, runs `tests/bats/50-agents.bats` + `51-*.bats`, asserts all green. Non-zero blocks. Ubuntu 24.04 Docker (pinned dev environment).
  6. Build artifacts: only after all gates green, `scripts/build-release.sh v<X.Y.Z>` builds tarball + sha256 + catalog snapshot + optional .deb.
  7. Publish to GitHub Release: attach artifacts to tag; release notes from commit log since previous tag.
- QEMU image caching: pre-built cached images in GitHub Actions to bound CI time.

**User-Facing README (DOC-01):**
- Location: root `README.md`. v0.1.0 landing-page content preserved as "About" section; install/verify/uninstall sections primary.
- Sections (ordered): pitch → Install → Verify → Uninstall → Stability model → Escape hatch → Requirements → Links.
- Version stamp: `<!-- VERSION: v0.3.0 -->` markers auto-updated by `scripts/build-release.sh`.
- `docs/STABILITY-MODEL.md` optional per ADR-011 — planner decides v0.3.0 vs v0.3.1.

### Claude's Discretion

- Exact URL for `https://agentlinux.org/install.sh` redirect (existing v0.1.0 website infra may need a new redirect rule).
- Whether `.deb` ships in v0.3.0 (ADR-006 says "optional"; defer to v0.4+ if fpm fiddly).
- Exact cloud-init seed contents for QEMU — minimum workable config.
- Whether `release.yml` uses a matrix job or separate jobs per gate.
- README version-stamp marker shape.
- Whether `docs/STABILITY-MODEL.md` ships in v0.3.0 or is deferred.
- Number of plans: research-recommended breakdown comes next; likely 4-5 plans (build-release script, curl-installer, QEMU harness, CI release workflow, README + stability-model).

### Deferred Ideas (OUT OF SCOPE)

- Public apt PPA (INF-01) — v0.4+. v0.3.0 distributes via curl-pipe-bash + GitHub Releases.
- Auto-update daemon (INF-04) — v0.4+. User explicitly invokes `agentlinux upgrade`.
- Multi-arch (ARM) — v0.4+. x86_64 only.
- GPG-signed releases — v0.4+. SHA256 verification + HTTPS is the v0.3.0 trust story.
- `agentlinux self-update` (INF-03) — v0.4+.
- Reproducible builds (bit-for-bit deterministic) — nice but not a v0.3.0 gate.
- Full browser matrix for Playwright (firefox + webkit) — v0.4+.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INST-03 | Installer distributable via curl-pipe-bash; SHA256-verifies tarball before exec | §Pattern 2 (curl-installer skeleton), §Pitfall 1 (partial-download), §Pitfall 2 (main(){}; main wrapper), §Standard Stack `sha256sum -c` |
| TST-03 | Tests run inside QEMU-based harness against fresh Ubuntu cloud image (nightly + release-gate) | §Pattern 4 (boot.sh skeleton), §Standard Stack `qemu-system-x86_64` + `cloud-localds`, §Pitfall 4 (KVM udev rule), §Runtime State Inventory cloud-image cache |
| TST-05 | AGT-02 acceptance test blocks any release | §Pattern 6 (release.yml gate ordering), §Code Example `bats tests/bats/51-*.bats` selector |
| TST-08 | CI installs pinned catalog combo + full bats suite before release tag published | §Pattern 6 gate 5 (pinned-combo job), §Code Example pinned-combo Docker run |
| CAT-05 | Release artifact includes catalog snapshot at `/opt/agentlinux/catalog/<version>/catalog.json` | §Pattern 3 (build-release.sh skeleton), §Pitfall 8 (install-time snapshot staging coupling to Phase 4) |
| DOC-01 | README describes install, verify, uninstall | §Pattern 7 (README shape), §Code Example version-stamp sed |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| SHA256-verified download + execute | Installer host (user's Ubuntu shell) | Trust domain: HTTPS + SHA256 | install.sh runs as root on user machine; trust comes from HTTPS transport + sibling SHA256 asset published to GitHub Releases |
| Tarball composition + checksum | Build-host (GitHub Actions ubuntu-24.04 runner) | Version source = `plugin/cli/package.json` | Build runs in CI, not on user machine; deterministic `tar --sort=name` + `sha256sum --tag` produce identical outputs across re-runs |
| Version resolution (curl-installer → tag) | Installer host | GitHub Releases API (optional fallback) | Env var `AGENTLINUX_VERSION` preferred; `releases/latest/download/` redirect avoids API rate limit; API fallback is last resort |
| Ubuntu version detection | Installer host (bash) | `/etc/os-release` (freedesktop standard) | `/etc/os-release` is the POSIX-y way; `lsb_release` not always installed on minimal Ubuntu |
| QEMU guest boot | GitHub Actions runner (ubuntu-24.04) | KVM acceleration via `/dev/kvm` | Hosted runner exposes `/dev/kvm` as of Oct 2025; requires udev rule to grant runner user access |
| Cloud-init seed generation | Build-time on runner (`cloud-localds`) | `tests/qemu/cloud-init/` templates | Template files in repo, ISO generated at CI time with per-run SSH keypair |
| SSH-in + bats-over-SSH | Runner → guest via `ssh -p 2222 root@localhost` | Guest's sshd from cloud-image + cloud-init `ssh_authorized_keys` | Loopback + port forward; keypair generated per run and destroyed after |
| 4-gate CI pipeline | `.github/workflows/release.yml` | `needs:` dependencies between jobs | Sequential `needs:` chain; fail-fast cancels downstream gates |
| Catalog snapshot artifact | Build-release.sh → `dist/catalog-v<X.Y.Z>.json` | `action-gh-release@v2` upload via glob | Byte-copy of `plugin/catalog/catalog.json`; installer stages to `/opt/agentlinux/catalog/<X.Y.Z>/` at install time |
| agentlinux.org install.sh hosting | GitHub Pages static site (existing v0.1.0 repo root) | CNAME → agentlinux.org | No server-side redirects — `install.sh` is literal static file at repo root or `website/`; content EITHER redirects via JS+meta-refresh (browser hits it) OR duplicates/proxies the packaging/curl-installer/install.sh content (curl hits it) |
| README + stability docs | Repo root `README.md` | `docs/STABILITY-MODEL.md` optional | Root README is GitHub's landing page; version marker `<!-- VERSION: v0.3.0 -->` updated by build-release.sh |

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| `sha256sum` (GNU coreutils) | ≥ 9.x (Ubuntu 22.04 = 8.32; 24.04 = 9.4) | SHA256 creation + verification | [VERIFIED: /usr/bin/sha256sum present on both Ubuntu targets] Default on every Ubuntu; `-c` reads GNU and BSD checksum files; `--tag` emits BSD-style |
| GNU `tar` | ≥ 1.30 (Ubuntu 22.04 = 1.34; 24.04 = 1.35) | Tarball assembly | [CITED: gnu.org/software/tar/manual/html_section/Reproducibility.html] `--sort=name --owner=0 --group=0 --mtime=@<epoch>` is the canonical reproducible-tar recipe |
| `curl` ≥ 7.81 | 22.04 = 7.81; 24.04 = 8.5 | Download tarball + sha256 | [CITED: curl.se/docs/manpage.html] `-fsSL` = fail silently / silent / follow-redirects; `-f` is critical — without it a 404 returns HTML and the sha256 check misses the real error |
| `cloud-image-utils` (Ubuntu pkg) | Ubuntu 24.04 runners ship it | Generates cloud-init seed ISOs | [CITED: documentation.ubuntu.com/public-images/public-images-how-to/use-local-cloud-init-ds/] `cloud-localds seed.iso user-data meta-data` is the one-command seed generation path |
| `qemu-system-x86_64` | Ubuntu 24.04 runner = 8.2.2 | Boot cloud image with KVM | [CITED: github.com/orgs/community/discussions/8305] KVM is now available on hosted `ubuntu-24.04` runners (confirmed Oct 2025); requires udev rule `KERNEL=="kvm", GROUP="kvm", MODE="0666"` or similar to grant runner access |
| `softprops/action-gh-release@v2` | v2.6.2 (final Node 20 line) | Publish GitHub Release with assets | [VERIFIED: github.com/softprops/action-gh-release tree/v2] Last Node 20-compatible is v2.6.2; v3 requires Node 24 runtime. Supports `files:` glob, `generate_release_notes: true`, `draft`, `prerelease`, `body_path` |
| `jq` | 1.6+ (22.04) / 1.7 (24.04) | Extract catalog `pinned_version` in CI + installer | [VERIFIED: /usr/bin/jq present] Already a dependency via Phase 4 Docker images (added in 04-07 Rule-3 auto-fix) |
| `bash` | 5.1 (22.04) / 5.2 (24.04) | curl-installer + build-release.sh + boot.sh | [VERIFIED: Phase 2 provisioner scripts all set `set -euo pipefail`] Standard AgentLinux contract |
| `actions/checkout@v4` | v4 | Checkout repo in CI | [VERIFIED: already used in test.yml + release.yml Phase 1 scaffolds] |
| `actions/cache@v4` | v4 | Cache Ubuntu cloud images between runs | [CITED: github.com/actions/cache] Key on SHA256 of upstream image; cache hit means no re-download |
| `actions/setup-node@v4` | v4 with node-version: '22' | Node in CI | [VERIFIED: existing test.yml uses this] |

### Supporting

| Library / Tool | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| `fpm` (Ruby gem) | 1.17.0 (Oct 2025) | Build optional `.deb` from plugin/ | [VERIFIED: github.com/jordansissel/fpm] Optional per ADR-006. Requires `apt install -y ruby-dev build-essential` + `gem install fpm`. Minimal invocation `fpm -s dir -t deb -n agentlinux -v 0.3.0 --prefix /opt/agentlinux plugin/` |
| `ssh` / `scp` (openssh-client) | — | SSH into QEMU guest | Ubuntu runner ships it; boot.sh uses `ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i <keyfile> -p 2222 root@localhost` |
| `nc` / `ncat` | — | Poll guest port 22 before SSH | `nc -z localhost 2222` returns 0 when port is accepting |
| `cloud-utils` ships `cloud-localds` in Ubuntu 24.04 runner image | — | — | Already installed on hosted runners; no `apt install` step needed per qemu-harness SKILL.md §Local prerequisites |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `sha256sum --tag` (BSD style) | GNU default `<hash>  <filename>` | [CITED: man7.org/linux/man-pages/man1/sha256sum.1.html] Both read back fine with `sha256sum -c`. BSD-style is marginally more portable across BSDs if we later port. **Recommendation: use GNU default** — simpler, one less flag, and we don't claim BSD support. |
| `cosign sign-blob` / GPG-signed releases | Simple SHA256 only | GPG = v0.4+ (explicitly deferred in ADR-006). Adds key-ceremony + user verification friction. v0.3.0 trust story is HTTPS + SHA256 only. |
| GitHub API `/releases/latest` | Permalink `/releases/latest/download/<asset>` | [CITED: docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api] API is 60 req/hr unauthenticated. Permalink redirects are rate-unlimited (served via CDN). **Use permalink.** API only as fallback if we ever need the version *string* (we don't — the tarball carries a VERSION marker). |
| `wget` | `curl` | Both work; `curl -fsSL` is the documented v0.3.0 idiom per ADR-006. Minimal Ubuntu cloud images ship `curl`; `wget` only sometimes. |
| `docker save` / OCI images | Tarball | Out of scope per ADR-001 pivot: AgentLinux is an installable extension, not a container. |
| Snap | curl-pipe-bash + optional `.deb` | Disqualified per ADR-009. |
| `esbuild --bundle` for CLI | Current `tsc` build that ships `dist/` + `node_modules/` | HARNESS.md §1.4 originally specified esbuild bundle; Phase 4 shipped tsc + node_modules bundle instead (Phase 4 Plan 04-06 Docker builder stage). **Phase 6 inherits the existing Phase 4 shape** — tarball includes `plugin/cli/dist/` + `plugin/cli/node_modules/`. Revisit bundling in v0.4+. |

**Installation (one-time, for CI runner):**

```bash
# cloud-image-utils and qemu are preinstalled on ubuntu-24.04 hosted runner.
# Only fpm needs an explicit install step if .deb ships in v0.3.0:
sudo apt-get update
sudo apt-get install -y ruby-dev build-essential
sudo gem install --no-document fpm
```

**Version verification (performed 2026-04-20 during research):**

```bash
npm view @anthropic-ai/claude-code version   # → 2.1.114 (newer than catalog 2.1.98 — normal drift)
npm view get-shit-done-cc version             # → 1.38.1 (newer than catalog 1.37.1)
npm view playwright version                   # → 1.59.1 (matches catalog exactly)
```

These three versions are what Phase 6 CI installs in the **pinned-combo gate** (TST-08). The release-gate job reads `pinned_version` fields from `plugin/catalog/catalog.json` via `jq`, so a version bump in the catalog auto-propagates. The upstream latest (2.1.114 vs. 2.1.98) is exactly the divergence scenario `agentlinux upgrade` addresses — Phase 6 does not attempt to close it.

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                      DEVELOPER: git tag v0.3.0                       │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ push v0.3.0
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│             .github/workflows/release.yml  (on tag v*.*.*)           │
│                                                                       │
│  GATE 1: pre-commit + cli-unit  ◀── reuses test.yml jobs             │
│          │ needs: success                                             │
│          ▼                                                            │
│  GATE 2: docker-matrix  (ubuntu-22.04 × ubuntu-24.04)                │
│          │ ./tests/docker/run.sh — 66/66 bats incl. 51-*.bats        │
│          │ needs: success                                             │
│          ▼                                                            │
│  GATE 3: qemu-matrix   (ubuntu-22.04 × ubuntu-24.04 cloud images)    │
│          │ ./tests/qemu/boot.sh — fresh VM, installer over SSH,      │
│          │                        full bats incl. 51-*.bats (TST-05) │
│          │ needs: success                                             │
│          ▼                                                            │
│  GATE 4: pinned-combo  (ubuntu-24.04 Docker, all catalog agents      │
│          │               installed at pinned_version, 66/66 bats)    │
│          │ needs: success                                             │
│          ▼                                                            │
│  BUILD:  scripts/build-release.sh v0.3.0                             │
│          │  ├─ tar --sort=name --owner=0 --group=0 … plugin/         │
│          │  ├─ sha256sum → tarball.sha256                            │
│          │  ├─ cp plugin/catalog/catalog.json → catalog-v0.3.0.json  │
│          │  └─ (optional) fpm -s dir -t deb → agentlinux_0.3.0.deb   │
│          ▼                                                            │
│  PUBLISH: softprops/action-gh-release@v2                             │
│          │  Attaches: tar.gz, tar.gz.sha256, catalog-v0.3.0.json,   │
│          │            (optional) .deb                                 │
│          │  Body: generate_release_notes: true                        │
│          ▼                                                            │
│          ┌────────────────────────────────────┐                      │
│          │  GitHub Release v0.3.0             │                      │
│          │  (permalinks /releases/latest/*)   │                      │
│          └─────────────┬──────────────────────┘                      │
└────────────────────────┼────────────────────────────────────────────┘
                         │
                         │  consumed by:
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│  USER:  curl -fsSL https://agentlinux.org/install.sh | sudo bash     │
│                               │                                       │
│                               ▼                                       │
│  packaging/curl-installer/install.sh   (served from GH Pages         │
│                                         static redirect)              │
│                                                                       │
│    main() {                                                           │
│      check_root                                                       │
│      detect_ubuntu_version                    ◀── /etc/os-release    │
│      resolve_version ($AGENTLINUX_VERSION || /releases/latest)        │
│      tmpdir=$(mktemp -d)                                             │
│      curl -fsSL .../agentlinux-<v>.tar.gz      → $tmpdir/tarball     │
│      curl -fsSL .../agentlinux-<v>.tar.gz.sha256 → $tmpdir/.sha256   │
│      (cd $tmpdir && sha256sum -c *.sha256)     ◀── FAIL-FAST if bad │
│      mkdir -p /opt/agentlinux/install/<v>                             │
│      tar -xzf $tarball -C /opt/agentlinux/install/<v>                 │
│      exec /opt/agentlinux/install/<v>/plugin/bin/agentlinux-install "$@"│
│    }                                                                  │
│    main "$@"   ◀── wrapper pattern: partial download cannot execute  │
│                                                                       │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼  (delegates to Phase 2 entrypoint)
                       plugin/bin/agentlinux-install
                       ├─ provisioner/10-agent-user.sh   (BHV-01)
                       ├─ provisioner/20-sudoers.sh      (INST-06)
                       ├─ provisioner/30-nodejs.sh       (RT-01)
                       ├─ provisioner/40-path-wiring.sh  (BHV-02..06)
                       └─ provisioner/50-registry-cli.sh (CLI-01)
                                + stage catalog-<v>.json → /opt/agentlinux/catalog/<v>/
```

### Component Responsibilities

| File / Dir | Owner | Responsibility | Phase 6 Action |
|------------|-------|----------------|----------------|
| `scripts/build-release.sh` | NEW | Assemble tarball + SHA256 + catalog snapshot + optional .deb | CREATE (Plan 06-A) |
| `packaging/curl-installer/install.sh` | Phase 1 stub | SHA256-verified download → exec agentlinux-install | REPLACE body (Plan 06-B) |
| `install.sh` at repo root OR `website/install.sh` | GH Pages site | Serve at `agentlinux.org/install.sh` | CREATE or alias (Plan 06-B part 2) |
| `tests/qemu/boot.sh` | Phase 1 stub | Boot cloud image, SSH in, run installer + bats, teardown | CREATE full body (Plan 06-C) |
| `tests/qemu/cloud-init/user-data` | Phase 1 empty dir | Template for cloud-init seed (sshkey inject, apt update) | CREATE (Plan 06-C) |
| `tests/qemu/cloud-init/meta-data` | Phase 1 empty dir | Template for cloud-init seed (instance-id) | CREATE (Plan 06-C) |
| `tests/qemu/cloud-images.txt` | NEW | URL + SHA256 manifest for image cache | CREATE (Plan 06-C) |
| `.github/workflows/nightly-qemu.yml` | Phase 1 empty-guard scaffold | Nightly cron runs boot.sh | POPULATE matrix (Plan 06-C) |
| `.github/workflows/release.yml` | Phase 1 scaffold | 4-gate release pipeline + publish | EXPAND to full pipeline (Plan 06-D) |
| `packaging/deb/build.sh` | Phase 1 empty dir | fpm wrapper — optional | CREATE if .deb ships (Plan 06-A optional) |
| `README.md` | MISSING (only `index.html` at root) | User-facing landing/install/verify/uninstall | CREATE (Plan 06-E) |
| `docs/STABILITY-MODEL.md` | NEW | One-page ADR-011 user-friendly | CREATE optionally (Plan 06-E) |

### Pattern 1: SHA256 creation and verification round-trip

**What:** GNU `sha256sum` produces a file you can verify with `sha256sum -c`. Both GNU default (`<hash>  <file>`) and BSD-style (`SHA256 (<file>) = <hash>`) formats are supported on input by the same `-c` command — no format-mismatch trap.

**When to use:** Every release tarball + its sibling `.sha256` (non-negotiable per ADR-006, INST-03).

**Example:**

```bash
# Build side (scripts/build-release.sh): create with default GNU format.
# Source: coreutils man page sha256sum(1), verified via man7.org.
cd "$DIST_DIR"
sha256sum "agentlinux-${TAG}.tar.gz" > "agentlinux-${TAG}.tar.gz.sha256"
# Output line: "3a1b…  agentlinux-v0.3.0.tar.gz"

# Verify side (packaging/curl-installer/install.sh):
cd "$TMPDIR"
if ! sha256sum -c "agentlinux-${TAG}.tar.gz.sha256"; then
  die "SHA256 verification failed for agentlinux-${TAG}.tar.gz — aborting (possible tampering or partial download)"
fi
```

**Note on `--tag`:** `sha256sum --tag <file>` produces BSD-style. Either format works; **use GNU default** (simpler — one fewer flag).

### Pattern 2: Hardened curl-pipe-bash wrapper (main(){}; main)

**What:** The entire install logic is wrapped inside a single `main()` function. The very last line of the file is `main "$@"`. If the download is truncated mid-file, bash parses up to the EOF and calls `main` — which doesn't exist — and fails before executing anything destructive.

**When to use:** Every curl-pipe-bash installer (INST-03 security envelope). The canonical defense against partial-download execution.

**Example:**

```bash
#!/usr/bin/env bash
# packaging/curl-installer/install.sh — curl-pipe-bash safe wrapper
# Source: kicksecure.com/wiki/Dev/curl_bash_pipe + dev.to/operous/how-to-build-a-trustworthy-curl-pipe-bash-workflow-4bb
set -euo pipefail

# The entire body is inside main(); bash only *calls* anything at the final line.
# If the TCP stream is cut mid-file, bash never reaches `main "$@"` and nothing
# destructive happens.
main() {
  check_root
  detect_ubuntu_version
  local tag
  tag=$(resolve_version)
  local tmpdir
  tmpdir=$(mktemp -d -t agentlinux-install.XXXXXX)
  trap 'rm -rf "$tmpdir"' EXIT

  local base="https://github.com/${ORG}/agent-linux/releases/download/${tag}"
  local tarball="agentlinux-${tag}.tar.gz"

  curl -fsSL "${base}/${tarball}" -o "${tmpdir}/${tarball}"
  curl -fsSL "${base}/${tarball}.sha256" -o "${tmpdir}/${tarball}.sha256"

  (cd "$tmpdir" && sha256sum -c "${tarball}.sha256") \
    || die "SHA256 verification failed; refusing to install"

  local inst="/opt/agentlinux/install/${tag#v}"
  mkdir -p "$inst"
  tar --extract --gzip --file="${tmpdir}/${tarball}" --directory="$inst" --strip-components=0

  # Phase 2's agentlinux-install entrypoint; all flags pass-through.
  exec "${inst}/plugin/bin/agentlinux-install" "$@"
}

# ... helpers above: die, check_root, detect_ubuntu_version, resolve_version ...

main "$@"
```

### Pattern 3: Reproducible tarball + SHA256 build script

**What:** `scripts/build-release.sh v<X.Y.Z>` assembles `plugin/` into a gzipped tarball with deterministic metadata (sort by name, numeric owner=0, group=0, mtime pinned to commit date). Re-running on the same commit produces a byte-identical tarball. SHA256 matches across runs.

**When to use:** The release-pipeline build step (gate 6 in release.yml). Also invocable locally for reproducibility testing.

**Example:**

```bash
#!/usr/bin/env bash
# scripts/build-release.sh — assemble release artifacts.
# Source: gnu.org/software/tar/manual/html_section/Reproducibility.html
# Source: reproducible-builds.org/docs/archives/
set -euo pipefail

TAG=${1:?usage: scripts/build-release.sh v<X.Y.Z>}
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
  printf 'tag %s does not match vX.Y.Z[-suffix]\n' "$TAG" >&2
  exit 64
fi
VERSION=${TAG#v}

# 1. Verify version consistency (locks CLI package.json + tag + catalog.version).
CLI_V=$(jq -r .version plugin/cli/package.json)
CAT_V=$(jq -r .version plugin/catalog/catalog.json)
[[ "$CLI_V" == "$VERSION" ]] || { echo "plugin/cli/package.json version=$CLI_V ≠ tag=$VERSION"; exit 1; }
[[ "$CAT_V" == "$VERSION" ]] || { echo "plugin/catalog/catalog.json version=$CAT_V ≠ tag=$VERSION"; exit 1; }

# 2. Ensure CLI is built (dist/ exists; node_modules/ installed for runtime).
(cd plugin/cli && npm install --no-audit --no-fund && npm run build)

# 3. Prepare dist dir.
mkdir -p dist
cd "$(git rev-parse --show-toplevel)"
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git log -1 --pretty=%ct HEAD)}
export SOURCE_DATE_EPOCH

# 4. Reproducible tarball. `--sort=name --owner=0 --group=0 --numeric-owner`
# erases filesystem-specific metadata. `--mtime=@SOURCE_DATE_EPOCH` pins
# timestamps to the commit's author-date.
TARBALL="dist/agentlinux-${TAG}.tar.gz"
tar \
  --sort=name \
  --owner=0 --group=0 --numeric-owner \
  --mtime="@${SOURCE_DATE_EPOCH}" \
  --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
  --create --gzip --file="${TARBALL}" \
  plugin/

# 5. Sibling SHA256 (GNU default format; `sha256sum -c` reads it back).
( cd dist && sha256sum "agentlinux-${TAG}.tar.gz" > "agentlinux-${TAG}.tar.gz.sha256" )

# 6. Catalog snapshot (CAT-05): byte-for-byte copy.
cp plugin/catalog/catalog.json "dist/catalog-${TAG}.json"

# 7. Optional: fpm .deb (ADR-006 optional). Skip if --skip-deb flag or if fpm missing.
if command -v fpm >/dev/null && [[ "${SKIP_DEB:-}" != "1" ]]; then
  fpm -s dir -t deb \
    --name agentlinux \
    --version "$VERSION" \
    --description "Agent-ready Ubuntu environment: correctly-owned Node.js + curated agent catalog" \
    --url https://agentlinux.org \
    --license Apache-2.0 \
    --architecture all \
    --depends curl \
    --after-install packaging/deb/postinst.sh \
    --chdir plugin/ \
    --package "dist/agentlinux_${VERSION}_all.deb" \
    .
fi

printf 'Built: %s (+ .sha256 + catalog + optional .deb)\n' "$TARBALL"
```

### Pattern 4: QEMU boot.sh — cloud image + cloud-init + SSH in + bats over SSH

**What:** Download (cache + SHA-verify) the Ubuntu cloud image, generate a cloud-init seed ISO injecting a per-run SSH pubkey, boot QEMU with `-enable-kvm -drive …,snapshot=on`, poll localhost:2222 until SSH is up, scp the plugin tarball into the guest, run the installer over SSH, run bats over SSH, shutdown + cleanup.

**When to use:** TST-03 nightly-qemu.yml cron + release.yml QEMU gate.

**Example:**

```bash
#!/usr/bin/env bash
# tests/qemu/boot.sh — boot cloud image + cloud-init seed + run installer + bats
# Source: docs.cloud-init.io/en/latest/reference/examples.html
# Source: documentation.ubuntu.com/public-images/public-images-how-to/use-local-cloud-init-ds/
# Source: qemu-harness SKILL.md §Target boot flow
set -euo pipefail

UBUNTU_VERSION=${1:?usage: tests/qemu/boot.sh <22.04|24.04>}
case "$UBUNTU_VERSION" in
  22.04) RELEASE=jammy ;;
  24.04) RELEASE=noble ;;
  *) printf 'unsupported: %s\n' "$UBUNTU_VERSION" >&2; exit 64 ;;
esac

CACHE=${AGENTLINUX_QEMU_CACHE:-$HOME/.cache/agentlinux/qemu}
mkdir -p "$CACHE"
IMG_NAME="${RELEASE}-server-cloudimg-amd64.img"
IMG="$CACHE/$IMG_NAME"
SHASUMS="$CACHE/${RELEASE}-SHA256SUMS"

# 1. Download + verify the cloud image (cached between runs via actions/cache).
if [[ ! -f "$IMG" ]]; then
  curl -fsSL -o "$IMG" "https://cloud-images.ubuntu.com/releases/${RELEASE}/release/${IMG_NAME}"
fi
curl -fsSL -o "$SHASUMS" "https://cloud-images.ubuntu.com/releases/${RELEASE}/release/SHA256SUMS"
( cd "$CACHE" && sha256sum --ignore-missing --check "${SHASUMS}" ) \
  || { printf 'cloud image SHA256 mismatch — refusing to boot\n' >&2; exit 1; }

# 2. Generate per-run SSH keypair (NEVER committed).
RUN_DIR=$(mktemp -d -t agentlinux-qemu.XXXXXX)
trap 'rm -rf "$RUN_DIR"' EXIT
ssh-keygen -t ed25519 -N '' -f "$RUN_DIR/id_ed25519" -C 'agentlinux-qemu' >/dev/null

# 3. Generate cloud-init seed.
cat > "$RUN_DIR/meta-data" <<EOF
instance-id: agentlinux-ci-${RELEASE}-$(date +%s)
local-hostname: agentlinux-ci
EOF

cat > "$RUN_DIR/user-data" <<EOF
#cloud-config
ssh_pwauth: false
disable_root: false
users:
  - name: root
    ssh_authorized_keys:
      - $(cat "$RUN_DIR/id_ed25519.pub")
packages:
  - bats
  - jq
package_update: true
runcmd:
  - systemctl enable --now ssh
EOF

cloud-localds "$RUN_DIR/seed.iso" "$RUN_DIR/user-data" "$RUN_DIR/meta-data"

# 4. Boot QEMU (backgrounded). snapshot=on keeps cache pristine.
qemu-system-x86_64 \
  -cpu host -enable-kvm \
  -m 2048 -smp 2 \
  -drive "file=${IMG},if=virtio,snapshot=on" \
  -drive "file=${RUN_DIR}/seed.iso,format=raw,readonly=on" \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  -device virtio-net,netdev=n0 \
  -nographic -serial file:"${RUN_DIR}/serial.log" \
  &
QEMU_PID=$!
trap 'kill -TERM $QEMU_PID 2>/dev/null; rm -rf "$RUN_DIR"' EXIT

# 5. Poll SSH (cloud-init can take 60–120s to finish on first boot).
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i ${RUN_DIR}/id_ed25519 -p 2222"
for i in $(seq 1 60); do
  if ssh $SSH_OPTS root@localhost 'cloud-init status --wait' 2>/dev/null; then
    break
  fi
  sleep 5
done

# 6. scp the plugin tarball (built in a sibling workflow step or inline).
scp $SSH_OPTS dist/agentlinux-*.tar.gz root@localhost:/tmp/

# 7. Run installer + bats over SSH.
ssh $SSH_OPTS root@localhost 'cd /tmp && tar -xzf agentlinux-*.tar.gz && bash plugin/bin/agentlinux-install'
ssh $SSH_OPTS root@localhost 'cd /tmp && bats plugin/../tests/bats/'
BATS_STATUS=$?

# 8. Poweroff + reap.
ssh $SSH_OPTS root@localhost 'poweroff' || true
wait $QEMU_PID || true

exit $BATS_STATUS
```

### Pattern 5: GitHub Pages static install.sh hosting

**What:** GitHub Pages does not support server-side redirects. To serve `https://agentlinux.org/install.sh`, the *file content itself* must be at `install.sh` in the Pages root (= repo root per existing `CNAME: agentlinux.org` + `.github/workflows/deploy.yml`). The simplest approach: **publish `packaging/curl-installer/install.sh` literally at repo root** via a small sync in the deploy workflow (or ship it as both `packaging/curl-installer/install.sh` for the repo canon and `/install.sh` for the Pages surface — deploy.yml copies the canonical file).

**When to use:** Closing INST-03's "one-command install" UX promise. A literal `https://agentlinux.org/install.sh` URL that curl can fetch and bash can execute.

**Example:**

```yaml
# .github/workflows/deploy.yml  (extend existing)
# After existing GitHub Pages deploy, copy packaging/curl-installer/install.sh
# to the root of the site. install.sh must use the GitHub Releases permalink
# pattern for version resolution.
      - name: Stage install.sh for GH Pages
        run: cp packaging/curl-installer/install.sh install.sh
      - name: Setup Pages
        uses: actions/configure-pages@v5
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v4
        with:
          path: '.'
```

**Security note:** The `install.sh` served from `agentlinux.org` is the exact same content as the canonical `packaging/curl-installer/install.sh`. A user running `curl -fsSL https://agentlinux.org/install.sh | sudo bash` executes the script the tag's commit produced, transported via HTTPS from GitHub Pages. The tarball it then downloads is SHA256-verified against the sibling `.sha256` published alongside the tagged release. Two independent trust channels.

### Pattern 6: release.yml 4-gate pipeline with `needs:` sequencing

**What:** Each CI gate is a separate job; later jobs `needs:` earlier ones. GitHub Actions' dependency graph auto-cancels downstream gates when an earlier one fails, producing a clear pass/fail pattern per gate in the Actions UI. `concurrency: group: release-${{ github.ref }}` prevents two tag-release runs from racing.

**When to use:** `.github/workflows/release.yml` — the v0.3.0 release enforcement mechanism.

**Example:**

```yaml
# .github/workflows/release.yml — Phase 6 full-body
name: release
on:
  push:
    tags: ['v*.*.*']
  workflow_dispatch:
    inputs:
      tag:
        description: Release tag (e.g. v0.3.0)
        required: true

concurrency:
  group: release-${{ github.ref }}
  # cancel-in-progress: false — never cancel a release mid-build
  # (see community/community#53506 caveat; acceptable for tag-push since
  # concurrent v* tags are unusual).

permissions:
  contents: write

jobs:
  resolve:
    runs-on: ubuntu-24.04
    outputs:
      tag: ${{ steps.tag.outputs.value }}
    steps:
      - uses: actions/checkout@v4
      - id: tag
        run: |
          tag="${INPUT_TAG:-${GITHUB_REF##*/}}"
          if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
            echo "::error::invalid tag '$tag'"; exit 1
          fi
          echo "value=$tag" >> "$GITHUB_OUTPUT"
        env:
          INPUT_TAG: ${{ inputs.tag }}

  gate-1-precommit:
    needs: resolve
    uses: ./.github/workflows/test.yml   # reuse existing pre-commit + cli-unit

  gate-2-docker:
    needs: gate-1-precommit
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix:
        ubuntu: [ubuntu-22.04, ubuntu-24.04]
    steps:
      - uses: actions/checkout@v4
      - run: bash tests/docker/run.sh ${{ matrix.ubuntu }}

  gate-3-qemu:
    needs: gate-2-docker
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix:
        ubuntu: [22.04, 24.04]
    steps:
      - uses: actions/checkout@v4
      - name: Enable /dev/kvm access
        # Sources: github/community#8305 (Oct 2025 confirmation KVM now works);
        # actuated.com/blog/kvm-in-github-actions (udev rule pattern).
        run: |
          sudo bash -c 'echo "KERNEL==\"kvm\", GROUP=\"kvm\", MODE=\"0666\"" > /etc/udev/rules.d/99-kvm.rules'
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm
          [[ -r /dev/kvm && -w /dev/kvm ]] || { echo "::error::/dev/kvm not accessible"; exit 1; }
      - name: Build plugin tarball (pre-release local copy)
        run: bash scripts/build-release.sh ${{ needs.resolve.outputs.tag }}
      - name: Cache Ubuntu cloud images
        uses: actions/cache@v4
        with:
          path: ~/.cache/agentlinux/qemu
          key: cloud-image-${{ matrix.ubuntu }}-${{ hashFiles('tests/qemu/cloud-images.txt') }}
      - name: QEMU boot + installer + bats
        run: bash tests/qemu/boot.sh ${{ matrix.ubuntu }}

  gate-4-pinned-combo:
    needs: gate-3-qemu
    runs-on: ubuntu-24.04
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      # Runs in ubuntu-24.04 Docker (pinned dev env per CONTEXT). Installs all
      # three real agents at pinned_version and re-runs 50-*.bats + 51-*.bats
      # — the canonical AgentLinux combo before we cut the tag.
      - run: bash tests/docker/run.sh ubuntu-24.04

  build:
    needs: [resolve, gate-4-pinned-combo]
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '22' }
      - name: Install fpm (optional .deb)
        run: |
          sudo apt-get install -y ruby-dev build-essential
          sudo gem install --no-document fpm
      - name: Build release artifacts
        run: bash scripts/build-release.sh ${{ needs.resolve.outputs.tag }}
      - uses: actions/upload-artifact@v4
        with:
          name: release-artifacts
          path: dist/

  publish:
    needs: [resolve, build]
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-24.04
    permissions:
      contents: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: release-artifacts
          path: dist/
      - uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ needs.resolve.outputs.tag }}
          generate_release_notes: true
          files: |
            dist/agentlinux-*.tar.gz
            dist/agentlinux-*.tar.gz.sha256
            dist/catalog-*.json
            dist/agentlinux_*.deb
```

### Pattern 7: README shape + version-stamp marker

**What:** Root `README.md` is the GitHub landing page. ADR-011 stability-model summary lives there (user-facing) with the ADR itself as the authoritative reference. A `<!-- VERSION: v0.3.0 -->` marker is sed-replaceable by `build-release.sh` each release so the install command's version reference stays fresh.

**When to use:** DOC-01.

**Example skeleton:**

```markdown
<!-- VERSION: v0.3.0 -->

# AgentLinux

> Agent-ready Ubuntu, one command.

AgentLinux provisions a dedicated agent user with a correctly-owned Node.js
runtime so agents like Claude Code and GSD self-update without EACCES or sudo
fights. Curated stable versions; explicit override with `agentlinux pin`.

![release](https://github.com/<org>/agent-linux/actions/workflows/release.yml/badge.svg)

## Install

```bash
curl -fsSL https://agentlinux.org/install.sh | sudo bash
```

The installer verifies the release tarball's SHA256 before executing anything.

## Verify

```bash
agentlinux list                    # shows 3 available agents
agentlinux install claude-code     # installs Claude Code for the agent user
claude --version                   # confirms install
```

## Uninstall

```bash
sudo agentlinux-install --purge                    # remove AgentLinux, keep Node
sudo agentlinux-install --purge --remove-nodejs    # full cleanup
```

## Stability model

AgentLinux ships *curated combos* of agent versions that pass our full test
matrix together. Run `agentlinux list` to see the combo for your install; run
`agentlinux upgrade` to reconcile when a new release is out. If you want to run
ahead with `claude update` or `npm install -g @latest`, you can — `agentlinux
upgrade` will show a three-way diff (keep-override / accept-curated /
accept-latest) next time you reconcile. Set sticky overrides with
`agentlinux pin <name>=latest`.

Details: [`docs/decisions/011-stability-first-version-pinning.md`](docs/decisions/011-stability-first-version-pinning.md).

## Requirements

- Ubuntu 22.04 LTS or 24.04 LTS (x86_64)
- Root / sudo access to run the installer

## Links

- [Source + issues](https://github.com/<org>/agent-linux)
- [Releases](https://github.com/<org>/agent-linux/releases)
- [Architecture decisions](docs/decisions/)
```

Update at release time:

```bash
sed -i "s|<!-- VERSION: v[0-9.]\+ -->|<!-- VERSION: ${TAG} -->|" README.md
```

### Anti-Patterns to Avoid

- **Partial-download execution** — curl-pipe-bash without the `main(){}; main "$@"` wrapper is dangerous: bash may execute partial content. Fix: wrapper pattern (Pattern 2).
- **TLS-only trust** — relying on HTTPS alone means any compromise of the release-host CDN executes arbitrary code. Fix: sibling SHA256 file (non-negotiable per ADR-006/INST-03).
- **GitHub API `/latest` at scale** — 60 req/hr unauthenticated limit; a popular project burns it fast. Fix: `https://github.com/<org>/agent-linux/releases/latest/download/<asset>` permalink (served by CDN, no rate limit).
- **Hardcoded version in install.sh** — bakes the installer to one release; users can never override. Fix: `AGENTLINUX_VERSION` env var with `releases/latest` redirect fallback.
- **Mutable `latest` tarball asset** — if you attach `agentlinux-latest.tar.gz` to every release, old SHA256 files mismatch. Fix: always version the tarball filename; use `releases/latest/download/` for the permalink if you need "latest."
- **Docker-only release gate** — ADR-007 explicitly disqualifies. QEMU catches systemd, locale, cloud-init path regressions Docker misses.
- **`cancel-in-progress: true` on release.yml** — cancels an in-progress release when a retag happens, leaving a half-published release. Fix: `cancel-in-progress: false` for release workflows.
- **Cloud image downloaded but not SHA-verified** — a poisoned cache would execute in the release gate. Fix: verify every cache hit against `SHA256SUMS` from `cloud-images.ubuntu.com/releases/<release>/release/`.
- **Untagged `.deb` dependencies** — omitting `--depends curl` means `dpkg -i` succeeds but install.sh inside runs `curl` and fails. Fix: declare fpm `--depends` for every external binary the installer references.
- **`./dist/` tracked in git** — bloats the repo; Phase 4 gitignores `plugin/cli/dist/`. Fix: keep `dist/` gitignored; build in CI; upload as artifact.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Download + verify SHA256 | Ad-hoc `openssl sha256 \| awk` compare | `sha256sum -c <sidecar>.sha256` | Handles both GNU and BSD formats; well-tested; on every Ubuntu |
| Tarball reproducibility | Manual `find \| sort \| cpio` | `tar --sort=name --owner=0 --group=0 --mtime=@<epoch>` | One command, GNU tar 1.28+ supports all the knobs; documented by reproducible-builds.org |
| Cloud-init seed ISO | Hand-roll ISO 9660 filesystem | `cloud-localds seed.iso user-data meta-data` | One command; handles ISO metadata + genisoimage internals |
| `.deb` package layout | Hand-roll `DEBIAN/control` + `postinst` | `fpm -s dir -t deb` | Handles control file, md5sums, triggers, dependency resolution, postinst hooks |
| GitHub Release upload with assets | `gh release create` loop | `softprops/action-gh-release@v2` | Atomic upload with multiple asset globs, auto-generate release notes, draft/prerelease flags |
| QEMU boot polling | `sleep 30; ssh; echo pray` | Poll `cloud-init status --wait` + `nc -z localhost 2222` | Deterministic; `cloud-init status --wait` returns only when the seed user-data is fully applied |
| Release tag validation | Rely on users spelling `v0.3.0` correctly | Regex gate `^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$` in build-release.sh AND release.yml | Catches typos before the build step starts |
| GitHub Actions concurrency semantics | Manual tmpfile locking | `concurrency: { group: release-<ref>, cancel-in-progress: false }` | Declarative; GitHub's scheduler enforces |

**Key insight:** Every piece of this phase has a canonical Linux tool. The phase's engineering is *composing* them in the right order with fail-fast exits — not inventing any piece. If a plan finds itself writing a SHA256 implementation or a tar-directory walker, that's a red flag.

## Runtime State Inventory

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `/opt/agentlinux/catalog/<X.Y.Z>/catalog.json` — staged by installer at install time from the tarball's catalog snapshot (CAT-05 mechanism). `agentlinux upgrade` reads this. | Phase 6 must ensure the tarball ships `catalog.json` at a deterministic path the `50-registry-cli.sh` provisioner knows; and that the *sibling* `catalog-v<X.Y.Z>.json` is attached to the GitHub Release (so `agentlinux upgrade` can also fetch a newer snapshot out-of-band). Existing Phase 4 Plan 04-06 `50-registry-cli.sh` already stages `/opt/agentlinux/catalog/<version>/catalog.json` from the source tree — Phase 6 verifies this path is fed by the tarball, not by a git checkout. |
| Live service config | `https://agentlinux.org` — GitHub Pages site, content in repo root. Needs `install.sh` present at the Pages root so the URL `agentlinux.org/install.sh` serves the canonical curl-installer. | Phase 6 `.github/workflows/deploy.yml` extension OR commit `install.sh` at root as a literal copy of `packaging/curl-installer/install.sh` (with a build-time sync). |
| OS-registered state | **None** — AgentLinux does not register systemd services, cron jobs, or pm2 processes at the OS level beyond what Phase 2 provisioners write (those are in-tarball + covered by INST-04 teardown). The release pipeline itself registers no persistent OS state on the user's machine. | No action. |
| Secrets / env vars | `GITHUB_TOKEN` — automatic, used by `action-gh-release@v2` for publishing. No external secrets (no PPA key, no GPG key in v0.3.0 per ADR-006 deferral of GPG to v0.4+). | No action. |
| Build artifacts | (1) `plugin/cli/dist/` + `plugin/cli/node_modules/` (gitignored, tsc + npm-install output) — must be present in the tarball per Phase 4 Plan 04-06 Docker builder pattern. (2) `dist/` at repo root during a build — output of build-release.sh; not committed. | Phase 6 build-release.sh must run `(cd plugin/cli && npm install + npm run build)` before taring; `dist/` at repo root is CI-ephemeral + uploaded as artifact. |

## Common Pitfalls

### Pitfall 1: Partial download executes destructive code

**What goes wrong:** A flaky connection truncates `install.sh` mid-script. Bash executes the partial file and runs only the first half — possibly destructive operations (rm, chmod, userdel) without the verification + early-return guard that would have followed.

**Why it happens:** Bash is a streaming interpreter. Without syntactic framing, any prefix of a valid script is also valid.

**How to avoid:** The `main(){}; main "$@"` wrapper (Pattern 2). The entire script body is defined inside `main()`; the only top-level statement is the final `main "$@"` call. A truncated file has an undefined function reference and exits with an error instead of executing partial code.

**Warning signs:** Review-loop red flag: a curl-installer with top-level statements (not inside `main()`). Bash-engineer subagent should flag.

### Pitfall 2: `curl` without `-f` treats 404 HTML as success

**What goes wrong:** GitHub Releases returns a 404 HTML page for a missing asset. `curl` without `-f` writes the HTML to the output file and exits 0. Subsequent `sha256sum -c` fails — but the error message points at "checksum mismatch" rather than "asset missing," which sends debugging down the wrong path.

**Why it happens:** `curl`'s default treats any HTTP response as "success" — HTTP-level status codes (4xx/5xx) don't become non-zero exits without `-f`.

**How to avoid:** Always `curl -fsSL` in the curl-installer and in build-release.sh. `-f` = fail fast on HTTP errors; `-s` = silent; `-L` = follow redirects.

**Warning signs:** A `sha256sum -c` failure with message "agentlinux-X.Y.Z.tar.gz: FAILED" where a quick `head <tarball>` shows HTML content — diagnostic hint in install.sh's error branch: `file "$tarball" | grep -q 'HTML document' && die "received HTML instead of tarball — upstream 404?"`.

### Pitfall 3: `sha256sum -c` works on both formats, but mixed-format checksum files don't

**What goes wrong:** Someone hand-edits a `.sha256` file mixing GNU-default (`<hash>  <file>`) and BSD-style (`SHA256 (<file>) = <hash>`) lines. `sha256sum -c` fails on the BSD line with "no properly formatted checksum lines found."

**Why it happens:** The BSD-style re-encoding was an optional `--tag` addition; `-c` needs the file's entire content to be *either* format, not both.

**How to avoid:** Pick one format (recommend GNU default) and produce the file programmatically from `sha256sum` — never hand-edit. Include a grep in review: `grep -E "^SHA256 \(" dist/*.sha256 && die "mixed format"` if we enforce GNU-only.

**Warning signs:** A `.sha256` file that contains both `<hash>  <file>` and `SHA256 (<file>) = <hash>` lines. Regression-prone when merging multiple build outputs.

### Pitfall 4: /dev/kvm present but runner user can't access it

**What goes wrong:** Hosted Ubuntu runners expose `/dev/kvm` — but the `runner` user isn't in the `kvm` group by default. `qemu-system-x86_64 -enable-kvm` fails with "failed to initialize KVM: Permission denied" and QEMU silently falls back to TCG (20-30× slower), pushing the QEMU gate over its 30-minute timeout.

**Why it happens:** GitHub Actions enabled KVM access in Oct 2025 but did not add the `runner` user to the `kvm` group.

**How to avoid:** Add a udev rule step early in the qemu job: `KERNEL=="kvm", GROUP="kvm", MODE="0666"` → `udevadm control --reload-rules && udevadm trigger --name-match=kvm` → verify `[[ -r /dev/kvm && -w /dev/kvm ]]` before invoking QEMU.

**Warning signs:** QEMU boot stalls + GitHub Actions timeout at 30min. `dmesg | grep kvm` inside runner shows "permission denied".

### Pitfall 5: SOURCE_DATE_EPOCH drift makes re-runs non-reproducible

**What goes wrong:** Two CI re-runs of the same tag produce two different SHA256s. Can't verify reproducibility or publish a signed checksum.

**Why it happens:** `tar --mtime=now` embeds the build's wall-clock time. Without pinning, re-runs diverge.

**How to avoid:** Set `SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct HEAD)` at the top of `build-release.sh` and `export` it before invoking `tar --mtime=@$SOURCE_DATE_EPOCH`. Also pass `--pax-option=delete=atime,delete=ctime` per [reproducible-builds.org](https://reproducible-builds.org/docs/archives/).

**Warning signs:** Re-running build-release.sh on the same commit produces a different SHA256.

### Pitfall 6: fpm ruby-gem install pulls compiler toolchain on runner

**What goes wrong:** `gem install fpm` pulls C extensions that build against system libs. On a fresh `ubuntu-24.04` runner without `ruby-dev` + `build-essential`, install fails with obscure compiler errors.

**Why it happens:** Ubuntu's `ruby` package is the interpreter only; gems with C extensions need headers.

**How to avoid:** If `.deb` ships in v0.3.0, explicit install step: `sudo apt-get install -y ruby-dev build-essential && sudo gem install --no-document fpm`. If fpm install is brittle, ADR-006 allows deferring `.deb` to v0.4+ — the curl-pipe-bash channel is sufficient.

**Warning signs:** `gem install fpm` fails with "can't find header files for ruby" or "make: command not found".

### Pitfall 7: `install.sh` at GH Pages root and `packaging/curl-installer/install.sh` drift

**What goes wrong:** Developer edits `packaging/curl-installer/install.sh` but forgets the sibling at repo root. User's `curl agentlinux.org/install.sh` gets stale content while the tarball version jumps forward. Install fails or — worse — succeeds with stale verification logic.

**Why it happens:** Two places to maintain the same file; no enforcement.

**How to avoid:** Make `packaging/curl-installer/install.sh` the single source of truth; deploy.yml copies it to repo root at site build time. OR: commit a `install.sh` symlink at root → `packaging/curl-installer/install.sh` (GitHub Pages follows symlinks for served content — verify before committing).

**Warning signs:** The two files have different mtimes or content; pre-commit or a drift-check hook catches divergence.

### Pitfall 8: Catalog snapshot path coupled to installer implementation

**What goes wrong:** Phase 6 publishes `catalog-v0.3.0.json` as a GitHub Release asset. Phase 4's `50-registry-cli.sh` provisioner stages `/opt/agentlinux/catalog/<version>/catalog.json` from the tarball's `plugin/catalog/catalog.json`. These are two copies of the same JSON, but if Phase 6 evolves the release-attached snapshot format (e.g., adds an `attestations:` field) without updating the in-tarball copy, `agentlinux upgrade` reads divergent data on the same install.

**Why it happens:** CAT-05 says "sibling of tarball + sha256"; ADR-011 says "installer stages the snapshot; `agentlinux upgrade` reads it." Both are true at install time, but the `upgrade` path may fetch a newer release's snapshot out-of-band, and that file's shape must be compatible with the installer-staged one.

**How to avoid:** The release-attached `catalog-v<X.Y.Z>.json` is always byte-for-byte `plugin/catalog/catalog.json` from the same tag. No post-build transformation. Build-release.sh uses `cp`, not `jq .` — preserves formatting. Document in the plan: "sibling snapshot = source snapshot, zero transformation."

**Warning signs:** A diff between `sha256sum dist/catalog-v0.3.0.json` and `sha256sum plugin/catalog/catalog.json` at release time is non-zero.

### Pitfall 9: `release.yml` concurrency cancels an in-progress release

**What goes wrong:** Developer force-pushes a tag or re-triggers `workflow_dispatch` mid-build. `cancel-in-progress: true` cancels the in-progress build; `softprops/action-gh-release@v2` either fails mid-publish (corrupt Release with some assets) or doesn't run at all.

**Why it happens:** Tag force-push is rare but possible; concurrency defaults to `cancel-in-progress: false` but easy to mis-set.

**How to avoid:** `concurrency: { group: release-${{ github.ref }}, cancel-in-progress: false }`. Document: never re-tag the same version — tag `v0.3.0-rc2` or `v0.3.1` instead.

**Warning signs:** A Release with only a subset of expected assets; build log truncated partway through the `publish` job.

### Pitfall 10: Cloud image cache poisoned (SHA256 not re-verified on cache hit)

**What goes wrong:** `actions/cache` serves a previously-cached `jammy-server-cloudimg-amd64.img`. Upstream hasn't changed, so cache hits. But the cache entry itself was tampered or corrupted mid-write. QEMU boot test runs against a modified image; installer bugs from production don't surface; the release ships.

**Why it happens:** Cache integrity is not a guarantee from `actions/cache` — the service stores binary blobs by key; only the key is hashed, not the content.

**How to avoid:** Re-verify `sha256sum --check SHA256SUMS` against the upstream manifest on every cache hit, not just on first download. `boot.sh` step 1 already does this in the Pattern 4 skeleton. Cache key includes `hashFiles('tests/qemu/cloud-images.txt')` so a rotated image URL + SHA triggers a fresh fetch.

**Warning signs:** QEMU passes in CI but the same image fails locally; `sha256sum` values differ between runs.

## Code Examples

Verified patterns from official sources. Linked in the Patterns section above:

- **Reproducible tar** — [gnu.org/software/tar/manual/html_section/Reproducibility.html](https://www.gnu.org/software/tar/manual/html_section/Reproducibility.html), [reproducible-builds.org/docs/archives/](https://reproducible-builds.org/docs/archives/)
- **sha256sum round-trip** — [man7.org/linux/man-pages/man1/sha256sum.1.html](https://man7.org/linux/man-pages/man1/sha256sum.1.html)
- **curl-pipe-bash wrapper** — [kicksecure.com/wiki/Dev/curl_bash_pipe](https://www.kicksecure.com/wiki/Dev/curl_bash_pipe), [dev.to/operous/how-to-build-a-trustworthy-curl-pipe-bash-workflow-4bb](https://dev.to/operous/how-to-build-a-trustworthy-curl-pipe-bash-workflow-4bb)
- **cloud-localds seed ISO** — [documentation.ubuntu.com/public-images/public-images-how-to/use-local-cloud-init-ds/](https://documentation.ubuntu.com/public-images/public-images-how-to/use-local-cloud-init-ds/)
- **QEMU + cloud-init on Ubuntu 24.04** — [stevescargall.com/blog/2024/12/a-step-by-step-guide-on-using-cloud-images-with-qemu-9-on-ubuntu-24.04/](https://stevescargall.com/blog/2024/12/a-step-by-step-guide-on-using-cloud-images-with-qemu-9-on-ubuntu-24.04/)
- **KVM on GitHub Actions (Oct 2025)** — [github.com/orgs/community/discussions/8305](https://github.com/orgs/community/discussions/8305), [actuated.com/blog/kvm-in-github-actions](https://actuated.com/blog/kvm-in-github-actions)
- **softprops/action-gh-release v2** — [github.com/softprops/action-gh-release/tree/v2](https://github.com/softprops/action-gh-release/tree/v2)
- **fpm 1.17.0** — [github.com/jordansissel/fpm](https://github.com/jordansissel/fpm)
- **GitHub Releases permalinks** — [docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases)
- **Cloud-init user-data examples** — [docs.cloud-init.io/en/latest/reference/examples.html](https://docs.cloud-init.io/en/latest/reference/examples.html)

### Example: Release notes via `gh release create --generate-notes` (fallback to `action-gh-release@v2`'s `generate_release_notes: true`)

```yaml
      - uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ needs.resolve.outputs.tag }}
          generate_release_notes: true
          files: dist/agentlinux-*.tar.gz
# equivalent CLI (manual release):
# gh release create v0.3.0 --generate-notes --verify-tag dist/agentlinux-*.tar.gz dist/agentlinux-*.tar.gz.sha256 dist/catalog-*.json
```

`generate_release_notes: true` auto-generates the body from PR titles + commit history since the previous tag. Equivalent to `gh release create --generate-notes`. No maintenance.

### Example: Ubuntu version detection

```bash
# packaging/curl-installer/install.sh helper
detect_ubuntu_version() {
  local id version
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id=${ID:-unknown}
    version=${VERSION_ID:-unknown}
  else
    die "cannot detect Ubuntu version: /etc/os-release missing"
  fi
  [[ "$id" == "ubuntu" ]] || die "unsupported distro: $id (AgentLinux v0.3.0 supports Ubuntu only)"
  case "$version" in
    22.04 | 24.04) ;;
    *) die "unsupported Ubuntu version: $version (AgentLinux v0.3.0 supports 22.04 and 24.04 only)" ;;
  esac
}
```

### Example: Version resolution with permalink + env override

```bash
# packaging/curl-installer/install.sh helper
resolve_version() {
  # User can pin via env (deterministic).
  if [[ -n "${AGENTLINUX_VERSION:-}" ]]; then
    printf '%s' "$AGENTLINUX_VERSION"
    return
  fi
  # Fallback: permalink redirect yields "latest" without burning API quota.
  # Follow redirect, extract tag from final URL (no JSON parsing needed).
  local redirect tag
  redirect=$(curl -fsSIL -o /dev/null -w '%{url_effective}' \
    "https://github.com/${ORG}/agent-linux/releases/latest/download/VERSION" \
  || die "could not resolve latest version (check connectivity)")
  tag=$(printf '%s' "$redirect" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?')
  [[ -n "$tag" ]] || die "could not parse tag from redirect URL: $redirect"
  printf '%s' "$tag"
}
```

## State of the Art

| Old Approach (pre-v0.3.0) | Current Approach (Phase 6) | Why Changed |
|---------------------------|----------------------------|-------------|
| v0.2.0 Packer → QCOW2 → OpenNebula | GitHub Releases tarball + curl-pipe-bash installer | ADR-001 pivot 2026-04-18 |
| Trust via HTTPS alone | SHA256 sidecar + HTTPS | ADR-006 INST-03 |
| GPG-signed releases | SHA256 only for v0.3.0; GPG deferred v0.4+ | ADR-006 — trade-off explicit |
| Docker-only test harness | Docker (fast PR) + QEMU (release gate) | ADR-007 — Docker misses systemd, locale, cloud-init |
| `gh release create` manual runbook | `softprops/action-gh-release@v2` auto-triggered on tag | Less maintainer toil; release is deterministic |
| Thin `npm install -g` wrapper | Pinned catalog + `catalog-v<X.Y.Z>.json` release sibling | ADR-011 stability-first |
| Per-release GPG key ceremony | None (v0.3.0) | Deferred with apt PPA to v0.4+ per ADR-006 |

**Deprecated / outdated (do NOT follow these paths):**

- `apt install agentlinux` — would require a public PPA (INF-01); explicitly deferred to v0.4+. v0.3.0 `.deb` is `dpkg -i` only.
- Installing via `pip`, `brew`, `snap` — none apply (Python not the language, Homebrew not targeted, Snap disqualified per ADR-009).
- Hosting the installer on `agentlinux.org` with dynamic version-resolution via PHP / serverless — GitHub Pages is static-only; the script uses `releases/latest/download/` redirect.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | GitHub Pages follows symlinks for served content | Pitfall 7 | If false, must duplicate install.sh file (sync at deploy time) — easy alternative |
| A2 | `softprops/action-gh-release@v2.6.2` is the correct pin (last Node-20 line) | Standard Stack | If runner upgrades drop Node 20, need v3; minor migration if so |
| A3 | `cancel-in-progress: false` is respected by GitHub Actions' scheduler | Pitfall 9 | Community thread [#53506](https://github.com/orgs/community/discussions/53506) reports edge cases; acceptable risk for tag-push workflow (rare concurrent retag) |
| A4 | Release-gate QEMU runs complete in under 30 minutes per Ubuntu version | Pattern 4 / gate-3-qemu | If KVM fails to activate (Pitfall 4), TCG fallback pushes past timeout; plan must include a fail-fast on `/dev/kvm` inaccessibility rather than silent fallback |
| A5 | `cloud-init` can install `bats` + `jq` on first boot reliably | Pattern 4 user-data | `bats` is in Ubuntu's `universe` repo; may need `package_update: true` + apt update before `packages:` — Pattern 4 does this |
| A6 | GitHub Actions runners can reach `cloud-images.ubuntu.com` without auth | Pattern 4 | Public site; should work; fallback is self-hosted mirror (not in v0.3.0 scope) |
| A7 | `fpm` install via `gem install` on Ubuntu 24.04 runner is reliable | Standard Stack + Pitfall 6 | If brittle, ADR-006 allows skipping `.deb` — plan must include a feature-flag `SKIP_DEB` and document defer-to-v0.4+ decision |
| A8 | The existing v0.1.0 `deploy.yml` can be modified to also ship `install.sh` at site root | Pitfall 7 | Low risk — existing workflow is simple; one `cp` step |

**Nothing to confirm with user:** All 8 assumptions have documented fallbacks in this research. None blocks planning.

## Open Questions

1. **Does the `.deb` ship in v0.3.0?**
   - What we know: ADR-006 says "optional." `fpm` install adds ~2min CI time + one source of fragility.
   - What's unclear: How much user demand exists for `.deb` vs. curl-pipe-bash. v0.3.0 is pre-1.0; low-demand features should defer.
   - Recommendation: Plan a `SKIP_DEB=1` env flag; ship by default; if CI fails on fpm, merge-skip by toggling the flag and file `INF-02` for v0.4+. Do not block release on `.deb`.

2. **Does `docs/STABILITY-MODEL.md` ship in v0.3.0 or v0.3.1?**
   - What we know: CONTEXT locks README's stability-model section (primary DOC-01 content); the standalone `docs/STABILITY-MODEL.md` is optional per ADR-011.
   - What's unclear: User-facing pressure for a standalone doc. ADR-011 itself is already readable.
   - Recommendation: Ship v0.3.0 with a link from README → ADR-011. Defer standalone `docs/STABILITY-MODEL.md` to v0.3.1 unless a review-loop flag surfaces it as needed.

3. **Which release.yml shape — separate jobs with `needs:` vs. matrix?**
   - What we know: CONTEXT marks this Claude's discretion. Pattern 6 in this research recommends separate jobs — the UI surfaces each gate as its own green/red badge, which matches the mental model of "4 gates + build + publish."
   - What's unclear: Whether the planner wants a matrix shape that's more compact.
   - Recommendation: Separate jobs (Pattern 6). Each gate is semantically distinct; a matrix would confuse "which gate failed?" in the Actions UI.

4. **Plan count: 4, 5, or 6?**
   - What we know: CONTEXT anticipates 4-5 plans.
   - Recommendation: 5 plans — (A) build-release.sh, (B) curl-installer + GH Pages redirect, (C) QEMU harness + nightly-qemu.yml, (D) release.yml full 4-gate pipeline, (E) README + optional stability-model doc. Optional 6th for .deb integration if ships.

## Environment Availability

| Dependency | Required By | Available on target | Version | Fallback |
|------------|------------|---------------------|---------|----------|
| `sha256sum` | curl-installer, build-release.sh | ✓ (coreutils on every Ubuntu) | 8.32+ (22.04), 9.4+ (24.04) | — |
| GNU `tar` 1.30+ | build-release.sh | ✓ | 1.34 (22.04), 1.35 (24.04) | — |
| `curl` | curl-installer | ✓ | 7.81 (22.04), 8.5 (24.04) | — |
| `jq` | CI pinned-combo gate, curl-installer version resolution (optional) | ✓ on CI; ✓ on installed AgentLinux via Phase 4 Plan 04-06 (added to Docker images) | 1.7 (24.04) | — |
| `qemu-system-x86_64` | tests/qemu/boot.sh | ✓ on GitHub hosted `ubuntu-24.04` runner | 8.2.2 | Self-hosted runner (not in v0.3.0 scope) |
| `cloud-image-utils` / `cloud-localds` | tests/qemu/boot.sh seed generation | ✓ on `ubuntu-24.04` runner | — | — |
| `/dev/kvm` | tests/qemu/boot.sh acceleration | ✓ on hosted `ubuntu-24.04` runner (Oct 2025+); requires udev rule | — | TCG fallback works but is 20-30× slower; push past 30-min timeout — treat as blocking |
| `ssh` / `scp` | tests/qemu/boot.sh | ✓ | openssh-client default | — |
| `fpm` | build-release.sh `.deb` | ✗ — not preinstalled | — | Skip `.deb` via `SKIP_DEB=1` env; ADR-006 allows |
| `bats` | tests/qemu in-guest | ✗ in Ubuntu minimal cloud image — install via cloud-init `packages:` | — | — |
| `softprops/action-gh-release@v2` | release.yml publish | ✓ (GitHub Marketplace action) | v2.6.2 | — |
| `actions/cache@v4` | release.yml QEMU gate image caching | ✓ | v4 | — |

**Missing dependencies with fallback:**
- `fpm` — skip `.deb` for v0.3.0 if install fails.
- `bats` in guest — install via cloud-init.

**No blocking missing dependencies.** All must-have tools are present on the target CI runner.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `bats-core` 1.11.x (in-guest via cloud-init `packages:`; existing CI Docker images already ship it per Phase 2 Plan 02-05) |
| Config file | No dedicated config; `tests/bats/` is the suite root per HARNESS.md §1.3 |
| Quick run command | `bats tests/bats/51-*.bats` (AGT-02 release-gate only — 1 @test, ~120s including live CDN) |
| Full suite command | `bats tests/bats/` (66 @tests per Phase 5 close; Phase 6 likely adds 0-2 @tests for INST-03 curl-pipe-bash coverage) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| INST-03 | curl-pipe-bash installer SHA256-verifies tarball before exec | integration | `bats tests/bats/10-installer.bats -f INST-03` (Phase 6 adds SHA-verify happy path + tampered-SHA error path) | ❌ Wave 0 — add `INST-03: install.sh aborts with clear error when SHA256 mismatches` + `INST-03: install.sh succeeds via curl | bash on good tarball` |
| TST-03 | QEMU release-gate runs installer + bats against fresh cloud image; Ubuntu 22.04 + 24.04 | infrastructure | `bash tests/qemu/boot.sh 22.04 && bash tests/qemu/boot.sh 24.04` | ❌ Wave 0 — `tests/qemu/boot.sh` and `tests/qemu/cloud-init/{user-data,meta-data}` |
| TST-05 | AGT-02 blocks release in both Docker + QEMU matrices | release-pipeline | In release.yml gate-2 + gate-3 (docker + qemu), bats exit non-zero if `51-*.bats` fails; `bats tests/bats/51-*.bats` selector locks the file prefix | ✓ `tests/bats/51-agt02-release-gate.bats` already exists (Phase 5 Plan 05-01) |
| TST-08 | Pinned-combo CI installs every catalog agent at pinned_version + runs bats before tag | release-pipeline | `bash tests/docker/run.sh ubuntu-24.04` (already installs pinned versions via catalog.json; needs no new bats) | ✓ Phase 4 + Phase 5 already install pinned; Phase 6 adds a dedicated job in release.yml only |
| CAT-05 | Catalog snapshot attached to GitHub Release + installer stages it | integration | `bats tests/bats/10-installer.bats -f CAT-05` — `[[ -f /opt/agentlinux/catalog/0.3.0/catalog.json ]]` + `sha256sum` matches tarball-internal + release-sibling | ❌ Wave 0 — add `CAT-05: catalog snapshot at /opt/agentlinux/catalog/<v>/` — Phase 4's `50-registry-cli.sh` already stages; Phase 6 only adds the release-sibling artifact assertion |
| DOC-01 | README shipped with install + verify + uninstall + stability | docs | `test -f README.md && grep -q '## Install' README.md && grep -q 'curl.*bash' README.md && grep -q '## Uninstall' README.md && grep -q '## Stability' README.md` | ❌ Wave 0 — README.md currently absent; plan must create |

### Sampling Rate

- **Per task commit:** `pre-commit run --all-files` (existing); if task touches `tests/qemu/boot.sh`, local `shellcheck tests/qemu/boot.sh`.
- **Per wave merge:** `./tests/docker/run.sh ubuntu-24.04` (90s; covers INST-03 bats if tests added). QEMU runs are too slow for wave merges — run once per phase at phase-close.
- **Phase gate (pre-verify-work):**
  1. `bash tests/docker/run.sh ubuntu-22.04 && bash tests/docker/run.sh ubuntu-24.04` (full bats)
  2. `bash tests/qemu/boot.sh 22.04 && bash tests/qemu/boot.sh 24.04` (full bats over SSH) — may run in CI rather than locally given KVM availability
  3. Dry-run `release.yml` via `workflow_dispatch: inputs.tag: v0.3.0-rc1` (builds artifacts to a draft; does not publish real release)
  4. `scripts/build-release.sh v0.3.0-dryrun` locally — verify tarball + sha256 + catalog snapshot assemble
  5. `sha256sum -c dist/agentlinux-*.sha256` round-trip — must exit 0

### Wave 0 Gaps

Bats files + infrastructure that must exist before Phase 6 implementation tasks begin:

- [ ] `tests/bats/10-installer.bats` — add 2-3 @tests for `INST-03` (happy-path curl-pipe + tampered-sha fail-fast). Existing file; add to it.
- [ ] `tests/bats/10-installer.bats` — add 1 @test for `CAT-05` (snapshot file exists at stage path + byte-stable against source).
- [ ] `tests/qemu/boot.sh` — full body (Phase 1 stub only; Pattern 4 skeleton is the target).
- [ ] `tests/qemu/cloud-init/user-data` + `meta-data` — templates (currently only `.gitkeep`).
- [ ] `tests/qemu/cloud-images.txt` — URL + SHA256 manifest for `jammy` + `noble` releases.
- [ ] `scripts/build-release.sh` — new file; Pattern 3 skeleton is the target.
- [ ] `packaging/curl-installer/install.sh` — Phase 1 `.gitkeep` stub → Pattern 2 body. (File is present per `tests/harness/` meta-tests; Phase 6 replaces body.)
- [ ] `README.md` — Pattern 7 skeleton. Currently absent.
- [ ] `.github/workflows/release.yml` — Phase 1 scaffold → Pattern 6 full body.
- [ ] `.github/workflows/nightly-qemu.yml` — Phase 1 empty-guard → populate with `boot.sh` matrix run.

## Security Domain

### Applicable ASVS Categories

(ASVS = OWASP Application Security Verification Standard. The release pipeline is a narrow attack surface — no persistent server, no user auth — but curl-pipe-bash is a high-trust remote-execution channel and warrants V1/V6/V14.)

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V1 Architecture | yes | Threat-model the curl-pipe-bash channel (§Threat model below); document trust boundary |
| V2 Authentication | no | No user auth — installer requires root on the user's machine; no AgentLinux service |
| V3 Session Management | no | Stateless installer |
| V4 Access Control | partial | Root check in install.sh fails fast if UID ≠ 0 |
| V5 Input Validation | yes | `AGENTLINUX_VERSION` env var validated against `^v[0-9]+\.[0-9]+\.[0-9]+$` regex before use |
| V6 Cryptography | yes | SHA-256 (not MD5, not SHA-1) for tarball integrity; HTTPS (TLS) for transport; no home-rolled crypto |
| V8 Data Protection | no | No persistent data |
| V10 Malicious Code | yes | Partial-download execution prevented by `main(){}; main` wrapper (Pitfall 1 mitigation) |
| V14 Configuration | yes | No secret handling in release.yml beyond GITHUB_TOKEN (GitHub-issued, scoped) |

### Known Threat Patterns for Release Pipeline

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| T-06-01: MITM tampers with install.sh during curl download | Tampering | HTTPS (TLS) + Certificate Transparency via GitHub's CA chain; all URLs HTTPS-only in install.sh |
| T-06-02: MITM tampers with tarball during curl download | Tampering | SHA256 sidecar verified by `sha256sum -c` BEFORE `tar xvf`; fail-fast abort on mismatch |
| T-06-03: Compromised `agentlinux.org` (GH Pages) serves malicious install.sh | Tampering | User's only defense is that `install.sh` fetches tarball from `github.com/<org>/agent-linux/releases/...` with a SHA pinned at the script level; if install.sh itself is replaced, this breaks. Full mitigation = GPG signing (ADR-006 v0.4+). Partial mitigation = repo visibility + 2FA on maintainer account (operational, not code). Documented accepted risk per ADR-006 Consequences. |
| T-06-04: Partial-download execution leaves system in inconsistent state | Tampering / Availability | `main(){}; main "$@"` wrapper (Pattern 2 / Pitfall 1) |
| T-06-05: Tampered cloud image passes through actions/cache | Tampering | Re-verify `sha256sum --check SHA256SUMS` on every cache hit (Pattern 4 step 1, Pitfall 10) |
| T-06-06: Leaked per-run SSH keypair (QEMU harness) | Information Disclosure | Keypair generated per-run via `ssh-keygen -t ed25519 -N ''`; written to `mktemp -d` with mode 0700; `trap 'rm -rf "$RUN_DIR"' EXIT` ensures cleanup. Never committed. (Pattern 4 step 2.) |
| T-06-07: Malicious PR merges a tag-pushing workflow and ships a forged release | Elevation of Privilege | `concurrency: group: release-${{ github.ref }}` + branch protection on master + required reviews before merge. Tag-push permission scoped via repo settings, not an in-CI decision. |
| T-06-08: release.yml publishes a Release missing `.sha256` sibling | Integrity | `scripts/build-release.sh` fails if `sha256sum` exits non-zero; `action-gh-release@v2` uploads all files from `dist/agentlinux-*.tar.gz.sha256` glob; manual pre-release check = `ls dist/` shows .tar.gz + .tar.gz.sha256 + catalog-*.json |
| T-06-09: GitHub API rate-limit exhaustion during mass `curl \| bash` | Availability | `install.sh` uses `releases/latest/download/` permalink (CDN, no rate limit) rather than `/releases/latest` API (60/hr). Env override `AGENTLINUX_VERSION=v0.3.0` bypasses version resolution entirely. |
| T-06-10: `.deb` postinst runs with root + could be tampered | Tampering / EoP | `.deb` signature not mitigated in v0.3.0 (no PPA signing key per ADR-006); user downloads `.deb` from GitHub Release asset — same trust model as the tarball; `dpkg -i` + SHA256 verification before `dpkg` call is the mitigation. Documented trade-off. |

## Project Constraints (from CLAUDE.md)

CLAUDE.md directives that apply to Phase 6 implementation (must not be contradicted by any plan):

- **Never `sudo npm install -g` anywhere.** Always `sudo -u agent -H npm install -g`. → `scripts/build-release.sh` must not invoke `npm install -g`; the CLI is built locally via `npm install && npm run build` in `plugin/cli/`, not globally.
- **No default agents installed.** → Release tarball ships catalog as "available"; installer does not install any agent by default. Pinned-combo CI gate is a separate test-only path; it installs agents in a CI container, not on the user's target.
- **QEMU suite must be green before any release.** → Explicit Phase 6 requirement (TST-03); release.yml gate-3 enforces.
- **Every release tarball ships with a sibling `.sha256`.** → `scripts/build-release.sh` produces it; `action-gh-release@v2` attaches it; `install.sh` verifies it.
- **No wrapper shims at `/usr/local/bin/`.** → `scripts/build-release.sh` does not produce shims; `packaging/curl-installer/install.sh` does not create them; `.deb` postinst must not either.
- **Review loop.** → Every file changed in Phase 6 runs through review-loop: bash files → `bash-engineer` + `security-engineer` + `qa-engineer`; YAML workflows → `security-engineer` + `qa-engineer`; README → `technical-writer` + `fact-checker`.

## Sources

### Primary (HIGH confidence)

- Phase 6 CONTEXT.md + ROADMAP.md + REQUIREMENTS.md — locked decisions, requirement IDs, success criteria.
- ADR-006 (curl-pipe-bash + optional .deb), ADR-007 (Docker + QEMU two-layer), ADR-011 (stability-first pinning).
- HARNESS.md §1.1 + §1.3 + §1.4 — layout, testing contract, build configuration.
- qemu-harness SKILL.md — canonical QEMU boot flow, SHA verification contract, per-run SSH keypair hygiene.
- Phase 1 scaffolds: `.github/workflows/{release,test,nightly-qemu,nightly-mutation,deploy}.yml`; `packaging/curl-installer/`, `packaging/deb/`, `tests/qemu/`.
- Phase 4 outputs: `plugin/cli/package.json` (version source), `plugin/catalog/catalog.json` (snapshot source), Phase 4 Plan 04-06 Docker builder stage (CLI bundle pattern).
- Phase 5 output: `tests/bats/51-agt02-release-gate.bats` (AGT-02 canonical test; `51-*.bats` selector contract).
- GNU tar manual §8.4 (reproducible archives): https://www.gnu.org/software/tar/manual/html_section/Reproducibility.html
- GNU coreutils sha256sum(1) manpage: https://man7.org/linux/man-pages/man1/sha256sum.1.html
- Ubuntu cloud-init docs: https://documentation.ubuntu.com/public-images/public-images-how-to/use-local-cloud-init-ds/
- Cloud-init user-data examples: https://docs.cloud-init.io/en/latest/reference/examples.html
- Ubuntu cloud images index: https://cloud-images.ubuntu.com/releases/ + SHA256SUMS paths for `jammy` and `noble`.
- GitHub Docs: Rate limits for REST API (60 req/hr unauth): https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
- GitHub Docs: Linking to releases (`/releases/latest/download/`): https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases
- reproducible-builds.org / docs / archives: https://reproducible-builds.org/docs/archives/
- `softprops/action-gh-release` v2 tree: https://github.com/softprops/action-gh-release/tree/v2

### Secondary (MEDIUM confidence)

- `sha256sum -c` format-agnostic verification: verified via man7.org manpage + tobywf.com notes; standard Linux tool.
- `curl -fsSL` idiom: verified via kicksecure.com/wiki/Dev/curl_bash_pipe + dev.to/operous/how-to-build-a-trustworthy-curl-pipe-bash-workflow-4bb; widely-replicated convention.
- GitHub Actions KVM availability on ubuntu-24.04 runners: github.com/orgs/community/discussions/8305 (October 2025 confirmation); supplemented by actuated.com/blog/kvm-in-github-actions for udev-rule workaround.
- GitHub Actions concurrency semantics (`cancel-in-progress: false`): github.com/orgs/community/discussions/53506 — known edge cases documented; acceptable for tag-push workflows.
- fpm 1.17.0 on Ubuntu 24.04: github.com/jordansissel/fpm (latest release Oct 2025) + fpm.readthedocs.io/en/latest/installation.html (403 during fetch; community-replicated install recipe).

### Tertiary (LOW confidence — flagged for validation during Plan phase)

- GitHub Pages symlink following (Assumption A1) — should be verified before relying on a symlinked `install.sh`; alternative is deploy-time `cp`.
- fpm `gem install` reliability on fresh ubuntu-24.04 runner (Assumption A7) — first CI run will validate.

## Metadata

**Confidence breakdown:**
- Standard stack (tar, sha256sum, curl, qemu, cloud-localds): HIGH — every tool verified on Ubuntu 22.04/24.04 + documented on man pages or upstream docs
- Architecture (4-gate release.yml, release tarball layout): HIGH — Pattern 6 composes verified building blocks
- Pitfalls (10 listed, cross-linked to sources): HIGH — each pitfall has an upstream citation or community report
- fpm specifics (Ubuntu 24.04 compatibility, postinst hooks): MEDIUM — ADR-006 allows deferring `.deb` if fragile
- KVM availability on hosted runners: HIGH (as of Oct 2025); MEDIUM as a first-run-in-CI for this repo (Assumption A4 + Pitfall 4 detection step in release.yml)
- GitHub Pages symlink serving: LOW — Assumption A1, documented fallback

**Research date:** 2026-04-20
**Valid until:** 2026-05-20 (stable stack; QEMU/KVM on Actions is a moving target — re-verify if Phase 6 execution slips past May)
