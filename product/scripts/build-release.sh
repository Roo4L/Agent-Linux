#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# product/scripts/build-release.sh — Assemble AgentLinux release artifacts.
#   Phase 6 Plan 01 (origin); Phase 58 (DIST-01/02) swapped the payload from the
#   pnpm TS bundle to the static x86_64-musl `agentlinux` bin and removed the
#   optional fpm .deb channel — the reproducible tarball + `.sha256` is now the
#   SOLE distribution channel.
#
# Produces (under dist/ at repo root):
#   agentlinux-v<X.Y.Z>.tar.gz        — reproducible tarball, payload plugin/bin/agentlinux
#                                       (the static musl bin) + plugin/catalog/ (the per-agent
#                                       Bash recipes), SOURCE_DATE_EPOCH-pinned.
#   agentlinux-v<X.Y.Z>.tar.gz.sha256 — GNU sha256sum sidecar; round-trips via `sha256sum -c`.
#   catalog-v<X.Y.Z>.json             — byte-for-byte copy of plugin/catalog/catalog.json (CAT-05).
#   VERSION                           — the tag sentinel the installer's latest-resolution reads.
#
# Usage:
#   product/scripts/build-release.sh v0.3.0                   # full build
#   product/scripts/build-release.sh v0.3.0 --dry-run         # validate + plan only
#   SOURCE_DATE_EPOCH=123456 product/scripts/build-release.sh v0.3.0  # pin epoch (CI override)
#
# Referenced by:
#   CLAUDE.md §Commands (build-release.sh vX.Y.Z)
#   .github/workflows/release.yml (invokes this in the build step)
#   packaging/curl-installer/install.sh (consumes the sha256 sidecar over HTTPS)
#
# Design references:
#   06-RESEARCH.md §Pattern 3 (reproducible tar recipe)
#   06-RESEARCH.md §Pitfall 5 (reproducibility — SOURCE_DATE_EPOCH + --sort=name)
#   06-RESEARCH.md §Pitfall 8 (byte-for-byte catalog snapshot, not `jq .`)
#   58-RESEARCH.md §Pattern 1 (reproducible static-bin tarball), §Pitfall 3 (three-way
#     version lock now spans package.json / catalog.json / Cargo.toml), §Pitfall 6
#     (build-host-path / build-id non-determinism in the compiled bin)
#   docs/decisions/006-curl-pipe-bash-plus-deb.md (ADR-006 — channel (1) survives; (2)
#     the optional .deb is superseded by Phase 58 DIST-02)
#   docs/decisions/011-stability-first-version-pinning.md (ADR-011 — bundle pattern)
#   reproducible-builds.org/docs/archives/ (tar flag recipe)
#
# Invariants (T-06-01 / T-06-08 / T-06-08b / T-06-V / T-58-01 / T-58-03 mitigations):
#   - TAG arg is re-validated here, regardless of who invoked us — release.yml passes it
#     through from GITHUB_REF and we MUST NOT trust that surface. Bad tag → exit 64.
#   - Two-way version lock: TAG vs plugin/catalog/catalog.json.version vs
#     rust/crates/agentlinux/Cargo.toml.version.
#     A drift anywhere fails the build loudly — prevents shipping a tag whose pinned
#     versions (incl. the shipped musl bin's CARGO_PKG_VERSION) diverge.
#   - Tarball is reproducible: two back-to-back runs on the same HEAD produce byte-identical
#     gzip. The musl bin is made reproducible via `[profile.release] strip = true` +
#     `--build-id=none` + `--remap-path-prefix` (RUSTFLAGS exported below) so no build-host
#     path or build-id leaks non-determinism (Pitfall 6).
#   - Catalog snapshot is `cp`, not `jq .` — sha256(source) == sha256(sibling).
#   - Single channel: the reproducible musl tarball + `.sha256`. No fpm/.deb (DIST-02).
#
# NOT done here (by design):
#   - No `sudo` anywhere (CLAUDE.md hard rule — this script runs as a normal user).
#   - No `npm install` / `pnpm` (DIST-01: the shipped path has no Node prerequisite;
#     the TS CLI it replaced was deleted at the Phase-59 Rust cutover).
#   - No GPG signing (ADR-006 defers signed releases; SHA256 + HTTPS is the trust story).

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Argument parsing + tag shape validation (T-06-V mitigation).
# ---------------------------------------------------------------------------
usage() {
  cat >&2 <<'EOF'
usage: product/scripts/build-release.sh v<X.Y.Z>[-suffix] [--dry-run]

Builds the release artifact set under dist/ (reproducible musl tarball — the SOLE channel):
  agentlinux-v<X.Y.Z>.tar.gz         (payload: plugin/bin/agentlinux musl bin + plugin/catalog/)
  agentlinux-v<X.Y.Z>.tar.gz.sha256
  catalog-v<X.Y.Z>.json
  VERSION

Flags:
  --dry-run                  validate arg + version lock + print planned artifact
                             set to stdout; write nothing under dist/ and run no
                             musl build. Exit 0 on validation pass, 64/1 on
                             arg/version errors (same codes as a real build).

Environment:
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
#   --dry-run — run validation + planning only; do NOT invoke cargo, tar, sha256,
#               or write to dist/. Exit 0 once the plan is printed. This lets CI
#               `workflow_dispatch` smoke-test the version-consistency gate
#               without paying the musl-build cost or producing artifacts that
#               would be mistaken for a real release.
DRY_RUN_FLAG=0
while (($#)); do
  case "$1" in
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
# Stays REPO-root-anchored, not product/-anchored like the sibling gate scripts:
# dist/ is a repo-root build output, so every path below is written relative to
# the repo root and product-tree reads carry an explicit product/ prefix.
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# 3. Two-way version-consistency gate (T-06-V / T-58-03 mitigation).
#    TAG must match plugin/catalog/catalog.json .version AND
#    rust/crates/agentlinux/Cargo.toml [package] version. A mismatch either side
#    means the tag being built does not correspond to the code/config shipped
#    inside the tarball — the lock is what prevents that. The Cargo.toml leg is
#    load-bearing: the shipped payload is the musl bin, whose CARGO_PKG_VERSION
#    comes from Cargo.toml. (Pre-cutover this was a three-way lock that also
#    checked plugin/cli/package.json; the TS CLI was deleted at the Rust cutover,
#    so catalog.json is now the sole JSON version SoT.)
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required on PATH but not found\n' >&2
  exit 1
fi

CAT_V=$(jq -r .version product/plugin/catalog/catalog.json)
# Cargo.toml has no jq-parseable shape; read the first `version = "X.Y.Z"` line
# under [package] (the [[bin]]/[dependencies] tables use `version =` too, so
# anchor on the [package] block being first in the file — Cargo requires it).
CARGO_TOML="product/rust/crates/agentlinux/Cargo.toml"
CARGO_V=$(sed -n 's/^version = "\([^"]*\)".*/\1/p' "$CARGO_TOML" | head -1)

# Pre-release tags (e.g. v0.3.0-rc1) ship the SAME code as the eventual
# v0.3.0 — catalog.json + Cargo.toml track the base semver, not the rc suffix.
# Strip the suffix from $VERSION before comparing.
BASE_VERSION=${VERSION%%-*}

if [[ "$CAT_V" != "$BASE_VERSION" ]]; then
  printf 'version mismatch: product/plugin/catalog/catalog.json .version=%s ≠ tag=%s (base=%s)\n' \
    "$CAT_V" "$TAG" "$BASE_VERSION" >&2
  exit 1
fi
# Cargo.toml version parity — the shipped musl bin's CARGO_PKG_VERSION must match
# the tag (DIST-01/Pitfall 3). A divergence would ship a bin whose --version
# disagrees with the tarball's staged version paths.
if [[ "$CARGO_V" != "$BASE_VERSION" ]]; then
  printf 'version mismatch: %s [package] version=%s ≠ tag=%s (base=%s)\n' \
    "$CARGO_TOML" "$CARGO_V" "$TAG" "$BASE_VERSION" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3b. --dry-run short-circuit (06-VALIDATION.md row 06-01-01).
#     Print the planned artifact set to stdout and exit 0 without running the
#     musl build or writing to dist/. Tag-shape + version-lock gates above still
#     run — that is the point of the dry-run: surface version drift at
#     `workflow_dispatch` smoke-test time, before a real tag push pays the full
#     musl-build cost.
# ---------------------------------------------------------------------------
if ((DRY_RUN_FLAG == 1)); then
  cat <<EOF
dry-run: would build for tag=${TAG} version=${VERSION}
  product/plugin/catalog/catalog.json .version=${CAT_V} (matches)
  ${CARGO_TOML} version=${CARGO_V} (matches)
planned artifacts under dist/:
  dist/agentlinux-${TAG}.tar.gz   (payload: plugin/bin/agentlinux musl bin + plugin/catalog/)
  dist/agentlinux-${TAG}.tar.gz.sha256
  dist/catalog-${TAG}.json
  dist/VERSION
dry-run: no files written, no musl build invoked
EOF
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Build the static x86_64-musl `agentlinux` bin (DIST-01 — replaces the
#    pnpm TS-bundle build). This bin IS the shipped `plugin/bin/agentlinux`;
#    the installer execs it and the provisioner stages it (Wave 2). No pnpm/npm
#    anywhere on the producer path — that is the DIST-01 "no Node prerequisite"
#    win. The TS CLI this replaced was deleted at the Phase-59 cutover.
#
#    Reproducibility (Pitfall 6 / T-58-01): a bare `cargo build --release` embeds
#    the absolute build-host path (in panic/debug metadata) and an ELF build-id,
#    both of which vary across build hosts / $PWD and would break the tarball's
#    byte-identical `.sha256` invariant. We defuse both:
#      - `[profile.release] strip = true` (rust/Cargo.toml) drops debuginfo.
#      - `--remap-path-prefix=$PWD=.` rewrites the source path to a stable `.`.
#      - `--remap-path-prefix=$CARGO_HOME=/cargo` (and $HOME) neutralizes the
#        registry-dependency paths baked into any residual metadata.
#      - `-C link-arg=-Wl,--build-id=none` zeroes the ELF build-id note.
#    These travel with the RELEASE build only (exported RUSTFLAGS here), so
#    `cargo test`/`clippy` on the dev target are unaffected.
#
#    Build discipline: ALWAYS build (cargo incremental makes an unchanged rebuild
#    near-free and correctly refreshes a stale bin) — mirrors tests/docker/run.sh
#    host_build_musl; no stale-bin early-return.
# ---------------------------------------------------------------------------
if ! command -v cargo >/dev/null 2>&1; then
  # shellcheck disable=SC1091  # optional shim, path checked
  if [[ -f "$HOME/.cargo/env" ]]; then
    . "$HOME/.cargo/env"
  fi
fi
if ! command -v cargo >/dev/null 2>&1; then
  printf 'cargo is required on PATH (or via ~/.cargo/env) but not found\n' >&2
  exit 1
fi

MUSL_TARGET="x86_64-unknown-linux-musl"
MUSL_BIN="product/rust/target/${MUSL_TARGET}/release/agentlinux"
CARGO_HOME_DIR="${CARGO_HOME:-$HOME/.cargo}"

# Reproducible RUSTFLAGS — remap every build-host path prefix to a stable token
# and strip the ELF build-id. --remap-path-prefix is applied left-to-right, so
# the most-specific ($PWD/product/rust) mapping is listed before the broader
# $HOME one. Keep this in step with the crate location: a stale prefix here does
# not break determinism (both mappings are host-invariant) but it silently stops
# an older tag from rebuilding byte-identically.
REPRO_RUSTFLAGS="--remap-path-prefix=${REPO_ROOT}/product/rust=. --remap-path-prefix=${REPO_ROOT}=. --remap-path-prefix=${CARGO_HOME_DIR}=/cargo --remap-path-prefix=${HOME}=/home -C link-arg=-Wl,--build-id=none"

(
  cd product/rust
  # Prepend our reproducibility flags to any inherited RUSTFLAGS.
  RUSTFLAGS="${REPRO_RUSTFLAGS}${RUSTFLAGS:+ ${RUSTFLAGS}}" \
    cargo build --release --target "$MUSL_TARGET" -p agentlinux
)

if [[ ! -f "$MUSL_BIN" ]]; then
  printf 'musl build produced no binary at %s — aborting\n' "$MUSL_BIN" >&2
  exit 1
fi
# Static-link assertion (RUST-01 carried forward): a musl bin must have no
# dynamic dependencies and no runtime interpreter — it must run before any libc
# or ld.so exists (the pre-Node install environment). Note musl links a
# STATIC-PIE by default: that has an ELF dynamic *section* (self-relocation
# entries) but ZERO NEEDED libs and NO PT_INTERP segment. So the correct static
# test is "no NEEDED libs AND no INTERP", NOT "no dynamic section" and NOT the
# `ldd` exit code (glibc's ldd prints "statically linked" and exits 0 for a
# static bin — the naive `if ldd` check false-positives here). Prefer readelf;
# fall back to `file` if readelf is unavailable.
if command -v readelf >/dev/null 2>&1; then
  NEEDED_COUNT=$(readelf -d "$MUSL_BIN" 2>/dev/null | grep -c 'NEEDED' || true)
  INTERP_COUNT=$(readelf -l "$MUSL_BIN" 2>/dev/null | grep -c 'INTERP' || true)
  if [[ "$NEEDED_COUNT" -ne 0 || "$INTERP_COUNT" -ne 0 ]]; then
    printf 'musl bin %s is not fully static (NEEDED=%s INTERP=%s) — aborting\n' \
      "$MUSL_BIN" "$NEEDED_COUNT" "$INTERP_COUNT" >&2
    readelf -d "$MUSL_BIN" 2>&1 | grep NEEDED >&2 || true
    exit 1
  fi
elif command -v file >/dev/null 2>&1; then
  if ! file "$MUSL_BIN" | grep -q 'statically\|static-pie'; then
    printf 'musl bin %s does not report as statically linked — aborting\n' "$MUSL_BIN" >&2
    file "$MUSL_BIN" >&2 || true
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 5. Prepare dist/ output directory + the tarball staging tree.
#    The payload keeps the `plugin/` prefix (Open Q1): the musl bin is staged at
#    plugin/bin/agentlinux (the path install.sh execs + registry_cli.rs stages),
#    and the catalog + the ~25 Bash recipes are copied verbatim from plugin/
#    catalog/. Nothing else is staged. The staging dir is a clean, reproducible
#    payload root the tar recipe archives, so no repo build-output (e.g.
#    rust/target/) can leak into the tarball.
# ---------------------------------------------------------------------------
mkdir -p dist

STAGE_DIR=$(mktemp -d)
trap 'rm -rf "$STAGE_DIR"' EXIT

# plugin/bin/agentlinux — the static musl bin (0755).
install -Dm0755 "$MUSL_BIN" "$STAGE_DIR/plugin/bin/agentlinux"
# plugin/catalog/ — catalog.json + schema.json + the ~25 Bash recipes, verbatim.
mkdir -p "$STAGE_DIR/plugin/catalog"
cp -R product/plugin/catalog/. "$STAGE_DIR/plugin/catalog/"

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
#    Payload root is the STAGING tree ($STAGE_DIR), not the repo plugin/: the
#    staging tree holds only the musl bin (plugin/bin/agentlinux) + plugin/
#    catalog/, so no repo build-output (e.g. plugin/cli/dist, node_modules) can
#    leak in. `-C "$STAGE_DIR"` makes the archived paths repo-relative (`plugin/
#    ...`) — identical to the pre-Phase-58 layout — with no $STAGE_DIR prefix.
#    The pnpm-bookkeeping --exclude lines are gone: the TS bundle no longer ships.
# ---------------------------------------------------------------------------
TARBALL="dist/agentlinux-${TAG}.tar.gz"
tar \
  --sort=name \
  --owner=0 --group=0 --numeric-owner \
  --mtime="@${SOURCE_DATE_EPOCH}" \
  --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
  --create --file=- \
  -C "$STAGE_DIR" \
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
cp product/plugin/catalog/catalog.json "$CATALOG_SNAPSHOT"

# ---------------------------------------------------------------------------
# 10. VERSION sentinel asset.
#      packaging/curl-installer/install.sh resolves an unpinned tag by
#      following https://github.com/.../releases/latest/download/VERSION and
#      capturing the redirect URL with curl -fsSIL. The asset itself doesn't
#      need to be machine-parsed — but it MUST exist so curl -f doesn't fail
#      on the redirect target. Without this file shipped on every release,
#      `curl -fsSL https://agentlinux.org/install.sh | bash` fails with
#      "could not resolve latest version" against any release that lacks the
#      sentinel (dogfood-discovered against v0.3.2-rc1).
# ---------------------------------------------------------------------------
printf '%s\n' "$TAG" >dist/VERSION

# ---------------------------------------------------------------------------
# 11. Final summary (stdout-only; no emojis per CLAUDE.md).
#     The reproducible musl tarball + .sha256 is the SOLE distribution channel
#     (Phase 58 DIST-02 removed the optional fpm .deb path).
# ---------------------------------------------------------------------------
printf 'Built: %s + .sha256 + catalog-%s.json + VERSION\n' "$TARBALL" "$TAG"
