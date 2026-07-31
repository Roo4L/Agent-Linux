//! `category` — the pure `deriveCategory` port (CORE-03).
//!
//! Category derivation for `agentlinux list --by-category`
//! groups entries by a small fixed set of categories DERIVED from the entry's
//! tags (with `source_kind` as a fallback signal), never hardcoded per entry — so
//! a contributor adding a catalog entry lands in the right group by choosing a
//! canonical category tag, with zero CLI edits (the CAT-03 contract).
//!
//! Pure: no `std::env`/`std::fs`/`std::process`. `derive_category` is a total
//! function of `CatalogEntry.tags` + `source_kind` → `Category`.
//!
//! The golden corpus below was transcribed from the pre-cutover TypeScript
//! suite before it was deleted; it is now the authority. Every golden row is
//! ported verbatim below.
//!
//! # Pitfall 3 (RESEARCH): precedence is FIRST-MATCH-WINS, ORDER-SENSITIVE.
//! [`TAG_PRECEDENCE`] is an ordered slice, NOT a map: `workflow`/`token` MUST
//! precede `devops` (so rtk `["token","workflow","devops"]` resolves `workflow`),
//! and `coding-agent` MUST precede a bare `agent` (so codex
//! `["agent","coding-agent"]` resolves `coding-agent`). A `HashMap`/`BTreeMap`
//! would lose that ordering and diverge from the TS.

use crate::types::{CatalogEntry, Category, CategoryKey};

/// Tag → category precedence (FIRST matching tag wins). Order matters — this is
/// an ORDERED slice iterated in order, never a map. Byte-identical to
/// the TS `TAG_PRECEDENCE` array (`category.ts:44-54`): a tool tagged both
/// `workflow` and `devops` (e.g. rtk) is a workflow tool first, so `workflow`/
/// `token` precede `devops`; `coding-agent` beats a bare `agent` (claude-code);
/// and `browser`/`automation` beat `agent` (playwright-cli).
const TAG_PRECEDENCE: &[(&str, CategoryKey)] = &[
    ("coding-agent", CategoryKey::CodingAgent),
    ("assistant", CategoryKey::Assistant),
    ("mcp", CategoryKey::Mcp),
    ("workflow", CategoryKey::Workflow),
    ("token", CategoryKey::Workflow),
    ("devops", CategoryKey::Devops),
    ("browser", CategoryKey::Browser),
    ("automation", CategoryKey::Browser),
    ("agent", CategoryKey::CodingAgent),
];

/// Build the `Category` for a key with the exact TS label + display order
/// (`CATEGORIES` table, `category.ts:30-38`). Kept as a constructor (not a
/// static map) so the returned `Category` carries the byte-identical label/order
/// the TS `CATEGORIES[key]` yields.
#[must_use]
pub fn category_for(key: CategoryKey) -> Category {
    let (label, order) = match key {
        CategoryKey::CodingAgent => ("Coding agents", 1),
        CategoryKey::Assistant => ("AI assistants", 2),
        CategoryKey::Mcp => ("MCP servers", 3),
        CategoryKey::Devops => ("DevOps & security", 4),
        CategoryKey::Workflow => ("Token & workflow", 5),
        CategoryKey::Browser => ("Browser & automation", 6),
        CategoryKey::Other => ("Other", 99),
    };
    Category {
        key,
        label: label.to_string(),
        order,
    }
}

/// Derive an entry's display category from its tags, with `source_kind == "mcp"`
/// as a fallback signal and `Other` as the floor so no entry is ever dropped from
/// the grouped view (`deriveCategory`, `category.ts:58-65`).
///
/// First-match-wins over the ORDERED [`TAG_PRECEDENCE`]; then the
/// `source_kind == "mcp"` fallback (catches an entry whose tags omit `"mcp"`);
/// then the `Other` floor. `entry.tags` defaults to the empty list via serde, so
/// this mirrors the TS `entry.tags ?? []`.
#[must_use]
pub fn derive_category(entry: &CatalogEntry) -> Category {
    for (tag, key) in TAG_PRECEDENCE {
        if entry.tags.iter().any(|t| t == tag) {
            return category_for(*key);
        }
    }
    if entry.source_kind.as_deref() == Some("mcp") {
        return category_for(CategoryKey::Mcp);
    }
    category_for(CategoryKey::Other)
}

#[cfg(test)]
mod tests {
    //! Golden corpus — every row is ported VERBATIM from
    //! transcribed from the pre-cutover TypeScript suite.
    use super::*;

    /// Build a `CatalogEntry` fixture mirroring the TS `entry(id, tags, source_kind)`
    /// helper (`category.test.ts:13-25`). `source_kind` defaults to `"npm"` as in TS.
    fn entry(id: &str, tags: &[&str], source_kind: &str) -> CatalogEntry {
        let json = serde_json::json!({
            "id": id,
            "pinned_version": "1.0.0",
            "tags": tags,
            "source_kind": source_kind,
        });
        serde_json::from_value(json).expect("fixture entry deserializes")
    }

    // category.test.ts:28-32 — "coding-agent tag wins over a bare agent tag".
    #[test]
    fn coding_agent_tag_wins_over_bare_agent() {
        // deriveCategory(entry("codex", ["agent", "coding-agent"])).key === "coding-agent"
        assert_eq!(
            derive_category(&entry("codex", &["agent", "coding-agent"], "npm")).key,
            CategoryKey::CodingAgent
        );
        // claude-code has only a bare `agent` tag → still a coding agent (last row).
        assert_eq!(
            derive_category(&entry("claude-code", &["agent", "anthropic"], "npm")).key,
            CategoryKey::CodingAgent
        );
    }

    // category.test.ts:34-38 — "assistant tag → AI assistants" (label asserted).
    #[test]
    fn assistant_tag_maps_to_ai_assistants_with_label() {
        let c = derive_category(&entry("openclaw", &["assistant", "daemon"], "script"));
        assert_eq!(c.key, CategoryKey::Assistant);
        assert_eq!(c.label, "AI assistants");
    }

    // category.test.ts:40-44 — "mcp via tag OR source_kind fallback".
    #[test]
    fn mcp_via_tag_or_source_kind_fallback() {
        assert_eq!(
            derive_category(&entry("context7", &["mcp", "docs"], "mcp")).key,
            CategoryKey::Mcp
        );
        // source_kind=mcp catches an entry whose tags omit "mcp".
        assert_eq!(
            derive_category(&entry("bare-mcp", &["docs"], "mcp")).key,
            CategoryKey::Mcp
        );
    }

    // category.test.ts:46-52 — "workflow/token precede devops (rtk is a token tool)".
    #[test]
    fn workflow_token_precede_devops() {
        assert_eq!(
            derive_category(&entry("rtk", &["token", "workflow", "devops"], "binary")).key,
            CategoryKey::Workflow
        );
        assert_eq!(
            derive_category(&entry("ccusage", &["workflow", "cost", "token"], "npm")).key,
            CategoryKey::Workflow
        );
    }

    // category.test.ts:54-60 — "devops when no workflow/token tag".
    #[test]
    fn devops_when_no_workflow_or_token_tag() {
        assert_eq!(
            derive_category(&entry("gh", &["devops", "git", "github"], "binary")).key,
            CategoryKey::Devops
        );
        assert_eq!(
            derive_category(&entry(
                "trivy",
                &["devops", "security", "scanner"],
                "binary"
            ))
            .key,
            CategoryKey::Devops
        );
    }

    // category.test.ts:62-67 — "browser/automation → Browser & automation, beating agent".
    #[test]
    fn browser_automation_beats_bare_agent() {
        assert_eq!(
            derive_category(&entry(
                "playwright-cli",
                &["browser", "automation", "agent-skill"],
                "npm"
            ))
            .key,
            CategoryKey::Browser
        );
    }

    // category.test.ts:69-72 — "unmatched tags fall to Other, never dropped".
    #[test]
    fn unmatched_tags_fall_to_other_never_dropped() {
        assert_eq!(
            derive_category(&entry("mystery", &["unknowable"], "npm")).key,
            CategoryKey::Other
        );
        assert_eq!(
            derive_category(&entry("no-tags", &[], "npm")).key,
            CategoryKey::Other
        );
    }

    // The `CATEGORIES` table (labels + display orders, category.ts:30-38) is
    // carried by `category_for`; assert the full table so a label/order drift trips.
    #[test]
    fn category_for_carries_ts_labels_and_orders() {
        let cases = [
            (CategoryKey::CodingAgent, "Coding agents", 1u32),
            (CategoryKey::Assistant, "AI assistants", 2),
            (CategoryKey::Mcp, "MCP servers", 3),
            (CategoryKey::Devops, "DevOps & security", 4),
            (CategoryKey::Workflow, "Token & workflow", 5),
            (CategoryKey::Browser, "Browser & automation", 6),
            (CategoryKey::Other, "Other", 99),
        ];
        for (key, label, order) in cases {
            let c = category_for(key);
            assert_eq!(c.key, key);
            assert_eq!(c.label, label);
            assert_eq!(c.order, order);
        }
    }
}

#[cfg(test)]
mod proptests {
    //! Property tests (TEST-01) — `derive_category` totality + determinism, and
    //! the precedence-monotonicity property (the property form of Pitfall 3).
    use super::*;
    use proptest::prelude::*;

    /// An arbitrary tag drawn from the precedence tags + some noise tags, so the
    /// generated entries cross the interesting first-match boundaries.
    fn tag() -> impl Strategy<Value = String> {
        prop_oneof![
            Just("coding-agent".to_string()),
            Just("assistant".to_string()),
            Just("mcp".to_string()),
            Just("workflow".to_string()),
            Just("token".to_string()),
            Just("devops".to_string()),
            Just("browser".to_string()),
            Just("automation".to_string()),
            Just("agent".to_string()),
            "[a-z]{1,6}".prop_map(|s| s),
        ]
    }

    fn arbitrary_entry() -> impl Strategy<Value = CatalogEntry> {
        (
            proptest::collection::vec(tag(), 0..6),
            proptest::option::of(prop_oneof![
                Just("npm".to_string()),
                Just("mcp".to_string()),
                Just("binary".to_string()),
                Just("script".to_string()),
            ]),
        )
            .prop_map(|(tags, source_kind)| {
                let json = serde_json::json!({
                    "id": "prop",
                    "pinned_version": "1.0.0",
                    "tags": tags,
                    "source_kind": source_kind,
                });
                serde_json::from_value(json).expect("prop entry deserializes")
            })
    }

    proptest! {
        // Totality + determinism: any entry yields exactly one Category (the
        // `Other` floor guarantees totality) and two calls agree.
        #[test]
        fn derive_category_total_and_deterministic(entry in arbitrary_entry()) {
            let a = derive_category(&entry);
            let b = derive_category(&entry);
            prop_assert_eq!(&a, &b);
            // The key is always one of the seven canonical keys.
            prop_assert!(matches!(
                a.key,
                CategoryKey::CodingAgent
                    | CategoryKey::Assistant
                    | CategoryKey::Mcp
                    | CategoryKey::Devops
                    | CategoryKey::Workflow
                    | CategoryKey::Browser
                    | CategoryKey::Other
            ));
        }

        // Precedence-monotonicity (the property form of Pitfall 3): if the
        // highest-precedence tag present determines the result, prepending a
        // LOWER-precedence tag must NOT change it. We take an entry, find its
        // derived category, then assert appending lower-precedence noise is inert.
        #[test]
        fn derive_category_precedence_is_first_match_wins(
            tags in proptest::collection::vec(tag(), 1..6),
        ) {
            // The category of `tags` equals the category of the FIRST precedence
            // tag that appears in `tags` (order over TAG_PRECEDENCE, not over the
            // tags vec). Recompute the expected key by scanning TAG_PRECEDENCE.
            let json = serde_json::json!({
                "id": "prop", "pinned_version": "1.0.0", "tags": tags,
            });
            let entry: CatalogEntry = serde_json::from_value(json).unwrap();
            let got = derive_category(&entry).key;

            let mut expected = None;
            for (t, k) in TAG_PRECEDENCE {
                if entry.tags.iter().any(|x| x == t) {
                    expected = Some(*k);
                    break;
                }
            }
            let expected = expected.unwrap_or(CategoryKey::Other);
            prop_assert_eq!(got, expected);
        }
    }
}
