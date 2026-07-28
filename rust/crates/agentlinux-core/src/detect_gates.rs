//! `detect_gates` — the PURE detect-gate decision cores (CORE-03).
//!
//! Ports the PURE decision logic of `plugin/cli/src/detect.ts:32-275`:
//! `isCanonicalAgentPath`, the `managedBinDir`/`isManagedPath`/`isAtManagedPath`
//! source_kind heuristics, and the pre-`statSync` gate sets of `tryReuse` /
//! `tryRemediate` / `detectPresence`.
//!
//! # The pure/I-O seam (Phase-56)
//! The detect-cache read (`readCachedAgentById`/`readDetectedAgent`/
//! `detectCachePath`/`readCacheAgents`) and `tryReuse`'s host `statSync`
//! re-validation are OUT of scope — they are the Phase-56 adapter. This module
//! ports only the DECISION over a `DetectedAgent` value + `CatalogEntry` +
//! canonical-path map → a slim verdict. NO `std::fs`, NO `std::env`, NO
//! `statSync`, NO cache read. The crate stays PURE.
//!
//! # Distinct from `reuse.rs`
//! [`crate::reuse::agent_decision`] is the PROVISIONER's 3-way Reuse/Remediate/
//! Create dispatch that deliberately does NOT evaluate semver. These gates
//! evaluate the `compatibility_window` via [`crate::semver_shim::satisfies`]
//! (RESEARCH §"Reuse Overlap Clarity"). The two are separate decision surfaces —
//! do not conflate.
//!
//! # Canonical map is a parameter (Phase-57)
//! `CANONICAL_PATHS` / `GSD_SYSTEM_PATH` stay DUPLICATED (detect.ts + bin + bash)
//! until Phase 57. The deciders receive `canonical` / `gsd_system_path` /
//! `agent_home` as parameters — never hardcode a map inside a decider (mirrors
//! `reuse::agent_decision`).
//!
//! # Pitfalls (RESEARCH)
//! - **Pitfall 4** — `!!entry.compatibility_window` (detect.ts:271) is FALSY for
//!   BOTH `undefined` AND `""`. Gate on `.as_deref().is_some_and(|w| !w.is_empty())`
//!   so an empty-string window is treated as absent (NOT adoptable).
//! - **Pitfall 5** — `tryReuse` uses `isAtManagedPath` (any catalog tool at its
//!   managed dir) while `tryRemediate` is CANONICAL-GATED (only ids WITH a
//!   canonical entry). Different predicates/sources.
//! - **Pitfall 6** — `semver.valid` returns the CLEAN (normalized) version; the
//!   deciders forward that clean value, not the raw cache string.

use crate::semver_shim;
use crate::types::{CatalogEntry, DetectedAgent};

// ---------------------------------------------------------------------------
// Path predicates (pure ports of detect.ts:32-81)
// ---------------------------------------------------------------------------

/// A detected agent is "at canonical" when its path is the catalog canonical OR,
/// for gsd only, the deployed-system VERSION file (gsd's dual presence).
/// Port of `isCanonicalAgentPath` (detect.ts:32-38).
#[must_use]
pub fn is_canonical_agent_path(
    entry: &CatalogEntry,
    path: &str,
    canonical: &str,
    gsd_system_path: &str,
) -> bool {
    path == canonical || (entry.id == "gsd" && path == gsd_system_path)
}

/// The dir AgentLinux's recipe installs a tool's binary into, by `source_kind`:
/// npm globals → `{agent_home}/.npm-global/bin`; prebuilt binaries and script
/// installers → `{agent_home}/.local/bin`; `None` for kinds with no PATH binary
/// (mcp/other). Port of `managedBinDir` (detect.ts:51-61).
///
/// `agent_home` is passed in (TS reads `AGENTLINUX_AGENT_HOME` — that env read is
/// the Phase-56 adapter; this pure fn receives the resolved home string).
#[must_use]
pub fn managed_bin_dir(entry: &CatalogEntry, agent_home: &str) -> Option<String> {
    match entry.source_kind.as_deref() {
        Some("npm") => Some(format!("{agent_home}/.npm-global/bin")),
        Some("binary") | Some("script") => Some(format!("{agent_home}/.local/bin")),
        _ => None,
    }
}

/// True when a detected binary sits in its `source_kind`'s managed install dir.
/// Port of `isManagedPath` (detect.ts:65-68).
#[must_use]
pub fn is_managed_path(entry: &CatalogEntry, path: &str, agent_home: &str) -> bool {
    match managed_bin_dir(entry, agent_home) {
        Some(dir) => path.starts_with(&format!("{dir}/")),
        None => false,
    }
}

/// "Is this detected binary at the path AgentLinux would manage it at?" — the
/// single at-canonical predicate shared by the reuse gate and the presence gate.
/// Port of `isAtManagedPath` (detect.ts:78-81): the original three carry an EXACT
/// canonical path; every other catalog tool derives its managed path from the
/// `source_kind` install dir.
///
/// `canonical` is `Some` for an id WITH a `CANONICAL_PATHS` entry (→ exact
/// canonical predicate), `None` otherwise (→ source_kind managed-dir heuristic).
#[must_use]
pub fn is_at_managed_path(
    entry: &CatalogEntry,
    path: &str,
    canonical: Option<&str>,
    gsd_system_path: &str,
    agent_home: &str,
) -> bool {
    match canonical {
        Some(known) => is_canonical_agent_path(entry, path, known, gsd_system_path),
        None => is_managed_path(entry, path, agent_home),
    }
}

// ---------------------------------------------------------------------------
// Reuse gate (pure part of tryReuse, detect.ts:165-194 minus statSync)
// ---------------------------------------------------------------------------

/// The slim pure verdict of the reuse gate (RESEARCH Open Q2): the detected
/// binary path + the CLEAN (normalized) version. The Phase-56 adapter `statSync`s
/// `path` and constructs the final `ReuseHit` (`binary_path` + `version` +
/// `detected_source`). NO `statSync` here.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReuseCandidate {
    pub path: String,
    pub version: String,
}

/// The pure REUSE-03 gate: given a catalog entry + a detected-agent record +
/// its canonical map, decide whether this is a reuse candidate — WITHOUT the
/// host `statSync` (that stays in the Phase-56 adapter). Returns `Some` with the
/// path + clean version on a full match, `None` on any non-reuse condition.
///
/// Gate order is byte-for-byte with `tryReuse` (detect.ts:166-179):
/// 1. `compatibility_window` nonempty (Pitfall 4 — `""` treated as absent),
/// 2. `status == "healthy"`,
/// 3. `is_at_managed_path` (NOT canonical-gated — any catalog tool at its managed
///    path, Pitfall 5),
/// 4. `semver_shim::valid(version)` yields the CLEAN version (Pitfall 6),
/// 5. `semver_shim::satisfies(clean, window)`.
#[must_use]
pub fn reuse_gate(
    entry: &CatalogEntry,
    detected: &DetectedAgent,
    canonical: Option<&str>,
    gsd_system_path: &str,
    agent_home: &str,
) -> Option<ReuseCandidate> {
    // Gate 1: window present (Pitfall 4 — empty string is absent).
    let window = entry
        .compatibility_window
        .as_deref()
        .filter(|w| !w.is_empty())?;
    // Gate 2: healthy.
    if detected.status != "healthy" {
        return None;
    }
    // Gate 3: at its managed path (isAtManagedPath — not canonical-gated).
    if !is_at_managed_path(
        entry,
        &detected.path,
        canonical,
        gsd_system_path,
        agent_home,
    ) {
        return None;
    }
    // Gate 4: version parses (clean/normalized form, Pitfall 6).
    let version = semver_shim::valid(&detected.version)?;
    // Gate 5: version in window.
    if !semver_shim::satisfies(&version, window) {
        return None;
    }
    Some(ReuseCandidate {
        path: detected.path.clone(),
        version,
    })
}

// ---------------------------------------------------------------------------
// Remediate gate (pure port of tryRemediate, detect.ts:202-224)
// ---------------------------------------------------------------------------

/// Which trigger fired the remediate gate — the discriminant of the two paths.
/// Port of the TS `reason: "broken" | "path-mismatch"` union (detect.ts:99).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RemediateReason {
    /// detect cache reports `status == "broken"`.
    Broken,
    /// `status == "healthy"` but the resolved path != the canonical path.
    PathMismatch,
}

impl RemediateReason {
    /// The lowercase reason string the TS `RemediateHit.reason` carries.
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            RemediateReason::Broken => "broken",
            RemediateReason::PathMismatch => "path-mismatch",
        }
    }
}

/// The pure REMEDIATE-04 verdict. Port of `RemediateHit` (detect.ts:99-104):
/// `detected_version` carries the CLEAN currently-installed version for a healthy
/// path-mismatch (so migration can preserve it), `None` for a broken install.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RemediateHit {
    pub reason: RemediateReason,
    pub detected_path: String,
    pub canonical_path: String,
    pub detected_version: Option<String>,
}

/// The pure REMEDIATE-04 gate. CANONICAL-GATED (Pitfall 5): `canonical` is `None`
/// for an id without a `CANONICAL_PATHS` entry → not a remediate candidate.
/// Port of `tryRemediate` (detect.ts:202-224):
/// - `status == "broken"` → broken hit (`detected_version = None`),
/// - `status == "healthy"` AND NOT `is_canonical_agent_path` → path-mismatch hit
///   (`detected_version = semver_shim::valid(version)`),
/// - else (healthy at canonical) → `None`.
#[must_use]
pub fn remediate_gate(
    entry: &CatalogEntry,
    detected: &DetectedAgent,
    canonical: Option<&str>,
    gsd_system_path: &str,
) -> Option<RemediateHit> {
    // Canonical-gated: an id without a canonical entry is not a candidate.
    let canonical = canonical?;
    if detected.status == "broken" {
        return Some(RemediateHit {
            reason: RemediateReason::Broken,
            detected_path: detected.path.clone(),
            canonical_path: canonical.to_string(),
            detected_version: None,
        });
    }
    if detected.status == "healthy"
        && !is_canonical_agent_path(entry, &detected.path, canonical, gsd_system_path)
    {
        return Some(RemediateHit {
            reason: RemediateReason::PathMismatch,
            detected_path: detected.path.clone(),
            canonical_path: canonical.to_string(),
            // Normalized (semver.valid → clean version or None).
            detected_version: semver_shim::valid(&detected.version),
        });
    }
    None
}

// ---------------------------------------------------------------------------
// Presence gate (pure port of detectPresence, detect.ts:248-275)
// ---------------------------------------------------------------------------

/// The pure presence verdict for `agentlinux list`. Port of `PresenceHit`
/// (detect.ts:241-246): `version` is the CLEAN version (or `None`), `canonical`
/// = at its managed path, `adoptable` = `canonical` AND window-nonempty AND
/// version-in-window.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PresenceHit {
    pub version: Option<String>,
    pub path: String,
    pub canonical: bool,
    pub adoptable: bool,
}

/// The pure presence gate. Port of `detectPresence` (detect.ts:248-275):
/// - `source_kind == "mcp"` → `None` (no PATH binary),
/// - detected `status != "healthy"` (incl. broken) → `None`,
/// - else: `canonical = is_at_managed_path(...)`, `version = valid(version)`,
///   `adoptable = canonical && window-nonempty (Pitfall 4) && version.is_some()
///   && satisfies(version, window)`.
#[must_use]
pub fn presence_gate(
    entry: &CatalogEntry,
    detected: &DetectedAgent,
    canonical: Option<&str>,
    gsd_system_path: &str,
    agent_home: &str,
) -> Option<PresenceHit> {
    // MCP entries have no PATH binary — presence is a client-config registration
    // the overlay does not detect. Guard so a stray mcp cache entry is never
    // mislabeled as a present-but-migrate binary.
    if entry.source_kind.as_deref() == Some("mcp") {
        return None;
    }
    if detected.status != "healthy" {
        return None;
    }
    let canonical_at = is_at_managed_path(
        entry,
        &detected.path,
        canonical,
        gsd_system_path,
        agent_home,
    );
    // Normalized (semver.valid → clean version or None).
    let version = semver_shim::valid(&detected.version);
    // adoptable replicates the reuse gate's non-location gates: window present
    // (Pitfall 4 — `!!` truthiness, empty string is absent) + version in window.
    let adoptable = canonical_at
        && entry
            .compatibility_window
            .as_deref()
            .is_some_and(|w| !w.is_empty())
        && version.is_some()
        && version.as_deref().is_some_and(|v| {
            semver_shim::satisfies(v, entry.compatibility_window.as_deref().unwrap_or(""))
        });
    Some(PresenceHit {
        version,
        path: detected.path.clone(),
        canonical: canonical_at,
        adoptable,
    })
}

#[cfg(test)]
mod tests {
    //! Golden corpus — the pre-statSync deterministic rows from
    //! `plugin/cli/test/adopt.test.ts` + `list-presence.test.ts` (the parity
    //! oracles). Fixtures mirror those test catalogs verbatim.
    use super::*;

    // Canonical map values, byte-identical to detect.ts:16-28 (duplicated here as
    // params — Phase-57 consolidation). Agent home defaults to /home/agent.
    const CLAUDE_CANONICAL: &str = "/home/agent/.local/bin/claude";
    const GSD_CANONICAL: &str = "/home/agent/.npm-global/bin/gsd-core";
    const GSD_SYSTEM_PATH: &str = "/home/agent/.claude/gsd-core/VERSION";
    const AGENT_HOME: &str = "/home/agent";

    /// Build a `CatalogEntry` from the adopt/list-presence fixtures.
    fn entry(id: &str, source_kind: &str, window: Option<&str>) -> CatalogEntry {
        let mut json = serde_json::json!({
            "id": id,
            "pinned_version": "1.0.0",
            "source_kind": source_kind,
        });
        if let Some(w) = window {
            json["compatibility_window"] = serde_json::json!(w);
        }
        serde_json::from_value(json).expect("fixture entry deserializes")
    }

    /// Build a `DetectedAgent` cache record.
    fn detected(id: &str, status: &str, path: &str, version: &str) -> DetectedAgent {
        DetectedAgent {
            id: id.to_string(),
            status: status.to_string(),
            path: path.to_string(),
            version: version.to_string(),
        }
    }

    // --- is_canonical_agent_path (detect.ts:32-38) ---

    #[test]
    fn canonical_path_matches_exact_or_gsd_system_path() {
        let claude = entry("claude-code", "script", Some(">=2.0.0 <3.0.0"));
        assert!(is_canonical_agent_path(
            &claude,
            CLAUDE_CANONICAL,
            CLAUDE_CANONICAL,
            GSD_SYSTEM_PATH
        ));
        // gsd's dual presence: the deployed-system VERSION file is canonical.
        let gsd = entry("gsd", "script", Some(">=1.37.0 <2.0.0"));
        assert!(is_canonical_agent_path(
            &gsd,
            GSD_SYSTEM_PATH,
            GSD_CANONICAL,
            GSD_SYSTEM_PATH
        ));
        // The gsd-system-path special case is gsd-only.
        assert!(!is_canonical_agent_path(
            &claude,
            GSD_SYSTEM_PATH,
            CLAUDE_CANONICAL,
            GSD_SYSTEM_PATH
        ));
    }

    // --- managed_bin_dir / is_managed_path (detect.ts:51-68) ---

    #[test]
    fn managed_bin_dir_by_source_kind() {
        assert_eq!(
            managed_bin_dir(&entry("x", "npm", None), AGENT_HOME).as_deref(),
            Some("/home/agent/.npm-global/bin")
        );
        assert_eq!(
            managed_bin_dir(&entry("x", "binary", None), AGENT_HOME).as_deref(),
            Some("/home/agent/.local/bin")
        );
        assert_eq!(
            managed_bin_dir(&entry("x", "script", None), AGENT_HOME).as_deref(),
            Some("/home/agent/.local/bin")
        );
        // mcp/other → None (no PATH binary).
        assert_eq!(managed_bin_dir(&entry("x", "mcp", None), AGENT_HOME), None);
    }

    // --- reuse_gate ---

    // adopt.test.ts:317-336 — gsd@system-path in-window → reuse candidate.
    #[test]
    fn reuse_gsd_at_system_path_in_window() {
        let gsd = entry("gsd", "script", Some(">=1.37.0 <2.0.0"));
        let det = detected("gsd", "healthy", GSD_SYSTEM_PATH, "1.37.1");
        let got = reuse_gate(&gsd, &det, Some(GSD_CANONICAL), GSD_SYSTEM_PATH, AGENT_HOME);
        assert_eq!(
            got,
            Some(ReuseCandidate {
                path: GSD_SYSTEM_PATH.to_string(),
                version: "1.37.1".to_string(),
            })
        );
    }

    // adopt.test.ts:194-203 — gsd 1.36.0 out-of-window → skipped (None).
    #[test]
    fn reuse_gsd_out_of_window_skipped() {
        let gsd = entry("gsd", "script", Some(">=1.37.0 <2.0.0"));
        let det = detected("gsd", "healthy", GSD_SYSTEM_PATH, "1.36.0");
        assert_eq!(
            reuse_gate(&gsd, &det, Some(GSD_CANONICAL), GSD_SYSTEM_PATH, AGENT_HOME),
            None
        );
    }

    // adopt.test.ts:273-297 — non-canonical rtk at its managed ~/.local/bin
    // in-window → reuse candidate (generalized reuse, Pitfall 5).
    #[test]
    fn reuse_rtk_non_canonical_at_managed_path() {
        let rtk = entry("rtk", "binary", Some(">=0.42.0 <0.43.0"));
        // AGENT_HOME/.local/bin/rtk → managed for a binary tool.
        let det = detected("rtk", "healthy", "/home/agent/.local/bin/rtk", "0.42.4");
        let got = reuse_gate(&rtk, &det, None, GSD_SYSTEM_PATH, AGENT_HOME);
        assert_eq!(
            got,
            Some(ReuseCandidate {
                path: "/home/agent/.local/bin/rtk".to_string(),
                version: "0.42.4".to_string(),
            })
        );
    }

    // adopt.test.ts:299-315 — rtk at a NON-managed path (/usr/bin) → skipped.
    #[test]
    fn reuse_rtk_non_managed_path_skipped() {
        let rtk = entry("rtk", "binary", Some(">=0.42.0 <0.43.0"));
        let det = detected("rtk", "healthy", "/usr/bin/rtk", "0.42.4");
        assert_eq!(
            reuse_gate(&rtk, &det, None, GSD_SYSTEM_PATH, AGENT_HOME),
            None
        );
    }

    // Pitfall 4 — empty compatibility_window → not a reuse candidate.
    #[test]
    fn reuse_empty_window_skipped() {
        let e = entry("gsd", "script", Some(""));
        let det = detected("gsd", "healthy", GSD_SYSTEM_PATH, "1.37.1");
        assert_eq!(
            reuse_gate(&e, &det, Some(GSD_CANONICAL), GSD_SYSTEM_PATH, AGENT_HOME),
            None
        );
    }

    // broken status → not a reuse candidate.
    #[test]
    fn reuse_broken_skipped() {
        let gsd = entry("gsd", "script", Some(">=1.37.0 <2.0.0"));
        let det = detected("gsd", "broken", GSD_SYSTEM_PATH, "1.37.1");
        assert_eq!(
            reuse_gate(&gsd, &det, Some(GSD_CANONICAL), GSD_SYSTEM_PATH, AGENT_HOME),
            None
        );
    }

    // --- remediate_gate ---

    // adopt.test.ts:206-227 — claude at npm-global path (healthy) → path-mismatch,
    // detected_version = clean version.
    #[test]
    fn remediate_claude_npm_global_path_mismatch() {
        let claude = entry("claude-code", "script", Some(">=2.0.0 <3.0.0"));
        let det = detected(
            "claude-code",
            "healthy",
            "/home/agent/.npm-global/bin/claude",
            "2.1.98",
        );
        let got = remediate_gate(&claude, &det, Some(CLAUDE_CANONICAL), GSD_SYSTEM_PATH);
        assert_eq!(
            got,
            Some(RemediateHit {
                reason: RemediateReason::PathMismatch,
                detected_path: "/home/agent/.npm-global/bin/claude".to_string(),
                canonical_path: CLAUDE_CANONICAL.to_string(),
                detected_version: Some("2.1.98".to_string()),
            })
        );
    }

    // broken install → broken remediate hit, detected_version None.
    #[test]
    fn remediate_broken_hit_no_version() {
        let claude = entry("claude-code", "script", Some(">=2.0.0 <3.0.0"));
        let det = detected("claude-code", "broken", CLAUDE_CANONICAL, "2.1.98");
        let got = remediate_gate(&claude, &det, Some(CLAUDE_CANONICAL), GSD_SYSTEM_PATH);
        assert_eq!(
            got,
            Some(RemediateHit {
                reason: RemediateReason::Broken,
                detected_path: CLAUDE_CANONICAL.to_string(),
                canonical_path: CLAUDE_CANONICAL.to_string(),
                detected_version: None,
            })
        );
    }

    // healthy at canonical → no remediate (None).
    #[test]
    fn remediate_healthy_canonical_none() {
        let claude = entry("claude-code", "script", Some(">=2.0.0 <3.0.0"));
        let det = detected("claude-code", "healthy", CLAUDE_CANONICAL, "2.1.98");
        assert_eq!(
            remediate_gate(&claude, &det, Some(CLAUDE_CANONICAL), GSD_SYSTEM_PATH),
            None
        );
    }

    // canonical-gated (Pitfall 5): an id without a canonical entry is never a
    // remediate candidate even when broken.
    #[test]
    fn remediate_no_canonical_entry_none() {
        let rtk = entry("rtk", "binary", Some(">=0.42.0 <0.43.0"));
        let det = detected("rtk", "broken", "/usr/bin/rtk", "0.42.4");
        assert_eq!(remediate_gate(&rtk, &det, None, GSD_SYSTEM_PATH), None);
    }

    // gsd at system VERSION path (healthy) is canonical → no path-mismatch.
    #[test]
    fn remediate_gsd_system_path_is_canonical_none() {
        let gsd = entry("gsd", "script", Some(">=1.37.0 <2.0.0"));
        let det = detected("gsd", "healthy", GSD_SYSTEM_PATH, "1.37.1");
        assert_eq!(
            remediate_gate(&gsd, &det, Some(GSD_CANONICAL), GSD_SYSTEM_PATH),
            None
        );
    }

    // --- presence_gate ---

    // list-presence.test.ts:92-104 — healthy at canonical in-window → present +
    // canonical + adoptable.
    #[test]
    fn presence_healthy_canonical_in_window_adoptable() {
        let gsd = entry("gsd", "script", Some(">=1.37.0 <2.0.0"));
        let det = detected("gsd", "healthy", GSD_SYSTEM_PATH, "1.37.1");
        let got = presence_gate(&gsd, &det, Some(GSD_CANONICAL), GSD_SYSTEM_PATH, AGENT_HOME);
        assert_eq!(
            got,
            Some(PresenceHit {
                version: Some("1.37.1".to_string()),
                path: GSD_SYSTEM_PATH.to_string(),
                canonical: true,
                adoptable: true,
            })
        );
    }

    // list-presence.test.ts:122-133 — broken → NOT present (None).
    #[test]
    fn presence_broken_is_none() {
        let gsd = entry("gsd", "script", Some(">=1.37.0 <2.0.0"));
        let det = detected("gsd", "broken", GSD_SYSTEM_PATH, "1.37.1");
        assert_eq!(
            presence_gate(&gsd, &det, Some(GSD_CANONICAL), GSD_SYSTEM_PATH, AGENT_HOME),
            None
        );
    }

    // list-presence.test.ts:135-151 — healthy at NON-canonical path → present but
    // NOT canonical (migration candidate), and NOT adoptable.
    #[test]
    fn presence_non_canonical_present_not_canonical() {
        let gsd = entry("gsd", "script", Some(">=1.37.0 <2.0.0"));
        let det = detected(
            "gsd",
            "healthy",
            "/home/agent/.npm-global/bin/gsd",
            "1.37.1",
        );
        let got = presence_gate(&gsd, &det, Some(GSD_CANONICAL), GSD_SYSTEM_PATH, AGENT_HOME);
        assert_eq!(
            got,
            Some(PresenceHit {
                version: Some("1.37.1".to_string()),
                path: "/home/agent/.npm-global/bin/gsd".to_string(),
                canonical: false,
                adoptable: false,
            })
        );
    }

    // Pitfall 4 — compatibility_window "" → present + canonical but NOT adoptable.
    #[test]
    fn presence_empty_window_not_adoptable() {
        let gsd = entry("gsd", "script", Some(""));
        let det = detected("gsd", "healthy", GSD_SYSTEM_PATH, "1.37.1");
        let got = presence_gate(&gsd, &det, Some(GSD_CANONICAL), GSD_SYSTEM_PATH, AGENT_HOME);
        assert_eq!(
            got,
            Some(PresenceHit {
                version: Some("1.37.1".to_string()),
                path: GSD_SYSTEM_PATH.to_string(),
                canonical: true,
                adoptable: false,
            })
        );
    }

    // mcp source_kind → None (no PATH binary).
    #[test]
    fn presence_mcp_is_none() {
        let e = entry("context7", "mcp", Some(">=1.0.0 <2.0.0"));
        let det = detected("context7", "healthy", "/anywhere", "1.5.0");
        assert_eq!(
            presence_gate(&e, &det, None, GSD_SYSTEM_PATH, AGENT_HOME),
            None
        );
    }
}

#[cfg(test)]
mod proptests {
    //! Property tests (TEST-01) — totality of each decider (threats T-55-04 /
    //! T-55-05): any `(entry, detected)` yields an `Option`, never panics.
    use super::*;
    use proptest::prelude::*;

    fn arb_entry() -> impl Strategy<Value = CatalogEntry> {
        (
            "[a-z-]{0,8}",
            proptest::option::of(prop_oneof![
                Just("npm".to_string()),
                Just("binary".to_string()),
                Just("script".to_string()),
                Just("mcp".to_string()),
            ]),
            proptest::option::of(prop_oneof![
                Just("".to_string()),
                Just(">=1.0.0 <2.0.0".to_string()),
                Just("^1.0".to_string()),
            ]),
        )
            .prop_map(|(id, source_kind, window)| {
                let mut json = serde_json::json!({ "id": id, "pinned_version": "1.0.0" });
                if let Some(sk) = source_kind {
                    json["source_kind"] = serde_json::json!(sk);
                }
                if let Some(w) = window {
                    json["compatibility_window"] = serde_json::json!(w);
                }
                serde_json::from_value(json).expect("prop entry deserializes")
            })
    }

    fn arb_detected() -> impl Strategy<Value = DetectedAgent> {
        (
            "[a-z-]{0,8}",
            prop_oneof![
                Just("healthy".to_string()),
                Just("broken".to_string()),
                Just("absent".to_string()),
                "[a-z]{0,6}".prop_map(|s| s),
            ],
            "[a-z/.0-9-]{0,30}",
            prop_oneof![
                "[0-9]{1,2}\\.[0-9]{1,2}\\.[0-9]{1,2}".prop_map(|s| s),
                "[a-z.0-9]{0,8}".prop_map(|s| s),
            ],
        )
            .prop_map(|(id, status, path, version)| DetectedAgent {
                id,
                status,
                path,
                version,
            })
    }

    proptest! {
        #[test]
        fn all_gates_total(
            entry in arb_entry(),
            det in arb_detected(),
            canonical in proptest::option::of("[a-z/.0-9-]{0,30}"),
            gsd_system_path in "[a-z/.0-9-]{0,30}",
            agent_home in "[a-z/.0-9-]{0,20}",
        ) {
            // Each call returning without unwinding IS the totality proof.
            let _ = reuse_gate(&entry, &det, canonical.as_deref(), &gsd_system_path, &agent_home);
            let _ = remediate_gate(&entry, &det, canonical.as_deref(), &gsd_system_path);
            let _ = presence_gate(&entry, &det, canonical.as_deref(), &gsd_system_path, &agent_home);
            let _ = is_at_managed_path(&entry, &det.path, canonical.as_deref(), &gsd_system_path, &agent_home);
        }
    }
}
