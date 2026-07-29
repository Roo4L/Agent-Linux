#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/check-catalog-schema.sh — commit-time structural gate for the catalog.
#
# Replaces the pre-cutover `node plugin/cli/scripts/validate-catalog.mjs` (ajv)
# hook, which was deleted with the TypeScript CLI. The AUTHORITATIVE catalog
# validation is now the Rust schemars drift-check (`cargo test -p agentlinux-core
# schema`, TEST-03) — it regenerates plugin/catalog/schema.json from the Rust
# types and fails on drift. That runs in CI (the rust job).
#
# This hook is the fast, jq-only commit-time backstop: it confirms catalog.json
# parses and every required field named in schema.json's `required` lists is
# present, so a contributor cannot land a structurally-broken entry that would
# only fail later in the Rust suite. It intentionally does NOT re-implement full
# JSON-Schema validation (types, enums, conditionals) — that is the Rust suite's
# job and duplicating it in jq would drift.

set -euo pipefail

CAT_JSON=plugin/catalog/catalog.json

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
  printf '(Full JSON-Schema validation runs in `cargo test -p agentlinux-core schema`.)\n' >&2
  exit 1
fi

exit 0
