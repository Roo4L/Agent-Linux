//! TEST-03: `plugin/catalog/schema.json` generated from Rust types (single SoT).
//!
//! The lean [`crate::types::CatalogEntry`] deliberately mirrors only the five
//! fields the classify/divergence core reads (`types.rs`); the full ~15-field
//! catalog schema covers more fields than the core's lean type. Deriving `JsonSchema` on that lean type
//! would emit a broken 5-field schema the ajv validator rejects the real
//! catalog against. So this module carries a
//! **codegen-only** [`SchemaCatalogEntry`] that mirrors the FULL catalog schema
//! — every field, the constraint set, the `source_kind` enum, and the
//! npm-requires `if/then` conditional — without touching the core types.
//!
//! [`schema_json`] is pure (no I/O); only the `#[cfg(test)]` drift-check touches
//! the filesystem, so the crate's I/O-free ban (`lib.rs`) only bends inside the
//! test module. Regenerate the committed schema with:
//! `UPDATE_SCHEMA=1 cargo test -p agentlinux-core schema` after changing a type.

use schemars::JsonSchema;
use serde::Serialize;

// The four dispatchable install sources (schema `source_kind` enum). Modelled
// as a Rust enum so schemars emits the `enum` keyword; `#[schemars(inline)]` on
// the enum inlines it into `source_kind` to match the hand-written schema's
// inline enum (rather than a `$ref` to a `$defs/SourceKind`). Plain `//`
// comments (not `///`) so this note does NOT leak into the schema `description`.
// Variants are never constructed (we only source their schema via JsonSchema),
// so silence the dead-code lint the whole codegen struct triggers.
#[derive(JsonSchema, Serialize)]
#[serde(rename_all = "snake_case")]
#[schemars(inline)]
#[allow(dead_code)]
enum SourceKind {
    Npm,
    Script,
    Binary,
    Mcp,
}

// Codegen-only mirror of `plugin/catalog/schema.json` `$defs/agent` — carries
// ALL catalog fields with their `pattern`/`minLength`/`format` constraints so
// the generated schema still rejects malformed entries (the negative
// `schema.test.ts` fixtures). Renamed to `agent` so the `$defs` member name
// matches the hand-written schema. The npm-requires `if/then` conditional
// (which schemars cannot derive from field types) is re-added via `extend`.
// Plain `//` comments (not `///`) keep this note out of the schema `description`.
//
// This is NOT the type the core reads — it exists purely to source the schema;
// its fields are never read at runtime, hence `#[allow(dead_code)]`.
#[derive(JsonSchema, Serialize)]
#[allow(dead_code)]
#[serde(rename = "agent", deny_unknown_fields)]
#[schemars(extend("allOf" = [
    {
        "if": { "properties": { "source_kind": { "const": "npm" } }, "required": ["source_kind"] },
        "then": { "required": ["npm_package_name"] }
    }
]))]
struct SchemaCatalogEntry {
    #[schemars(regex(pattern = r"^[a-z][a-z0-9-]*$"))]
    id: String,
    #[schemars(length(min = 1))]
    display_name: String,
    #[schemars(length(min = 1))]
    description: String,
    #[schemars(extend("format" = "uri"))]
    homepage: Option<String>,
    license: Option<String>,
    source_kind: SourceKind,
    #[schemars(regex(pattern = r"^(@[a-z0-9-]+/)?[a-z0-9][a-z0-9_-]*$"))]
    npm_package_name: Option<String>,
    requires_secret: Option<bool>,
    #[schemars(regex(pattern = r"^[A-Z][A-Z0-9_]*$"))]
    secret_env: Option<String>,
    #[schemars(extend("format" = "uri"), regex(pattern = r"^https://"))]
    endpoint_url: Option<String>,
    #[schemars(regex(pattern = r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"))]
    pinned_version: String,
    version_constraint: Option<String>,
    #[schemars(length(min = 1))]
    compatibility_window: Option<String>,
    #[schemars(regex(pattern = r"^[a-z0-9_./-]+\.sh$"))]
    install_recipe_path: String,
    #[schemars(regex(pattern = r"^[a-z0-9_./-]+\.sh$"))]
    uninstall_recipe_path: String,
    #[schemars(regex(pattern = r"^[a-z0-9_./-]+\.sh$"))]
    rewire_recipe_path: Option<String>,
    post_install_verify: Option<String>,
    #[schemars(regex(pattern = r"^[a-z0-9_./-]+\.json$"))]
    preserve_paths_file: Option<String>,
    tags: Option<Vec<String>>,
    test_only: Option<bool>,
}

// Codegen-only mirror of the catalog root — `version` + `agents[]`, with the
// hand-written schema's `$id`, `title`, and `description` re-added via `extend`
// (schemars derives none of them from a bare struct), plus a `$comment` marking
// the file generated so a contributor regenerates rather than hand-edits it.
#[derive(JsonSchema, Serialize)]
#[allow(dead_code)]
#[serde(rename = "AgentLinux Catalog", deny_unknown_fields)]
#[schemars(extend(
    "$id" = "https://agentlinux.org/schemas/catalog.json",
    "$comment" = "GENERATED from rust/crates/agentlinux-core/src/schema_gen.rs (TEST-03). Do not hand-edit — regenerate with `UPDATE_SCHEMA=1 cargo test -p agentlinux-core schema` and commit.",
    "title" = "AgentLinux Catalog",
    "description" = "Catalog of available agents. Each entry is opt-in (CAT-02). Stability-first pinning (ADR-011): every entry carries a required pinned_version."
))]
struct Catalog {
    version: String,
    agents: Vec<SchemaCatalogEntry>,
}

/// The catalog JSON Schema, generated from the Rust types — the single source of
/// truth (TEST-03). Pretty-printed with a trailing newline. Pure: no I/O.
pub fn schema_json() -> String {
    let schema = schemars::schema_for!(Catalog);
    let mut out = serde_json::to_string_pretty(&schema)
        .expect("schema serializes to JSON (schemars output is always valid)");
    out.push('\n');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    // CARGO_MANIFEST_DIR is rust/crates/agentlinux-core; the committed schema is
    // three levels up under plugin/catalog/.
    const SCHEMA_PATH: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../plugin/catalog/schema.json"
    );

    // SCOPE: this asserts byte-equality of committed vs generated schema, and
    // nothing more. It does NOT check that the schema rejects a malformed entry,
    // and it does NOT check that the shipped catalog.json satisfies it.
    //
    // The negative-case coverage that used to back this up lived in an ajv suite
    // (`plugin/cli/test/schema.test.ts`) deleted with the TypeScript CLI. It has
    // no successor: no JSON-Schema validator runs anywhere in this repo. What
    // guards the live catalog today is `catalog::load_catalog` in the bin crate —
    // it deserializes catalog.json into the same field set this schema is
    // generated from, and `catalog::catalog_tests::shipped_catalog_satisfies_its_schema`
    // runs it against the real file, plus the field-level invariants this schema
    // encodes. Restoring true schema validation means adding a
    // validator dependency; until then, do not read this test as one.
    #[test]
    fn schema_is_not_drifted() {
        // NOTE: this test reads and (under UPDATE_SCHEMA) WRITES the filesystem
        // from `agentlinux-core`, whose lib doc forbids `std::fs`/`std::env`. The
        // purity rule is about the crate's PRODUCTION surface — a drift check has
        // to compare against the committed file, so it necessarily does I/O. It
        // stays behind `#[cfg(test)]` and must not grow a non-test caller.
        let generated = schema_json();
        // Emit mode (contributor): write the generated schema to the committed
        // path, then STILL assert. Returning early made a test that mutates the
        // source tree and self-neuters on an ambient env var — a stray
        // UPDATE_SCHEMA in a shell would rewrite the repo and report green.
        if std::env::var("UPDATE_SCHEMA").is_ok() {
            std::fs::write(SCHEMA_PATH, &generated)
                .expect("write generated schema.json to plugin/catalog/");
        }
        let committed = std::fs::read_to_string(SCHEMA_PATH)
            .expect("read committed plugin/catalog/schema.json");
        assert_eq!(
            committed, generated,
            "plugin/catalog/schema.json drifted from the Rust catalog types — \
             regenerate it with `UPDATE_SCHEMA=1 cargo test -p agentlinux-core schema` and commit the result"
        );
    }

    /// The constraints a malformed entry must trip. Byte-equality alone cannot
    /// see these move: a `#[derive(JsonSchema)]` change that drops a `required`
    /// field or widens `source_kind` from an enum to a free string produces a
    /// drift failure, which the documented fix (`UPDATE_SCHEMA=1`) then makes
    /// green — with the schema now accepting entries it used to reject.
    #[test]
    fn constraints_that_reject_a_malformed_entry_survive() {
        let schema: serde_json::Value =
            serde_json::from_str(&schema_json()).expect("generated schema is valid JSON");

        // Reach the entry definition wherever schemars puts it (inline under
        // properties.agents.items, or behind a $defs reference).
        let text = schema.to_string();

        // Required fields — an entry missing any of these must not validate.
        for field in [
            "id",
            "pinned_version",
            "install_recipe_path",
            "uninstall_recipe_path",
        ] {
            assert!(
                text.contains(&format!("\"{field}\"")),
                "the schema no longer mentions the required field {field}"
            );
        }

        // source_kind stays a CLOSED set — widening it to a free string is the
        // change that would let an unknown installer kind into the catalog.
        let source_kind_enum = find_enum(&schema, "source_kind")
            .expect("source_kind must still be a closed enum, not a free string");
        for kind in ["npm", "script", "binary", "mcp"] {
            assert!(
                source_kind_enum.iter().any(|v| v == kind),
                "source_kind enum lost {kind}: {source_kind_enum:?}"
            );
        }
    }

    /// Find the `enum` variant list for a named property anywhere in the schema.
    fn find_enum(node: &serde_json::Value, property: &str) -> Option<Vec<String>> {
        match node {
            serde_json::Value::Object(map) => {
                if let Some(prop) = map.get(property) {
                    if let Some(values) = prop.get("enum").and_then(|e| e.as_array()) {
                        return Some(
                            values
                                .iter()
                                .filter_map(|v| v.as_str().map(str::to_string))
                                .collect(),
                        );
                    }
                }
                map.values().find_map(|v| find_enum(v, property))
            }
            serde_json::Value::Array(items) => items.iter().find_map(|v| find_enum(v, property)),
            _ => None,
        }
    }
}
