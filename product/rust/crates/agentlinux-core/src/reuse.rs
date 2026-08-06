//! `reuse` — the pure REUSE-03 catalog-agent compatibility decision.
//!
//! Predicates 1 + 2 of the per-agent reuse decision
//! (the gnarly provisioner unit the stack-reconsideration decision quotes). The
//! bash function stops at two of three predicates because semver-range
//! satisfaction is non-trivial in bash; predicate 3 (version-in-window) is
//! layered on later by the CLI. This port keeps that exact contract — it does
//! NOT evaluate semver here.
//!
//! Pure: no `std::env`/`std::fs`/`std::process`. The `agentlinux` bin owns the
//! env-var reads and canonical-path map (the pure/adapter split); this module
//! only decides.
//!
//! Predicate order (byte-for-byte with the bash):
//! 1. empty id → Create
//! 2. status "absent" → Create
//! 3. unknown id (no map) → Create
//! 4. status "broken" → Remediate
//! 5. healthy, path != canonical → Remediate
//!    (EXCEPT id=="gsd" && detected_path == gsd_system_path → Reuse)
//! 6. healthy, path match → Reuse

/// The dispatch token `reuse::agent_decision` yields, consumed by
/// `remediate.sh:288`. `as_str`/`Display` render the lowercase tokens the bats
/// `$output == token` assertions expect.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decision {
    Reuse,
    Remediate,
    Create,
}

impl Decision {
    /// The lowercase stdout token (`reuse` | `remediate` | `create`).
    pub fn as_str(self) -> &'static str {
        match self {
            Decision::Reuse => "reuse",
            Decision::Remediate => "remediate",
            Decision::Create => "create",
        }
    }
}

impl std::fmt::Display for Decision {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Decide reuse/remediate/create for a catalog agent from predicates 1 + 2.
///
/// * `id` — the catalog agent id (e.g. `claude-code`, `gsd`). Empty → Create.
/// * `status` — the detector verdict: `healthy` | `broken` | `absent` (any
///   other value is treated like a non-absent, non-broken state and reaches the
///   path comparison, matching the bash which only special-cases `absent`/
///   `broken`).
/// * `detected_path` — the binary path the detector resolved (`None` when the
///   detector exported an empty/unset path; compared as `""` like the bash
///   `${!path_var:-}`).
/// * `canonical` — the catalog canonical path for `id`, or `None` for an
///   unknown id (not in the map) → Create.
/// * `gsd_system_path` — the GSD deployed-system VERSION path; a healthy `gsd`
///   detected here is a second valid canonical presence → Reuse.
pub fn agent_decision(
    id: &str,
    status: &str,
    detected_path: Option<&str>,
    canonical: Option<&str>,
    gsd_system_path: &str,
) -> Decision {
    // Predicate: empty id → Create (bash `[[ -z "$id" ]]`).
    if id.is_empty() {
        return Decision::Create;
    }

    // Predicate 1: status. absent → Create.
    if status == "absent" {
        return Decision::Create;
    }

    // Predicate 2: canonical path lookup. Unknown id (no map entry) → Create,
    // so future catalog ids fall through to install rather than mis-REUSE.
    let Some(canonical) = canonical else {
        return Decision::Create;
    };

    // broken → remediate (uninstall + reinstall via the recipe).
    if status == "broken" {
        return Decision::Remediate;
    }

    // healthy — compare the detected binary path to the catalog canonical path.
    // An unset/empty detected path is compared as "" (bash `${!path_var:-}`).
    let detected_path = detected_path.unwrap_or("");
    if detected_path != canonical {
        // GSD's deployed-system form (npx install) lives at the VERSION file
        // rather than the bootstrapper binary path — also a valid canonical
        // presence, so reuse instead of treating it as a wrong-path reinstall.
        if id == "gsd" && detected_path == gsd_system_path {
            return Decision::Reuse;
        }
        // Healthy but wrong path → reinstall at the canonical path.
        return Decision::Remediate;
    }

    // Healthy + path-match. The CLI re-checks version-in-window before acting.
    Decision::Reuse
}

#[cfg(test)]
mod tests {
    use super::*;

    // Canonical-path fixtures mirroring the bash REUSE_AGENT_CANONICAL_PATHS map
    // + REUSE_GSD_SYSTEM_PATH, so the six REUSE-03 branches assert against the
    // real values the bin resolves.
    const CLAUDE_CANONICAL: &str = "/home/agent/.local/bin/claude";
    const GSD_CANONICAL: &str = "/home/agent/.npm-global/bin/gsd-core";
    const GSD_SYSTEM_PATH: &str = "/home/agent/.claude/gsd-core/VERSION";

    // Branch 1: status=absent → Create (13-reuse.bats REUSE-03 absent case).
    #[test]
    fn absent_status_creates() {
        assert_eq!(
            agent_decision(
                "claude-code",
                "absent",
                None,
                Some(CLAUDE_CANONICAL),
                GSD_SYSTEM_PATH
            ),
            Decision::Create
        );
    }

    // Branch 2: unknown id (no canonical) → Create (defensive future-id path).
    #[test]
    fn unknown_id_creates() {
        assert_eq!(
            agent_decision(
                "new-thing",
                "healthy",
                Some("/usr/local/bin/new-thing"),
                None,
                GSD_SYSTEM_PATH
            ),
            Decision::Create
        );
    }

    // Branch 3: status=broken → Remediate.
    #[test]
    fn broken_status_remediates() {
        assert_eq!(
            agent_decision(
                "claude-code",
                "broken",
                Some(CLAUDE_CANONICAL),
                Some(CLAUDE_CANONICAL),
                GSD_SYSTEM_PATH
            ),
            Decision::Remediate
        );
    }

    // Branch 4: healthy + canonical path match → Reuse.
    #[test]
    fn healthy_canonical_reuses() {
        assert_eq!(
            agent_decision(
                "claude-code",
                "healthy",
                Some(CLAUDE_CANONICAL),
                Some(CLAUDE_CANONICAL),
                GSD_SYSTEM_PATH
            ),
            Decision::Reuse
        );
    }

    // Branch 5: healthy + wrong path → Remediate (npm-global install case).
    #[test]
    fn healthy_wrong_path_remediates() {
        assert_eq!(
            agent_decision(
                "claude-code",
                "healthy",
                Some("/home/agent/.npm-global/bin/claude"),
                Some(CLAUDE_CANONICAL),
                GSD_SYSTEM_PATH
            ),
            Decision::Remediate
        );
    }

    // Branch 6: gsd at the deployed-system VERSION path → Reuse (npx form),
    // NOT remediate despite differing from the bootstrapper canonical path.
    #[test]
    fn gsd_system_version_path_reuses() {
        assert_eq!(
            agent_decision(
                "gsd",
                "healthy",
                Some(GSD_SYSTEM_PATH),
                Some(GSD_CANONICAL),
                GSD_SYSTEM_PATH
            ),
            Decision::Reuse
        );
    }

    // Defensive: the gsd-system-path special case is gsd-only — the same
    // deployed-system path for a different id still remediates on mismatch.
    #[test]
    fn system_path_special_case_is_gsd_only() {
        assert_eq!(
            agent_decision(
                "claude-code",
                "healthy",
                Some(GSD_SYSTEM_PATH),
                Some(CLAUDE_CANONICAL),
                GSD_SYSTEM_PATH
            ),
            Decision::Remediate
        );
    }

    // Empty id → Create (bash `[[ -z "$id" ]]`).
    #[test]
    fn empty_id_creates() {
        assert_eq!(
            agent_decision("", "healthy", Some(CLAUDE_CANONICAL), None, GSD_SYSTEM_PATH),
            Decision::Create
        );
    }

    // Unset/empty detected path on a healthy agent → path-mismatch → Remediate.
    #[test]
    fn healthy_empty_path_remediates() {
        assert_eq!(
            agent_decision(
                "claude-code",
                "healthy",
                None,
                Some(CLAUDE_CANONICAL),
                GSD_SYSTEM_PATH
            ),
            Decision::Remediate
        );
        // and the token renders lowercase for the bats stdout assertion
        assert_eq!(Decision::Remediate.as_str(), "remediate");
        assert_eq!(Decision::Reuse.to_string(), "reuse");
        assert_eq!(Decision::Create.as_str(), "create");
    }
}

#[cfg(test)]
mod fallthrough_tests {
    //! The status fallthrough, stated explicitly because it is easy to read the
    //! branch order and conclude the opposite.
    use super::*;

    /// Only `absent` and `broken` are recognised negatively; ANY other status
    /// value takes the healthy path. So an agent whose detect record carries an
    /// unrecognised status (a future `degraded`, or a truncated cache write) at
    /// the canonical path is REUSED, not reinstalled.
    ///
    /// This test PINS CURRENT BEHAVIOUR — it does not endorse it. The port from
    /// Bash `reuse::agent_decision` inherited a fail-OPEN default: the only way
    /// a fourth status reaches here is a hand-edited or truncated
    /// `/run/agentlinux-detect.json`, and the consequence is that a possibly
    /// broken binary at the canonical path is reused instead of reinstalled.
    /// Changing it is a behaviour change with a bats contract behind it, so it is
    /// recorded rather than fixed in passing; see AL-129. The structural fix is a
    /// typed `Status` enum at the cache boundary, which makes the fourth case
    /// unrepresentable instead of merely tested.
    #[test]
    fn an_unrecognised_status_currently_fails_open_to_reuse() {
        let canonical = "/home/agent/.local/bin/claude";
        assert_eq!(
            agent_decision(
                "claude-code",
                "degraded",
                Some(canonical),
                Some(canonical),
                ""
            ),
            Decision::Reuse
        );
        // …and away from the canonical path it remediates, same as healthy.
        assert_eq!(
            agent_decision(
                "claude-code",
                "degraded",
                Some("/usr/bin/claude"),
                Some(canonical),
                ""
            ),
            Decision::Remediate
        );
    }
}

#[cfg(test)]
mod proptests {
    //! Property test (TEST-01) — `agent_decision` totality. The fn is
    //! branch-total (every path returns a `Decision`); this proves it across
    //! arbitrary id/status/path strings, including the empty-string and
    //! unknown-id boundaries, without panicking.
    use super::*;
    use proptest::prelude::*;

    proptest! {
        #[test]
        fn agent_decision_is_total(
            id in ".*",
            // Drawn from the vocabulary `detect` actually emits, plus arbitrary
            // junk. A bare `".*"` essentially never produces the literal
            // "broken" or "absent", so the two status-dependent postconditions
            // below fired ZERO times in 256 cases — asserted but unreachable.
            status in prop_oneof![
                Just("healthy".to_string()),
                Just("broken".to_string()),
                Just("absent".to_string()),
                ".*",
            ],
            detected_path in proptest::option::of(".*"),
            canonical in proptest::option::of(".*"),
            gsd_system_path in ".*",
            // Same problem for the reuse arm: two independent `option::of(".*")`
            // draws never coincide, so "detected at exactly its canonical path"
            // never happened. This aligns them half the time.
            align_paths in proptest::bool::weighted(0.5),
        ) {
            let detected_path = if align_paths { canonical.clone() } else { detected_path };

            // Totality plus the arms that are decidable from the inputs alone.
            // "The return is one of three enum variants" is guaranteed by the
            // type system, so on its own this property could not fail.
            let decision = agent_decision(
                &id,
                &status,
                detected_path.as_deref(),
                canonical.as_deref(),
                &gsd_system_path,
            );
            prop_assert!(matches!(
                decision,
                Decision::Reuse | Decision::Remediate | Decision::Create
            ));

            // An absent agent, an empty id, or an id with no canonical path can
            // only ever be CREATE — never a reuse of something that is not there.
            if id.is_empty() || status == "absent" || canonical.is_none() {
                prop_assert_eq!(decision, Decision::Create);
            }
            // A known-broken agent is always a REMEDIATE, whatever its path.
            if !id.is_empty() && status == "broken" && canonical.is_some() {
                prop_assert_eq!(decision, Decision::Remediate);
            }
            // An agent at exactly its canonical path with a status that is not
            // `absent`/`broken` is always a REUSE — see
            // `an_unrecognised_status_currently_fails_open_to_reuse` for why the
            // condition is phrased that way rather than `status == "healthy"`.
            if !id.is_empty()
                && status != "absent"
                && status != "broken"
                && canonical.is_some()
                && detected_path.as_deref() == canonical.as_deref()
            {
                prop_assert_eq!(decision, Decision::Reuse);
            }
        }
    }
}
