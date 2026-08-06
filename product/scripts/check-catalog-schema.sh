#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# product/scripts/check-catalog-schema.sh — commit-time structural gate for the catalog.
#
# Replaces the pre-cutover `node plugin/cli/scripts/validate-catalog.mjs` (ajv)
# hook, deleted with the TypeScript CLI.
#
# WHAT ACTUALLY GUARDS THE CATALOG, so the layering is not misread:
#   1. This hook — fast, jq-only, commit-time. Confirms catalog.json parses and
#      that the required fields are present. Catches a structurally-broken entry
#      before it is committed.
#   2. `cargo test -p agentlinux catalog::catalog_tests::shipped_catalog_satisfies_its_schema`
#      — loads the REAL catalog.json through the Rust types and asserts the
#      constraints serde cannot express (source_kind enum, semver pin, npm
#      requires npm_package_name, https endpoint_url). This is the strongest gate.
#   3. `cargo test -p agentlinux-core schema` — regenerates schema.json from the
#      Rust types and fails on drift. It compares BYTES ONLY; it never opens
#      catalog.json, so it is not catalog validation.
#
# No JSON-Schema validator runs in this repo. The required-field list below is
# therefore a deliberate, small duplication of schema.json's `required` — kept
# because it is what makes this hook fast enough for pre-commit. Gate (2) is the
# one that must be kept in step with the schema.

set -euo pipefail

# Resolved from this script's own location, not the caller's CWD: pre-commit
# invokes it from the repo root while the tree it checks lives under product/.
product_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CAT_JSON="${product_root}/plugin/catalog/catalog.json"

command -v jq >/dev/null 2>&1 || {
  printf 'check-catalog-schema: jq is required on PATH but not found\n' >&2
  exit 1
}
[[ -r "$CAT_JSON" ]] || {
  printf 'check-catalog-schema: %s missing or unreadable\n' "$CAT_JSON" >&2
  exit 1
}

# jq -e exits non-zero if the program's last value is false/null — so this both
# parses the JSON (a parse error is a non-zero exit + diagnostic) and asserts the
# structural contract. The required-field lists mirror plugin/catalog/schema.json.
if ! err=$(jq -e '
  # Top-level required (schema.json root "required").
  if (has("version") and has("agents") | not)
  then error("top-level must have .version and .agents") else . end
  | if (.agents | type != "array") then error(".agents must be an array") else . end
  # Collect all violations into one array, then error once if non-empty.
  | ( [ .agents | to_entries[]
        | .key as $i | .value as $a
        | ( ["id","display_name","description","source_kind",
             "pinned_version","install_recipe_path","uninstall_recipe_path"]
            | map(select($a[.] == null)) ) as $missing
        | select($missing | length > 0)
        | "agents[\($i)] (id=\($a.id // "?")) missing required: \($missing | join(", "))" ]
    ) as $missingErrs
  # npm entries additionally require npm_package_name (schema.json allOf/if-then).
  | ( [ .agents | to_entries[]
        | .key as $i | .value as $a
        | select($a.source_kind == "npm" and ($a.npm_package_name == null))
        | "agents[\($i)] (id=\($a.id // "?")) source_kind=npm requires npm_package_name" ]
    ) as $npmErrs
  | ($missingErrs + $npmErrs) as $errs
  | if ($errs | length) > 0 then error($errs | join("; ")) else true end
' "$CAT_JSON" 2>&1 >/dev/null); then
  printf 'check-catalog-schema: %s failed structural validation:\n  %s\n' "$CAT_JSON" "$err" >&2
  printf '(Deeper field checks run in `cargo test -p agentlinux catalog::catalog_tests::shipped_catalog_satisfies_its_schema`.\n No JSON-Schema validator runs anywhere in this repo — see schema_gen.rs.)\n' >&2
  exit 1
fi

exit 0
