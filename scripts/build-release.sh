#!/usr/bin/env bash
# scripts/build-release.sh — Phase 6 Plan 01. Assemble AgentLinux release artifacts.
#
# Produces (under dist/ at repo root):
#   agentlinux-v<X.Y.Z>.tar.gz        — plugin/ only, reproducible (SOURCE_DATE_EPOCH-pinned).
#   agentlinux-v<X.Y.Z>.tar.gz.sha256 — GNU sha256sum sidecar; round-trips via `sha256sum -c`.
#   catalog-v<X.Y.Z>.json             — byte-for-byte copy of plugin/catalog/catalog.json (CAT-05).
#   agentlinux_<X.Y.Z>_all.deb        — OPTIONAL; produced only if fpm is on PATH and SKIP_DEB!=1.
#
# Usage:
#   scripts/build-release.sh v0.3.0                   # full build
#   SKIP_DEB=1 scripts/build-release.sh v0.3.0        # force-skip .deb even if fpm present
#   scripts/build-release.sh v0.3.0 --no-deb          # same, flag form
#   SOURCE_DATE_EPOCH=123456 scripts/build-release.sh v0.3.0  # pin epoch (CI override)
#
# Referenced by:
#   CLAUDE.md §Commands (build-release.sh vX.Y.Z)
#   .github/workflows/release.yml (Plan 06-04 — invokes this in the build step)
#   packaging/curl-installer/install.sh (Plan 06-02 — consumes the sha256 sidecar over HTTPS)
#
# Design references:
#   06-RESEARCH.md §Pattern 3 (reproducible tar recipe)
#   06-RESEARCH.md §Pitfall 5 (reproducibility — SOURCE_DATE_EPOCH + --sort=name)
#   06-RESEARCH.md §Pitfall 6 (optional fpm — do not hard-fail)
#   06-RESEARCH.md §Pitfall 8 (byte-for-byte catalog snapshot, not `jq .`)
#   docs/decisions/006-curl-pipe-bash-plus-deb.md (ADR-006 — .deb optional)
#   docs/decisions/011-stability-first-version-pinning.md (ADR-011 — bundle pattern)
#   reproducible-builds.org/docs/archives/ (tar flag recipe)
#
# Invariants (T-06-01 / T-06-08 / T-06-08b / T-06-V mitigations):
#   - TAG arg is re-validated here, regardless of who invoked us — release.yml passes it
#     through from GITHUB_REF and we MUST NOT trust that surface. Bad tag → exit 64.
#   - Three-way version lock: TAG vs plugin/cli/package.json.version vs plugin/catalog/catalog.json.version.
#     A drift anywhere fails the build loudly — prevents shipping a tag whose pinned versions diverge.
#   - Tarball is reproducible: two back-to-back runs on the same HEAD produce byte-identical gzip.
#   - Catalog snapshot is `cp`, not `jq .` — sha256(source) == sha256(sibling).
#   - fpm is OPTIONAL: a missing fpm or SKIP_DEB=1 prints a notice and continues; the curl-pipe-bash
#     channel (tarball + sha256) is the authoritative v0.3.0 path.
#
# NOT done here (by design):
#   - No `sudo` anywhere (CLAUDE.md hard rule — this script runs as a normal user).
#   - No `npm install -g` (CLAUDE.md hard rule). We `npm install --no-audit --no-fund` inside plugin/cli/ only.
#   - No GPG signing (ADR-006 defers signed releases to v0.4+; SHA256 + HTTPS is the v0.3.0 trust story).

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Argument parsing + tag shape validation (T-06-V mitigation).
# ---------------------------------------------------------------------------
usage() {
  cat >&2 <<'EOF'
usage: scripts/build-release.sh v<X.Y.Z>[-suffix] [--no-deb] [--dry-run]

Builds the v0.3.0+ release artifact set under dist/:
  agentlinux-v<X.Y.Z>.tar.gz
  agentlinux-v<X.Y.Z>.tar.gz.sha256
  catalog-v<X.Y.Z>.json
  agentlinux_<X.Y.Z>_all.deb         (optional; skipped if fpm absent or SKIP_DEB=1 or --no-deb)

Flags:
  --no-deb                   skip .deb even if fpm is on PATH
  --dry-run                  validate arg + version lock + print planned artifact
                             set to stdout; write nothing under dist/ and run no
                             CLI build. Exit 0 on validation pass, 64/1 on
                             arg/version errors (same codes as a real build).

Environment:
  SKIP_DEB=1                 skip .deb even if fpm is on PATH
  SOURCE_DATE_EPOCH=<epoch>  pin tar mtime (default: commit author-date of HEAD)
EOF
}

TAG=${1:-}
if [[ -z "$TAG" ]]; then
  usage
  exit 64
fi
shift

# Parse remaining flags.
#   --no-deb  — skip .deb build even if fpm present.
#   --dry-run — run validation + planning only; do NOT invoke pnpm, tar, sha256,
#               fpm, or write to dist/. Exit 0 once the plan is printed. This
#               lets CI `workflow_dispatch` smoke-test the version-consistency
#               gate without paying the ~30s CLI-build cost or producing
#               artifacts that would be mistaken for a real release.
NO_DEB_FLAG=0
DRY_RUN_FLAG=0
while (($#)); do
  case "$1" in
    --no-deb) NO_DEB_FLAG=1 ;;
    --dry-run) DRY_RUN_FLAG=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown flag: %s\n' "$1" >&2
      usage
      exit 64
      ;;
  esac
  shift
done

# Semver-with-optional-suffix regex. Refuses `0.3.0` (missing v), `v0.3` (no patch),
# `v0.3.0+build` (build metadata not supported; use -suffix for pre-release).
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
  printf 'tag %s does not match vX.Y.Z[-suffix]\n' "$TAG" >&2
  exit 64
fi
VERSION=${TAG#v}

# ---------------------------------------------------------------------------
# 2. Resolve repo root (this script is invocable from any cwd).
# ---------------------------------------------------------------------------
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# 3. Three-way version-consistency gate (T-06-V mitigation).
#    TAG must match both plugin/cli/package.json .version and
#    plugin/catalog/catalog.json .version. A mismatch anywhere means the
#    tag being built does not correspond to the code/config shipped inside
#    the tarball — the three-way lock is what prevents that.
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required on PATH but not found\n' >&2
  exit 1
fi

CLI_V=$(jq -r .version plugin/cli/package.json)
CAT_V=$(jq -r .version plugin/catalog/catalog.json)

if [[ "$CLI_V" != "$VERSION" ]]; then
  printf 'version mismatch: plugin/cli/package.json .version=%s ≠ tag=%s (%s)\n' \
    "$CLI_V" "$VERSION" "$TAG" >&2
  exit 1
fi
if [[ "$CAT_V" != "$VERSION" ]]; then
  printf 'version mismatch: plugin/catalog/catalog.json .version=%s ≠ tag=%s (%s)\n' \
    "$CAT_V" "$VERSION" "$TAG" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3b. --dry-run short-circuit (06-VALIDATION.md row 06-01-01).
#     Print the planned artifact set to stdout and exit 0 without running the
#     CLI build, writing to dist/, or invoking fpm. Tag-shape + version-lock
#     gates above still run — that is the point of the dry-run: surface
#     version drift at `workflow_dispatch` smoke-test time, before a real
#     tag push pays the full ~30s build cost.
# ---------------------------------------------------------------------------
if ((DRY_RUN_FLAG == 1)); then
  DRY_DEB_LINE="  dist/agentlinux_${VERSION}_all.deb      (optional; fpm + SKIP_DEB=0 + --no-deb absent)"
  if [[ "${SKIP_DEB:-}" == "1" ]] || ((NO_DEB_FLAG == 1)) || ! command -v fpm >/dev/null 2>&1; then
    DRY_DEB_LINE="  (.deb skipped: fpm absent or SKIP_DEB=1 or --no-deb)"
  fi
  cat <<EOF
dry-run: would build for tag=${TAG} version=${VERSION}
  plugin/cli/package.json  .version=${CLI_V} (matches)
  plugin/catalog/catalog.json .version=${CAT_V} (matches)
planned artifacts under dist/:
  dist/agentlinux-${TAG}.tar.gz
  dist/agentlinux-${TAG}.tar.gz.sha256
  dist/catalog-${TAG}.json
${DRY_DEB_LINE}
dry-run: no files written, no CLI build invoked
EOF
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Build the CLI (ADR-011 bundle pattern) via pnpm with the checked-in
#    lockfile. The tarball ships plugin/cli/dist/ (tsc output) +
#    plugin/cli/node_modules/ (production deps). Installer's 50-registry-cli.sh
#    asserts both are present and fails the install if malformed — this build
#    step is the producer.
#
#    Rationale for pnpm --frozen-lockfile (not `npm install`):
#      - plugin/cli/ ships a pnpm-lock.yaml (lockfileVersion 9.0); there is no
#        package-lock.json. `npm install` ignores pnpm's lockfile, drifts deps,
#        and — worse — can execute upstream packages' postinstall hooks that
#        scatter template files into plugin/cli/ (observed: @npmcli/template-oss
#        overwrites package.json + drops CODE_OF_CONDUCT.md, SECURITY.md,
#        .commitlintrc.cjs, .github/, etc. into the working tree).
#      - The Docker cli-builder stage (tests/docker/Dockerfile.ubuntu-24.04
#        §Stage 1) already uses `pnpm install --frozen-lockfile && pnpm run
#        build && pnpm prune --prod`. This script mirrors that contract so
#        the release tarball and Docker test image ship byte-equivalent
#        node_modules trees.
#      - pnpm's --frozen-lockfile refuses to update the lockfile; any drift
#        fails the build loudly (Pitfall-adjacent: silent dep drift at release
#        time is the exact class of bug reproducibility aims to prevent).
#
#    pnpm resolution: prefer corepack (bundled with node 22+), fall back to a
#    direct `pnpm` on PATH. Either yields pnpm@latest-in-range; the lockfile
#    determines resolved versions, so the PM version only needs to honor the
#    lockfile format (v9 — pnpm >=9).
# ---------------------------------------------------------------------------
(
  cd plugin/cli
  if command -v corepack >/dev/null 2>&1; then
    corepack enable >/dev/null 2>&1 || true
    corepack prepare pnpm@latest --activate >/dev/null 2>&1 || true
    PNPM_CMD="pnpm"
  elif command -v pnpm >/dev/null 2>&1; then
    PNPM_CMD="pnpm"
  else
    printf 'pnpm is required on PATH (or via corepack) but not found\n' >&2
    exit 1
  fi
  "$PNPM_CMD" install --frozen-lockfile
  "$PNPM_CMD" run build
  # Prune devDeps AFTER build so tsc (devDep) is available during build, then
  # the shipped node_modules/ contains runtime deps only. Mirrors Docker
  # cli-builder stage's `pnpm prune --prod`.
  "$PNPM_CMD" prune --prod
)

# ---------------------------------------------------------------------------
# 5. Prepare dist/ output directory.
# ---------------------------------------------------------------------------
mkdir -p dist

# ---------------------------------------------------------------------------
# 6. Pin SOURCE_DATE_EPOCH (T-06-01 mitigation — reproducibility).
#    Defaulting to `git log -1 --pretty=%ct HEAD` means every re-run on the
#    same HEAD pins tar mtimes to the same second. Override via env for CI
#    workflow_dispatch dry-runs (e.g. pin to a release tag's ctime explicitly).
# ---------------------------------------------------------------------------
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git log -1 --pretty=%ct HEAD)}
export SOURCE_DATE_EPOCH

# ---------------------------------------------------------------------------
# 7. Reproducible tarball (reproducible-builds.org canonical recipe).
#
#    Flag rationale:
#      --sort=name          : deterministic file order (default is FS-order, which varies).
#      --owner=0 --group=0  : erase the builder's uid/gid from the archive.
#      --numeric-owner      : do NOT embed /etc/passwd lookups; preserves the 0/0 above.
#      --mtime=@$epoch      : pin all entries to SOURCE_DATE_EPOCH (default: HEAD ctime).
#      --pax-option=...     : strip atime/ctime from pax extended headers (they
#                             embed filesystem-specific nanosecond jitter).
#
#    Then we pipe through `gzip -n` explicitly: GNU tar's `--gzip` can embed
#    a timestamp in the gzip header depending on the gzip version. `-n` forces
#    "no original filename, no timestamp" and gives a byte-identical gzip frame
#    across runs. (This is the subtle reproducibility bug Phase 6 Research §Pitfall 5
#    calls out; using --gzip alone tripped a real reproducible-builds.org test suite.)
#
#    Excluded files (pnpm-internal metadata — not needed at runtime, contains
#    wall-clock timestamps that break reproducibility across re-runs):
#      - plugin/cli/node_modules/.modules.yaml — pnpm's "prunedAt" timestamp.
#      - plugin/cli/node_modules/.pnpm-workspace-state-v1.json — pnpm's
#        "lastValidatedTimestamp". Node's ESM resolver does NOT read either
#        file; they are pnpm bookkeeping for subsequent `pnpm install` calls.
#        Stripping them is both a reproducibility fix (Pitfall 5) AND a
#        tarball-hygiene improvement (smaller surface, no dev-tool state in
#        the shipped artifact).
# ---------------------------------------------------------------------------
TARBALL="dist/agentlinux-${TAG}.tar.gz"
tar \
  --sort=name \
  --owner=0 --group=0 --numeric-owner \
  --mtime="@${SOURCE_DATE_EPOCH}" \
  --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
  --exclude='plugin/cli/node_modules/.modules.yaml' \
  --exclude='plugin/cli/node_modules/.pnpm-workspace-state-v1.json' \
  --create --file=- \
  plugin/ \
  | gzip -n >"$TARBALL"

# ---------------------------------------------------------------------------
# 8. SHA256 sidecar (T-06-08 mitigation).
#    GNU sha256sum default format: "<hex>  <filename>". Readable back via
#    `sha256sum -c`. We `cd dist` so the sidecar's filename column is the
#    tarball's basename (not the relative path), which is what the
#    curl-installer's verification step expects.
# ---------------------------------------------------------------------------
(
  cd dist
  sha256sum "agentlinux-${TAG}.tar.gz" >"agentlinux-${TAG}.tar.gz.sha256"
)

# ---------------------------------------------------------------------------
# 9. Catalog snapshot (CAT-05, T-06-08b mitigation).
#    `cp`, NOT `jq .` — preserves byte-for-byte formatting and whitespace
#    (Pitfall 8). A drift between the release-sibling catalog-<tag>.json and
#    the staged /opt/agentlinux/catalog/<ver>/catalog.json would make
#    `agentlinux upgrade` read divergent data. Task 3's CAT-05 @test enforces
#    this at install time.
# ---------------------------------------------------------------------------
CATALOG_SNAPSHOT="dist/catalog-${TAG}.json"
cp plugin/catalog/catalog.json "$CATALOG_SNAPSHOT"

# ---------------------------------------------------------------------------
# 10. Self-verify the catalog snapshot is byte-identical to the source.
#     Belt-and-braces: even though `cp` is byte-copy by contract, verifying
#     the invariant at build time means a broken cp (e.g. a rogue alias that
#     smuggled `cp` to do line-ending conversion) fails the build instead of
#     shipping silently-corrupted bytes.
# ---------------------------------------------------------------------------
SRC_SHA=$(sha256sum plugin/catalog/catalog.json | awk '{print $1}')
SNAPSHOT_SHA=$(sha256sum "$CATALOG_SNAPSHOT" | awk '{print $1}')
if [[ "$SRC_SHA" != "$SNAPSHOT_SHA" ]]; then
  printf 'CAT-05 byte-stability FAILED: source=%s snapshot=%s\n' \
    "$SRC_SHA" "$SNAPSHOT_SHA" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 11. Optional .deb via fpm (ADR-006 — optional v0.3.0 path).
#     Skip gracefully if fpm is absent or SKIP_DEB=1 or --no-deb — the
#     tarball + sha256 + catalog snapshot are the authoritative outputs.
# ---------------------------------------------------------------------------
DEB_SUFFIX=""
if [[ "${SKIP_DEB:-}" == "1" ]] || ((NO_DEB_FLAG == 1)); then
  printf 'skipping .deb (SKIP_DEB=1 or --no-deb)\n'
elif ! command -v fpm >/dev/null 2>&1; then
  printf 'skipping .deb (fpm not installed; install via `gem install fpm` to enable)\n'
else
  DEB="dist/agentlinux_${VERSION}_all.deb"
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
    --package "$DEB" \
    .
  DEB_SUFFIX=" + ${DEB##*/}"
fi

# ---------------------------------------------------------------------------
# 12. Final summary (stdout-only; no emojis per CLAUDE.md).
# ---------------------------------------------------------------------------
printf 'Built: %s + .sha256 + catalog-%s.json%s\n' "$TARBALL" "$TAG" "$DEB_SUFFIX"
