#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/check-version-lockstep.sh — AL-25 pre-commit guardrail.
#
# Asserts that plugin/catalog/catalog.json::version matches the
# rust/crates/agentlinux/Cargo.toml [package] version. The two must agree
# because scripts/build-release.sh enforces a two-way version lock at release
# time (TAG vs catalog.json vs Cargo.toml) — any drift between them on master
# would block the next release.
#
# This hook shifts that gate from release-time to commit-time: a mismatch
# fails pre-commit with a precise diagnostic, so contributors cannot land a
# divergent pair into master and only discover it during the release run.
#
# Why these two files:
#   - catalog.json ships in the release tarball as a sibling artifact (CAT-05),
#     and its `version` field is consumed by `agentlinux upgrade` for staleness
#     detection and drives the /opt/agentlinux/<ver>/ staging paths.
#   - Cargo.toml [package] version becomes the shipped musl bin's
#     CARGO_PKG_VERSION (the CLI-01 `agentlinux --version` string and the
#     runtime catalog-dir resolver). A drift would ship a bin whose --version
#     disagrees with the staged catalog.
#   (Pre-cutover this locked plugin/cli/package.json against catalog.json; the TS
#   CLI was deleted at the Rust cutover, so Cargo.toml is now the other leg.)
#
# Refs:
#   - scripts/build-release.sh §two-way-lock (release-time gate)
#   - AL-25 (this hook), AL-29 (the SoT consolidation it backstops)

set -euo pipefail

# Resolved from this script's own location, not the caller's CWD: pre-commit
# invokes it from the repo root while the tree it checks lives under product/.
product_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CAT_JSON="${product_root}/plugin/catalog/catalog.json"
CARGO_TOML="${product_root}/rust/crates/agentlinux/Cargo.toml"

if [[ ! -r "$CAT_JSON" ]]; then
  printf 'check-version-lockstep: %s missing or unreadable\n' "$CAT_JSON" >&2
  exit 1
fi
if [[ ! -r "$CARGO_TOML" ]]; then
  printf 'check-version-lockstep: %s missing or unreadable\n' "$CARGO_TOML" >&2
  exit 1
fi

# Coreutils-only extraction so this hook does not require jq on contributor
# laptops. Both formats are fixed (we control both files).
CAT_V=$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' "$CAT_JSON" | head -n 1)
# Cargo.toml: the first `version = "X.Y.Z"` — the [package] block is first in the
# file (Cargo requires it), so the [[bin]]/[dependencies] `version =` lines that
# follow never shadow it under `head -n 1`.
CARGO_V=$(sed -nE 's/^version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$CARGO_TOML" | head -n 1)

readonly VERSION_REGEX='^[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.-]+)?$'
if [[ ! "$CAT_V" =~ $VERSION_REGEX ]]; then
  printf 'check-version-lockstep: bad or missing version in %s: %q (expected match for %s)\n' \
    "$CAT_JSON" "$CAT_V" "$VERSION_REGEX" >&2
  exit 1
fi
if [[ ! "$CARGO_V" =~ $VERSION_REGEX ]]; then
  printf 'check-version-lockstep: bad or missing version in %s: %q (expected match for %s)\n' \
    "$CARGO_TOML" "$CARGO_V" "$VERSION_REGEX" >&2
  exit 1
fi

if [[ "$CAT_V" != "$CARGO_V" ]]; then
  cat >&2 <<EOF
check-version-lockstep: version drift between catalog and Cargo.toml
  plugin/catalog/catalog.json      -> ${CAT_V}
  rust/crates/agentlinux/Cargo.toml -> ${CARGO_V}

Both files MUST carry the same version string. Bump them together.
The build-release.sh two-way version lock would have caught this at release
time; this pre-commit hook shifts that gate to commit time so the drift never
reaches master.
EOF
  exit 1
fi

# All-clear. No stdout per pre-commit convention (silent on success).
exit 0
