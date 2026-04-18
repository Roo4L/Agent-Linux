#!/usr/bin/env bash
# tests/harness/run.sh
# Runs the Phase 1 harness acceptance suite.
# Exit 0 iff every HRN-XX, TST-06, TST-07 artifact required by ROADMAP.md §Phase 1 is present.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT"

# --- Locate bats ---------------------------------------------------------------
# Prefer (in order):
#   1. system-installed bats on PATH (CI installs via apt / brew / npm -g)
#   2. locally-installed node_modules/.bin/bats (npm install --no-save bats)
#   3. vendored bats-core at tests/bats/bin/bats
BATS_BIN=""
if command -v bats >/dev/null 2>&1; then
  BATS_BIN="$(command -v bats)"
elif [[ -x "$REPO_ROOT/node_modules/.bin/bats" ]]; then
  BATS_BIN="$REPO_ROOT/node_modules/.bin/bats"
elif [[ -x "$REPO_ROOT/tests/bats/bin/bats" ]]; then
  BATS_BIN="$REPO_ROOT/tests/bats/bin/bats"
fi

if [[ -z "$BATS_BIN" ]]; then
  cat <<'EOF' >&2
tests/harness/run.sh: bats is not installed.

Install bats-core by one of:
  Ubuntu:       sudo apt install bats
  macOS:        brew install bats-core
  npm (local):  npm install --no-save bats    # → node_modules/.bin/bats
  npm (global): npm install -g bats
  Docker:       docker run --rm -v "$PWD":/code -w /code bats/bats:latest tests/harness/
  Vendored:     clone https://github.com/bats-core/bats-core into tests/bats/

See tests/harness/README.md for details.
EOF
  exit 127
fi

echo "== harness: bats suite (via $BATS_BIN) =="
# Enumerate .bats files with nullglob so an empty directory fails loudly
# instead of passing the literal "tests/harness/*.bats" string to bats.
shopt -s nullglob
bats_files=("$HERE"/*.bats)
shopt -u nullglob
if [[ ${#bats_files[@]} -eq 0 ]]; then
  echo "tests/harness/run.sh: no .bats files found in $HERE" >&2
  exit 2
fi
set +e
"$BATS_BIN" "${bats_files[@]}"
BATS_STATUS=$?
set -e

echo
echo "== harness: pre-commit smoke (optional) =="
if command -v pre-commit >/dev/null 2>&1; then
  # pre-commit must run green on the Phase 1 deliverable. If this fails, Phase 1 is not done.
  pre-commit run --all-files --show-diff-on-failure
  echo "pre-commit: OK"
else
  echo "pre-commit not installed on PATH; skipping smoke. CI installs it in test.yml." >&2
fi

exit "$BATS_STATUS"
