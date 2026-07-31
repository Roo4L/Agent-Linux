//! sentinel.rs — per-agent install-record read/write (I/O boundary).
//!
//! The install-record store. Per-agent files under
//! `<state_dir>/installed.d/<id>.json`. The write is ATOMIC (tmp + `rename(2)`)
//! per POSIX so a timeout-killed op can never leave a torn sentinel the
//! next op trusts.
//!
//! # Full write-path shape
//! The pure `agentlinux_core::types::Sentinel` is a lean 4-field READ subset
//! (id/version/source/sticky). The bin needs the FULL write-path shape
//! (`installed_at`, `status`, `binary_path`, `detected_source`, `reused_at`,
//! `remediated_at`, `decline_reason`, …) to WRITE sentinels — field names
//! byte-identical to `types.ts:57-89` so the SAME `installed.d/<id>.json`
//! round-trips with no migration ("What is NOT yet in agentlinux-core",
//! item 2).
//!
//! # Env seam
//! `AGENTLINUX_STATE_DIR` overrides the default `/opt/agentlinux/state/installed.d`
//!  — the bats seam. Resolved lazily on each call so a test
//! that mutates the env after import still takes effect.
//!
//! # `#[serde(skip_serializing_if)]` parity
//! The TS `JSON.stringify(entry, null, 2)` omits `undefined` fields entirely. The
//! optional fields carry `skip_serializing_if = "Option::is_none"` so a sentinel
//! with no `status`/`binary_path`/… serializes to the SAME bytes the TS writes
//! (no `"status": null` noise) — the round-trip is byte-stable.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

const DEFAULT_INSTALLED_DIR: &str = "/opt/agentlinux/state/installed.d";

/// Resolve the installed.d dir lazily: `$AGENTLINUX_STATE_DIR` (bats seam) else
/// the default. Port of `installedDir()` (sentinel.ts:24-26).
///
/// `pub(crate)` because EVERY reader of installed.d must come through here.
/// `--purge` used to read a hard-coded `/opt/agentlinux/state/installed.d`, so a
/// bats fixture that redirects state — which install/remove/list all obey — was
/// ignored by the one verb that deletes things, which then walked the host's
/// real /opt tree.
pub(crate) fn installed_dir() -> PathBuf {
    match std::env::var("AGENTLINUX_STATE_DIR") {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => PathBuf::from(DEFAULT_INSTALLED_DIR),
    }
}

/// The full write-path sentinel — field names byte-identical to `types.ts:57-89`.
///
/// The four core fields (`id`/`version`/`source`/`sticky`) are always present; the
/// rest are `Option` and skipped when `None` so the serialized JSON matches the TS
/// `JSON.stringify` output (which omits `undefined`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Sentinel {
    pub id: String,
    pub version: String,
    /// `"curated" | "override" | "latest" | "pinned"`. Plain `String` (not an
    /// enum) so an inherited/unknown source round-trips, mirroring the core.
    pub source: String,
    pub sticky: bool,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub installed_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub decline_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub binary_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub detected_source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub reused_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub compatibility_window_at_reuse: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub remediated_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub remediate_failure_reason: Option<String>,
}

/// The current time as `YYYY-MM-DDTHH:MM:SSZ` — the format every sentinel
/// timestamp field (`installed_at`, `reused_at`, `remediated_at`) carries.
#[must_use]
pub fn now_iso8601() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    agentlinux_core::time::format_epoch_utc(secs)
}

/// Project the write-path sentinel down to the four fields the pure core reads.
/// A struct literal for the same reason as the catalog-entry projection: a field
/// added to the core type should break the build here, not panic at runtime.
impl From<&Sentinel> for agentlinux_core::types::Sentinel {
    fn from(s: &Sentinel) -> Self {
        Self {
            id: s.id.clone(),
            version: s.version.clone(),
            source: s.source.clone(),
            sticky: s.sticky,
        }
    }
}

impl Sentinel {
    /// Convenience constructor for the four required fields; all optional fields
    /// default to `None`. Callers set the optional fields fluently (the verb
    /// layer builds reused/pinned sentinels this way).
    #[must_use]
    pub fn new(id: String, version: String, source: String, sticky: bool) -> Self {
        Self {
            id,
            version,
            source,
            sticky,
            installed_at: None,
            status: None,
            decline_reason: None,
            binary_path: None,
            detected_source: None,
            reused_at: None,
            compatibility_window_at_reuse: None,
            remediated_at: None,
            remediate_failure_reason: None,
        }
    }
}

/// Read `<installed.d>/<id>.json`, or `None` when absent (ENOENT). Port of
/// `readSentinel`.
pub fn read_sentinel(id: &str) -> std::io::Result<Option<Sentinel>> {
    let path = installed_dir().join(format!("{id}.json"));
    match std::fs::read_to_string(&path) {
        Ok(data) => {
            let s: Sentinel = serde_json::from_str(&data)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
            Ok(Some(s))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e),
    }
}

/// Write a sentinel atomically. Modes 0755 (dir) / 0644 (file) mirror the
/// provisioner.
///
/// Goes through `sysio::write_file_atomic`, which is the careful implementation:
/// same-directory tmpfile, `sync_all` before the rename, mode set before
/// publication, and an RAII guard that unlinks the tmpfile on every error path.
/// This function used to hand-roll the sequence and skipped the fsync and the
/// cleanup, so a killed process left a stray `.json.tmp.<pid>` behind forever.
pub fn write_sentinel(entry: &Sentinel) -> std::io::Result<()> {
    let dir = installed_dir();
    std::fs::create_dir_all(&dir)?;
    set_mode(&dir, 0o755);
    let target = dir.join(format!("{}.json", entry.id));
    // 2-space pretty + a trailing newline.
    let body = format!("{}\n", serde_json::to_string_pretty(entry)?);
    crate::sysio::write_file_atomic(0o644, &target, body.as_bytes())
}

/// Delete `<installed.d>/<id>.json`, tolerating ENOENT (idempotent). Port of
/// `deleteSentinel`.
///
/// Consumed by the `remove` verb.
pub fn delete_sentinel(id: &str) -> std::io::Result<()> {
    let path = installed_dir().join(format!("{id}.json"));
    match std::fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e),
    }
}

/// List every sentinel under installed.d. Missing dir → empty (ENOENT-tolerant).
/// Port of `listSentinels`.
pub fn list_sentinels() -> std::io::Result<Vec<Sentinel>> {
    let dir = installed_dir();
    let entries = match std::fs::read_dir(&dir) {
        Ok(rd) => rd,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(e) => return Err(e),
    };
    let mut out = Vec::new();
    for entry in entries {
        let entry = entry?;
        let name = entry.file_name();
        let name = name.to_string_lossy();
        // Only `<id>.json`. A concurrent write's tmpfile is `.<id>.json.<pid>.…`
        // (see `sysio::mktemp_in`), which does not end in `.json`, so this
        // suffix test already excludes it — no separate tmp guard needed.
        if let Some(id) = name.strip_suffix(".json") {
            if id.is_empty() {
                continue;
            }
            if let Some(s) = read_sentinel(id)? {
                out.push(s);
            }
        }
    }
    Ok(out)
}

/// Set the unix mode on `path`, best-effort — a mode-set failure on a tmp dir a
/// test owns is non-fatal, and the atomic rename is the load-bearing guarantee.
fn set_mode(path: &std::path::Path, mode: u32) {
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode));
}

#[cfg(test)]
mod sentinel_tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn atomic_round_trip_write_then_read() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let dir = tempdir().unwrap();
        env_scope.set("AGENTLINUX_STATE_DIR", dir.path());

        let mut s = Sentinel::new("gsd".into(), "1.7.0".into(), "curated".into(), false);
        s.installed_at = Some("2026-07-28T00:00:00Z".into());
        s.status = Some("reused".into());
        s.binary_path = Some("/home/agent/.npm-global/bin/gsd-core".into());
        write_sentinel(&s).unwrap();

        let back = read_sentinel("gsd").unwrap().unwrap();
        assert_eq!(back, s);

        env_scope.unset("AGENTLINUX_STATE_DIR");
    }

    #[test]
    fn serialize_omits_none_fields_like_ts_json_stringify() {
        // A minimal (curated, non-sticky) sentinel with no optional fields must
        // serialize with NO `"status": null` etc. — byte-parity with the TS
        // JSON.stringify that drops `undefined`.
        let s = Sentinel::new("x".into(), "1.0.0".into(), "curated".into(), false);
        let json = serde_json::to_string_pretty(&s).unwrap();
        assert!(!json.contains("status"), "should omit None status: {json}");
        assert!(
            !json.contains("binary_path"),
            "should omit None binary_path"
        );
        // The four core fields ARE present.
        assert!(json.contains("\"id\": \"x\""));
        assert!(json.contains("\"sticky\": false"));
    }

    #[test]
    fn write_produces_trailing_newline() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let dir = tempdir().unwrap();
        env_scope.set("AGENTLINUX_STATE_DIR", dir.path());
        let s = Sentinel::new("x".into(), "1.0.0".into(), "curated".into(), false);
        write_sentinel(&s).unwrap();
        let body = std::fs::read_to_string(dir.path().join("x.json")).unwrap();
        assert!(body.ends_with("}\n"), "trailing newline expected: {body:?}");
        env_scope.unset("AGENTLINUX_STATE_DIR");
    }

    #[test]
    fn delete_is_enoent_tolerant_and_list_skips_missing() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let dir = tempdir().unwrap();
        env_scope.set("AGENTLINUX_STATE_DIR", dir.path());

        // Delete before any write — idempotent no-op.
        delete_sentinel("ghost").unwrap();
        // Empty dir → empty list.
        assert!(list_sentinels().unwrap().is_empty());

        let a = Sentinel::new("a".into(), "1.0.0".into(), "curated".into(), false);
        let b = Sentinel::new("b".into(), "2.0.0".into(), "latest".into(), true);
        write_sentinel(&a).unwrap();
        write_sentinel(&b).unwrap();
        let mut ids: Vec<String> = list_sentinels()
            .unwrap()
            .into_iter()
            .map(|s| s.id)
            .collect();
        ids.sort();
        assert_eq!(ids, vec!["a".to_string(), "b".to_string()]);

        delete_sentinel("a").unwrap();
        let ids: Vec<String> = list_sentinels()
            .unwrap()
            .into_iter()
            .map(|s| s.id)
            .collect();
        assert_eq!(ids, vec!["b".to_string()]);

        env_scope.unset("AGENTLINUX_STATE_DIR");
    }

    #[test]
    fn read_missing_is_none() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let dir = tempdir().unwrap();
        env_scope.set("AGENTLINUX_STATE_DIR", dir.path());
        assert!(read_sentinel("nope").unwrap().is_none());
        env_scope.unset("AGENTLINUX_STATE_DIR");
    }
}
