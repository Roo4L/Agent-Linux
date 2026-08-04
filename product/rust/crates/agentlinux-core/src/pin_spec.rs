//! `pin_spec` — the pure `parsePinSpec` port (CORE-03).
//!
//! Parses `agentlinux pin <name>=<target>`
//! parses a pin spec into a `PinTarget` discriminated union. This module is the
//! PURE parser only — the `pinCmd` verb (catalog lookup, sentinel mutation,
//! `process.exit`) lives in the bin's `cmd::pin`.
//!
//! Pure: no `std::env`/`std::fs`/`std::process`. The only version op routes
//! through [`crate::semver_shim::valid`] — never `semver::` directly.
//!
//! The golden corpus below was transcribed from the pre-cutover TypeScript
//! suite before it was deleted; it is now the authority. Every golden row is
//! ported verbatim below, INCLUDING which of the two error messages each bad
//! spec throws.
//!
//! # Pitfalls (RESEARCH)
//! - **Pitfall 1** — the TS `eq <= 0` guard (`pin.ts:56`) collapses TWO error
//!   branches: `"no-equals"` (no `=`) AND `"=curated"` (empty name, `eq === 0`).
//!   Both yield the [`PinSpecError::Usage`] `<name>=<target>` message. In Rust
//!   this is `matches!(idx, None | Some(0))`.
//! - **Pitfall 2** — TWO distinct error messages: [`PinSpecError::Usage`] vs
//!   [`PinSpecError::InvalidTarget`]. The subtle case: `"foo="` (trailing `=`,
//!   EMPTY target) is `InvalidTarget`, NOT `Usage`, because `""` is not
//!   `curated`/`latest`/valid-semver (`pin.test.ts:155-158`).
//! - The version case stores the RAW `tgt` string (matching TS `version: tgt`,
//!   `pin.ts:69`), NOT the normalized form — `valid` is used only as the
//!   accept/reject predicate here.

use crate::semver_shim;
use thiserror::Error;

/// The parsed pin target — a Rust enum mirroring the TS `PinTarget` discriminated
/// union (`pin.ts:47-50`, Pattern 2). `Curated`/`Latest` carry no payload (their
/// version semantics are resolution-time concerns); `Version` carries the parsed
/// (raw) semver string.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PinTarget {
    /// `<name>=curated` — clears the sticky flag; follows the catalog pin.
    Curated,
    /// `<name>=latest` — sticky follow-upstream-latest.
    Latest,
    /// `<name>=<semver>` — sticky pin at this exact version. Carries the RAW
    /// target string (matching TS `version: tgt`, `pin.ts:69`).
    Version(String),
}

/// The parsed pin spec: the agent `name` (TS `spec.slice(0, eq)`) plus its
/// [`PinTarget`]. Mirrors the TS `PinTarget` union, which ALSO carries `name`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedPin {
    pub name: String,
    pub target: PinTarget,
}

/// Typed parse error with the TWO distinct message shapes the corpus greps for
/// Message wording is copied from `pin.ts:57-59` / `pin.ts:71-73` so
/// the rendered `to_string()` stays byte-identical to the TS `throw new Error(...)`.
#[derive(Debug, Error, PartialEq, Eq)]
pub enum PinSpecError {
    /// Bad/absent `=` (no `=`, or empty name — the `eq <= 0` collapse, Pitfall 1).
    /// The message contains `<name>=<target>` (what `pin.test.ts` greps for) and
    /// mirrors the `pin.ts:57-59` usage help listing curated/latest/semver.
    #[error(
        "agentlinux pin: expected '<name>=<target>' (got '{spec}');\n  valid targets: curated, latest, or exact semver like 2.1.7"
    )]
    Usage { spec: String },
    /// The target RHS is not `curated`/`latest`/valid-semver. The
    /// message contains `invalid target` and lists `curated`, `latest`, `semver`
    /// (what `pin.test.ts` greps for), mirroring `pin.ts:71-73`.
    #[error(
        "agentlinux pin: invalid target '{target}' in '{spec}';\n  valid targets: curated, latest, or exact semver (e.g. 2.1.7)"
    )]
    InvalidTarget { spec: String, target: String },
}

/// Parse a `<name>=<target>` pin spec into a [`ParsedPin`], or a typed
/// [`PinSpecError`]. Byte-for-byte with the TS `parsePinSpec` (`pin.ts:52-74`).
///
/// - `spec.find('=')` → `matches!(idx, None | Some(0))` → [`PinSpecError::Usage`]
///   (Pitfall 1: catches BOTH "no `=`" AND empty-name `"=curated"`, exactly the
///   TS `eq <= 0`).
/// - `tgt == "curated"` → `Curated`; `tgt == "latest"` → `Latest`.
/// - else `semver_shim::valid(tgt)` accepts → `Version(tgt.to_string())` — the
///   RAW target is kept (TS `version: tgt`), `valid` is the accept/reject
///   predicate only.
/// - else → [`PinSpecError::InvalidTarget`] (Pitfall 2: empty target `"foo="`
///   lands here, since `""` is not curated/latest/valid-semver).
pub fn parse_pin_spec(spec: &str) -> Result<ParsedPin, PinSpecError> {
    let idx = spec.find('=');
    // eq <= 0 catches both 'no-equals' (None) and '=curated' (Some(0), empty
    // name). Both need the usage help pointing at <name>=<target> form.
    if matches!(idx, None | Some(0)) {
        return Err(PinSpecError::Usage {
            spec: spec.to_string(),
        });
    }
    // Safe: idx is Some(n) with n > 0 by the guard above.
    let idx = idx.expect("guard rejected None");
    let name = &spec[..idx];
    let tgt = &spec[idx + 1..];

    if tgt == "curated" {
        return Ok(ParsedPin {
            name: name.to_string(),
            target: PinTarget::Curated,
        });
    }
    if tgt == "latest" {
        return Ok(ParsedPin {
            name: name.to_string(),
            target: PinTarget::Latest,
        });
    }
    // semver_shim::valid accepts pre-releases (2.1.7-beta.1) and rejects partials
    // (2.1) + ranges (^2.1) — pins are version points, not ranges. The RAW tgt is
    // kept as the version (matching TS `version: tgt`, pin.ts:69).
    if semver_shim::valid(tgt).is_some() {
        return Ok(ParsedPin {
            name: name.to_string(),
            target: PinTarget::Version(tgt.to_string()),
        });
    }

    Err(PinSpecError::InvalidTarget {
        spec: spec.to_string(),
        target: tgt.to_string(),
    })
}

#[cfg(test)]
mod tests {
    //! Golden corpus — every row ported VERBATIM from
    //! transcribed from the pre-cutover TypeScript suite. The Ok rows
    //! assert the parsed value; the Err rows assert the rendered message CONTAINS
    //! the exact substring the corpus greps for, so a message drift trips.
    use super::*;

    // pin.test.ts:118-120 — "curated target".
    #[test]
    fn curated_target() {
        assert_eq!(
            parse_pin_spec("foo=curated").unwrap(),
            ParsedPin {
                name: "foo".to_string(),
                target: PinTarget::Curated
            }
        );
    }

    // pin.test.ts:122-124 — "latest target".
    #[test]
    fn latest_target() {
        assert_eq!(
            parse_pin_spec("foo=latest").unwrap(),
            ParsedPin {
                name: "foo".to_string(),
                target: PinTarget::Latest
            }
        );
    }

    // pin.test.ts:126-132 — "exact semver target".
    #[test]
    fn exact_semver_target() {
        assert_eq!(
            parse_pin_spec("foo=2.1.7").unwrap(),
            ParsedPin {
                name: "foo".to_string(),
                target: PinTarget::Version("2.1.7".to_string())
            }
        );
    }

    // pin.test.ts:134-140 — "pre-release semver target" (accepted via valid).
    #[test]
    fn prerelease_semver_target() {
        let parsed = parse_pin_spec("foo=2.1.7-beta.1").unwrap();
        assert_eq!(
            parsed.target,
            PinTarget::Version("2.1.7-beta.1".to_string())
        );
    }

    // pin.test.ts:142-145 — "invalid target: throws with message listing valid
    // targets" — greps /invalid target/ AND /curated.*latest.*semver/.
    #[test]
    fn invalid_target_message_lists_valid_targets() {
        let err = parse_pin_spec("foo=bogus").unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("invalid target"), "got: {msg}");
        // /curated.*latest.*semver/ — the three appear in order.
        let ci = msg.find("curated").expect("curated in message");
        let li = msg.find("latest").expect("latest in message");
        let si = msg.find("semver").expect("semver in message");
        assert!(
            ci < li && li < si,
            "curated<latest<semver ordering; got: {msg}"
        );
        assert!(matches!(err, PinSpecError::InvalidTarget { .. }));
    }

    // pin.test.ts:147-149 — "no '=': throws with usage help" — greps /<name>=<target>/.
    #[test]
    fn no_equals_usage_help() {
        let err = parse_pin_spec("no-equals").unwrap_err();
        assert!(err.to_string().contains("<name>=<target>"), "got: {err}");
        assert!(matches!(err, PinSpecError::Usage { .. }));
    }

    // pin.test.ts:151-153 — "empty name: throws" (eq === 0, Pitfall 1) — greps
    // /<name>=<target>/ (the USAGE message, NOT invalid-target).
    #[test]
    fn empty_name_usage_help() {
        let err = parse_pin_spec("=curated").unwrap_err();
        assert!(err.to_string().contains("<name>=<target>"), "got: {err}");
        assert!(
            matches!(err, PinSpecError::Usage { .. }),
            "empty name is a Usage error, not InvalidTarget"
        );
    }

    // pin.test.ts:155-158 — "empty target (trailing '='): throws with
    // invalid-target message" — greps /invalid target/. The subtle
    // one: "" is not curated/latest/valid-semver, so InvalidTarget NOT Usage.
    #[test]
    fn empty_target_invalid_target_message() {
        let err = parse_pin_spec("foo=").unwrap_err();
        assert!(err.to_string().contains("invalid target"), "got: {err}");
        assert!(
            matches!(err, PinSpecError::InvalidTarget { .. }),
            "empty target is InvalidTarget, not Usage (Pitfall 2)"
        );
    }
}

#[cfg(test)]
mod proptests {
    //! Property test (TEST-01) — `parse_pin_spec` totality:
    //! for any `&str` it returns `Ok` or a `PinSpecError`, never panics. Mirrors
    //! the `reuse.rs` totality proptest.
    use super::*;
    use proptest::prelude::*;

    proptest! {
        // Totality on catalog-realistic specs (name=target shapes + noise).
        #[test]
        fn parse_pin_spec_total_on_specs(
            name in "[a-z-]{0,8}",
            sep in prop_oneof![Just("="), Just("")],
            tgt in prop_oneof![
                Just("curated".to_string()),
                Just("latest".to_string()),
                "[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}".prop_map(|s| s),
                "[a-z0-9.]{0,8}".prop_map(|s| s),
            ],
        ) {
            let spec = format!("{name}{sep}{tgt}");
            // Totality is the floor; the POSTCONDITIONS are what a `parse_pin_spec`
            // returning `Usage` for every input would fail. Accepting any outcome
            // (the previous form) made that mutant survive.
            match parse_pin_spec(&spec) {
                Ok(parsed) => {
                    // A parse only succeeds on the `<name>=<target>` form, and the
                    // name it reports is exactly the text before the first `=`.
                    prop_assert_eq!(&parsed.name, &name);
                    prop_assert!(!name.is_empty(), "an empty name must be a Usage error");
                    prop_assert_eq!(sep, "=");
                    // …and the target is one of the three accepted shapes,
                    // classified independently of parse_pin_spec.
                    match &parsed.target {
                        PinTarget::Curated => prop_assert_eq!(&tgt, "curated"),
                        PinTarget::Latest => prop_assert_eq!(&tgt, "latest"),
                        PinTarget::Version(v) => {
                            prop_assert_eq!(v, &tgt);
                            prop_assert!(
                                semver_shim::valid(&tgt).is_some(),
                                "a Version pin must be valid semver: {:?}", tgt
                            );
                        }
                    }
                }
                // Usage is for the shape (`<name>=<target>` with a non-empty name).
                Err(PinSpecError::Usage { .. }) => {
                    prop_assert!(sep.is_empty() || name.is_empty(), "spec={:?}", spec);
                }
                // InvalidTarget is only for a well-shaped spec whose target is
                // neither keyword nor semver.
                Err(PinSpecError::InvalidTarget { .. }) => {
                    prop_assert_eq!(sep, "=");
                    prop_assert!(!name.is_empty());
                    prop_assert!(tgt != "curated" && tgt != "latest");
                    prop_assert!(semver_shim::valid(&tgt).is_none(), "tgt={:?}", tgt);
                }
            }
        }

        // Totality on ARBITRARY (adversarial) strings — never panics.
        #[test]
        fn parse_pin_spec_total_on_arbitrary(spec in ".*") {
            let _ = parse_pin_spec(&spec);
        }
    }
}
