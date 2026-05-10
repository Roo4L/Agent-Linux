#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/check-version-lockstep.sh — AL-25 pre-commit guardrail.
#
# Asserts that plugin/cli/package.json::version (the canonical SoT under
# AL-29) matches plugin/catalog/catalog.json::version. The two files must
# agree because scripts/build-release.sh enforces a three-way version lock at
# release time (TAG vs package.json vs catalog.json) — any drift between
# package.json and catalog.json on master would block the next release.
#
# This hook shifts that gate from release-time to commit-time: a mismatch
# fails pre-commit with a precise diagnostic, so contributors cannot land a
# divergent pair into master and only discover it during the release run.
#
# Why these two files only:
#   - Plugin source (plugin/bin/agentlinux-install, plugin/cli/src/*) reads
#     package.json dynamically at install time / module load via the AL-29
#     SoT migration; nothing left to drift in source code.
#   - Bats tests read package.json via jq for the same reason.
#   - catalog.json is a JSON document that ships in the release tarball as a
#     sibling artifact (CAT-05), and its `version` field is consumed
#     independently by `agentlinux upgrade` for staleness detection. It can
#     legitimately drift from package.json if a contributor edits one and
#     forgets the other — exactly the failure mode this hook prevents.
#
# Refs:
#   - .planning/quick/260503-dtx-.../260503-dtx-SUMMARY.md (AL-29 narrative)
#   - scripts/build-release.sh §three-way-lock (release-time gate)
#   - AL-25 (this hook), AL-29 (the SoT consolidation it backstops)

set -euo pipefail

PKG_JSON=plugin/cli/package.json
CAT_JSON=plugin/catalog/catalog.json

if [[ ! -r "$PKG_JSON" ]]; then
  printf 'check-version-lockstep: %s missing or unreadable\n' "$PKG_JSON" >&2
  exit 1
fi
if [[ ! -r "$CAT_JSON" ]]; then
  printf 'check-version-lockstep: %s missing or unreadable\n' "$CAT_JSON" >&2
  exit 1
fi

# Coreutils-only extraction so this hook does not require jq on contributor
# laptops. Format is fixed (we control both files); the regex is a strict
# parse of the conventional `"version": "X.Y.Z[-suffix]"` shape and rejects
# anything outside it loudly.
extract_version() {
  local file=$1
  sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' "$file" \
    | head -n 1
}

PKG_V=$(extract_version "$PKG_JSON")
CAT_V=$(extract_version "$CAT_JSON")

readonly VERSION_REGEX='^[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.-]+)?$'
if [[ ! "$PKG_V" =~ $VERSION_REGEX ]]; then
  printf 'check-version-lockstep: bad or missing version in %s: %q (expected match for %s)\n' \
    "$PKG_JSON" "$PKG_V" "$VERSION_REGEX" >&2
  exit 1
fi
if [[ ! "$CAT_V" =~ $VERSION_REGEX ]]; then
  printf 'check-version-lockstep: bad or missing version in %s: %q (expected match for %s)\n' \
    "$CAT_JSON" "$CAT_V" "$VERSION_REGEX" >&2
  exit 1
fi

if [[ "$PKG_V" != "$CAT_V" ]]; then
  cat >&2 <<EOF
check-version-lockstep: version drift between SoT and catalog
  plugin/cli/package.json    -> ${PKG_V}
  plugin/catalog/catalog.json -> ${CAT_V}

Both files MUST carry the same version string. Bump them together.
The build-release.sh three-way version lock would have caught this
at release time; this pre-commit hook shifts that gate to commit
time so the drift never reaches master.
EOF
  exit 1
fi

# All-clear. No stdout per pre-commit convention (silent on success).
exit 0
