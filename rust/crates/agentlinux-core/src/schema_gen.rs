//! TEST-03: `plugin/catalog/schema.json` generated from Rust types (single SoT).
//!
//! The lean [`crate::types::CatalogEntry`] deliberately mirrors only the five
//! fields the classify/divergence core reads (`types.rs`); the full ~15-field
//! catalog schema is Phase-55 scope. Deriving `JsonSchema` on that lean type
//! would emit a broken 5-field schema the ajv validator rejects the real
//! catalog against (RESEARCH Pitfall 3). So this module carries a
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

    // NOTE: this drift-check asserts byte-equality of committed vs generated
    // schema — it does NOT itself assert the schema still REJECTS malformed
    // catalog entries. That negative-case teeth lives in the ajv suite
    // `plugin/cli/test/schema.test.ts` (10 negative fixtures — missing pin,
    // unknown source_kind, npm-missing-package, lowercase secret_env, http
    // endpoint_url, non-semver version, the `allOf` npm-requires case), run in
    // the `cli-unit` CI job against this same committed schema.json. Because
    // committed == generated, those negatives run transitively against the
    // generated output. Keep both green: a schemars change that is byte-stable
    // but semantically looser is caught by schema.test.ts, not here.
    #[test]
    fn schema_is_not_drifted() {
        let generated = schema_json();
        if std::env::var("UPDATE_SCHEMA").is_ok() {
            // Emit mode (contributor / Task 2): write the generated schema to the
            // committed path and return without asserting.
            std::fs::write(SCHEMA_PATH, &generated)
                .expect("write generated schema.json to plugin/catalog/");
            return;
        }
        // Assert mode (CI + every normal run): committed must equal generated.
        let committed = std::fs::read_to_string(SCHEMA_PATH)
            .expect("read committed plugin/catalog/schema.json");
        assert_eq!(
            committed, generated,
            "plugin/catalog/schema.json drifted from the Rust catalog types — \
             regenerate it with `UPDATE_SCHEMA=1 cargo test -p agentlinux-core schema` and commit the result"
        );
    }
}
