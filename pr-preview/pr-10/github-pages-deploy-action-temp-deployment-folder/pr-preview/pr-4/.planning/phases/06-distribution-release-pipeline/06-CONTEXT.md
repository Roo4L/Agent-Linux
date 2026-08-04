# Phase 6: Distribution + Release Pipeline - Context

**Gathered:** 2026-04-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Ship v0.3.0. A user on a fresh Ubuntu 22.04 or 24.04 cloud image runs ONE command and gets a working AgentLinux environment. A tagged release publishes a SHA256-verified tarball + catalog snapshot + optional .deb to GitHub Releases. The release pipeline enforces four blocking gates: Docker matrix, QEMU matrix, AGT-02 canonical acceptance test, and TST-08 pinned-combo CI. A user-facing README documents install/verify/uninstall and AgentLinux's stability model (ADR-011).

Requirements in scope: INST-03 (SHA256 curl-pipe-bash), TST-03 (QEMU matrix), TST-05 (AGT-02 release gate), TST-08 (pinned-combo release gate), CAT-05 (catalog snapshot artifact), DOC-01 (user README).

Out of scope: Public PPA / apt repository (INF-01, v0.4+); multi-arch support (v0.4+); auto-update daemon (INF-04, v0.4+); `.deb` distribution as first-class path (INF-02, v0.4+).

</domain>

<decisions>
## Implementation Decisions

### Release Artifact Layout
- **Tarball:** `agentlinux-v<X.Y.Z>.tar.gz` containing the `plugin/` directory only (bin + lib + provisioner + cli/dist + cli/node_modules + catalog). Excludes `tests/`, `docs/`, `.planning/`, `.github/`, `website/`, `packer/`.
- **Sibling artifacts:** `agentlinux-v<X.Y.Z>.tar.gz.sha256` (per INST-03) + `catalog-v<X.Y.Z>.json` (per CAT-05, byte-for-byte from `plugin/catalog/catalog.json` at release time).
- **Optional .deb:** built via `fpm` per ADR-006 — fpm wraps the tarball into a Debian package that extracts plugin/ and runs `agentlinux-install`. Ship when feasible; skip if fpm integration proves brittle in CI (documented as v0.4+ if deferred).
- **Build script:** `scripts/build-release.sh v<X.Y.Z>` (already referenced in CLAUDE.md — create it) — assembles tarball, computes SHA256, copies catalog.json → catalog snapshot, optionally fpm-builds .deb. Called by `release.yml` on v* tag push.
- **Version source-of-truth:** `plugin/cli/package.json` `version` field. `scripts/build-release.sh` verifies the arg matches `package.json`. Release tag must match too.

### curl-pipe-bash Installer (INST-03)
- **Download location:** GitHub Releases — `https://github.com/<org>/agent-linux/releases/download/v<X.Y.Z>/agentlinux-v<X.Y.Z>.tar.gz` + sibling `.sha256`. Stable permalinks.
- **Entry script:** `packaging/curl-installer/install.sh` (already scaffolded in Phase 1 per HARNESS.md §1.1 — replace stub). Does:
  1. Root check; fail-fast if not root with clear error.
  2. Detect Ubuntu version + fail if unsupported.
  3. Resolve version: `AGENTLINUX_VERSION=v0.3.0` env OR fetch latest from GitHub releases API.
  4. Download tarball + `.sha256` to a tmp dir via `curl -fsSL`.
  5. Verify: `sha256sum -c agentlinux-v<X.Y.Z>.tar.gz.sha256` — fail-fast on mismatch with clear message ("downloaded tarball failed SHA256 check; retrying or aborting — possibly a corrupted download or a tampered host").
  6. Extract tarball to `/opt/agentlinux/install/<X.Y.Z>/`.
  7. `exec /opt/agentlinux/install/<X.Y.Z>/plugin/bin/agentlinux-install "$@"` — passes through any flags (`--verbose`, `--purge`).
- **Short URL:** `https://agentlinux.org/install.sh` redirects (via the existing v0.1.0 website) to the canonical GitHub Releases location. Documented in README as the canonical command.
- **Invocation:** `curl -fsSL https://agentlinux.org/install.sh | sudo bash` OR `sudo bash -c "$(curl -fsSL https://agentlinux.org/install.sh)"` (prefer the piped form for simplicity; README shows both).

### CI Release Pipeline (TST-03, TST-05, TST-08)
- **Trigger:** push of a `v*` tag to `.github/workflows/release.yml`. Also triggerable manually via `workflow_dispatch` for dry-runs.
- **Pipeline gates (in order; each blocks on failure):**
  1. **Pre-commit + Node unit tests** — existing test.yml logic reused (`bats`-docker excluded, handled below).
  2. **Docker matrix (existing test.yml)** — full `./tests/docker/run.sh ubuntu-{22,24}.04` on both Ubuntu versions. Expected 66/66.
  3. **QEMU matrix (TST-03 — NEW):** cloud-image VMs for Ubuntu 22.04 + 24.04. `tests/qemu/boot.sh` (scaffold from Phase 1) fleshed out. Cloud-init seed ISO configures user + installs base tools. SSH into the guest; run installer; run bats suite. Both must exit 0.
  4. **AGT-02 release-gate (TST-05):** `bats tests/bats/51-*.bats` runs inside BOTH the Docker matrix AND the QEMU matrix. Non-zero exit blocks the release. AGT-02 is the canonical v0.3.0 acceptance test.
  5. **Pinned-combo CI (TST-08 — NEW):** after Docker matrix and QEMU matrix green, release.yml runs a dedicated "pinned combo" job — installs every catalog agent at its `pinned_version`, runs `tests/bats/50-agents.bats` + `51-*.bats`, asserts all green. Non-zero blocks the release. Runs inside Ubuntu 24.04 Docker (the pinned dev environment).
  6. **Build artifacts:** only after all gates above green, `scripts/build-release.sh v<X.Y.Z>` builds the tarball + sha256 + catalog snapshot + optional .deb.
  7. **Publish to GitHub Release:** attach artifacts to the tag; set release notes from commit log since previous tag.
- **QEMU image caching:** pre-built cached images in GitHub Actions to bound CI time. Fresh cloud image on first run per Ubuntu version; subsequent runs restore cache + update apt.

### User-Facing README (DOC-01)
- **Location:** root `README.md`. v0.1.0 landing-page content (if any substantive prose survives in current README) preserved as an "About" section; new install/verify/uninstall sections take primary real estate.
- **Sections (ordered):**
  1. One-paragraph pitch: "AgentLinux provisions an agent user with correctly-owned runtime so agent tools self-update without EACCES or sudo fights. Curated stable versions with explicit override via `agentlinux pin`."
  2. **Install:** one-command `curl -fsSL https://agentlinux.org/install.sh | sudo bash` example.
  3. **Verify:** `agentlinux list` shows three available agents; `agentlinux install claude-code` installs one; `claude --version` confirms.
  4. **Uninstall:** `sudo agentlinux-install --purge` (or `--purge --remove-nodejs` for full cleanup).
  5. **Stability model:** one-paragraph summary of ADR-011 — "we ship curated combos, you can jump ahead with `claude update` / `npm install -g @latest`, then reconcile with `agentlinux upgrade` / `agentlinux pin`."
  6. **Escape hatch:** `agentlinux pin <name>=latest` example.
  7. **Requirements:** Ubuntu 22.04 / 24.04.
  8. **Links:** docs/decisions/ ADRs, GitHub Releases, issue tracker.
- **Version stamp:** the README contains `<!-- VERSION: v0.3.0 -->` markers auto-updated by `scripts/build-release.sh` at release time.
- **`docs/STABILITY-MODEL.md`** (optional per ADR-011 §What to Do Next): one-page user-facing explanation of the curated-combo model + divergence flow + `pin`/`upgrade` commands. Nice-to-have; planner decides whether to ship in v0.3.0 or defer to v0.3.1.

### Claude's Discretion
- Exact URL for `https://agentlinux.org/install.sh` redirect (existing v0.1.0 website infra may need a new redirect rule).
- Whether `.deb` ships in v0.3.0 (ADR-006 says "optional"; if fpm integration is fiddly, defer to v0.4+).
- Exact cloud-init seed contents for QEMU — minimum workable config.
- Whether `release.yml` uses a matrix job or separate jobs per gate.
- README version-stamp marker shape.
- Whether `docs/STABILITY-MODEL.md` ships in v0.3.0 or is deferred.
- Number of plans: research-recommended breakdown comes next; likely 4-5 plans (build-release script, curl-installer, QEMU harness, CI release workflow, README + stability-model).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.github/workflows/test.yml` — Docker matrix on PR (Phase 1 scaffold + Phase 4 populated; 66/66 green).
- `.github/workflows/nightly-qemu.yml` — Phase 1 empty-guard scaffold. Phase 6 populates its matrix or folds into release.yml.
- `.github/workflows/release.yml` — Phase 1 scaffold with empty-plugin guard. Phase 6 flesh out.
- `packaging/curl-installer/install.sh` — Phase 1 stub. Phase 6 replaces body.
- `packaging/deb/` — Phase 1 empty dir for fpm. Phase 6 populates if .deb ships.
- `tests/qemu/boot.sh` + `tests/qemu/cloud-init/` — Phase 1 scaffolding. Phase 6 implements.
- `tests/bats/51-agt02-release-gate.bats` — Phase 5 canonical AGT-02 test. Phase 6 invokes it in release.yml.
- `tests/bats/50-agents.bats` — Phase 5 pinned-combo coverage. Phase 6 invokes in TST-08 gate.
- `plugin/cli/package.json` — version source of truth.
- `plugin/catalog/catalog.json` — copied to `catalog-v0.3.0.json` at release time (CAT-05).

### Established Patterns
- Per-task atomic commits.
- Every bats @test cites its req ID (now in release.yml, bats runs inside the matrix).
- Review loop: bash-engineer + security-engineer for curl-installer + build-release.sh + qemu harness; qa-engineer on any new bats; catalog-auditor on release artifact composition; technical-writer + fact-checker on README.
- Each plan's `<threat_model>` cites T-06-XX IDs.

### Integration Points
- `scripts/build-release.sh` called by release.yml → consumed by curl-installer.
- QEMU cloud images: pre-built in a release-prep step, cached via `actions/cache`.
- AGT-02 release-gate: same bats file runs in Docker matrix AND QEMU matrix; `release.yml` selects via `bats tests/bats/51-*.bats`.
- CAT-05 catalog snapshot: release.yml copies `plugin/catalog/catalog.json` to `catalog-v<X.Y.Z>.json` sibling; curl-installer stages it to `/opt/agentlinux/catalog/<X.Y.Z>/` at install time; `agentlinux upgrade` reads it.
- README badge: GitHub Actions status badge for release.yml on root README.md.

</code_context>

<specifics>
## Specific Ideas

- **INST-03 SHA256 is non-negotiable.** Releases without matching sha256 are blocked by curl-installer; treat this as a hard gate.
- **QEMU + Docker both green for AGT-02** is the release signal — if either fails, tag is not published. Two separate runtime environments catch different classes of regression (systemd in Docker is fake; in QEMU it's real).
- **ADR-006 `.deb` is OPTIONAL.** Don't let fpm integration block v0.3.0 — ship it if easy, defer to v0.4+ if painful.
- **Release notes** from `git log v<previous-tag>..v<current-tag>` auto-appended to the GitHub release; user can edit after tagging.
- **Release-script idempotency:** re-running `scripts/build-release.sh v0.3.0` on the same commit produces byte-identical tarball + sha256 (important for reproducibility testing).
- **Window on v0.1.0 website:** the existing agentlinux.org landing page (Phase 0 v0.1.0 work) needs a redirect added for `/install.sh` → GitHub Releases latest. Small task.
- **Pinned-combo gate timing** — install claude-code + gsd + playwright + run full bats suite is ~8-10 minutes per image (network-bound). Acceptable for release.yml; skip for PR test.yml (only run on tag).

</specifics>

<deferred>
## Deferred Ideas

- **Public apt PPA (INF-01)** — v0.4+. v0.3.0 distributes via curl-pipe-bash + GitHub Releases.
- **Auto-update daemon (INF-04)** — v0.4+. User explicitly invokes `agentlinux upgrade`.
- **Multi-arch (ARM)** — v0.4+. x86_64 only.
- **GPG-signed releases** — v0.4+. SHA256 verification + HTTPS is the v0.3.0 trust story.
- **`agentlinux self-update` (INF-03)** to fetch newer installer and re-run — v0.4+. Current workflow: user re-runs the curl-installer for newer versions.
- **Reproducible builds** (bit-for-bit deterministic) — nice but not a v0.3.0 gate.
- **Full browser matrix for Playwright (firefox + webkit)** — v0.4+.

</deferred>
