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
/// real /opt tree. Crate-visible rather than private for the second reason too: a
/// diagnostic has to be able to NAME the directory an operator should go look at
/// — "cannot read the install records" is not actionable without the path.
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
            // Name the FILE in the parse error. Serde reports "expected value at
            // line 1 column 1", which for a zero-length record left by a power
            // loss says nothing about which record or where to find it.
            let s: Sentinel = serde_json::from_str(&data).map_err(|e| {
                std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    format!("{} is not a valid install record: {e}", path.display()),
                )
            })?;
            Ok(Some(s))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(std::io::Error::new(
            e.kind(),
            format!("cannot read {}: {e}", path.display()),
        )),
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
///
/// # One bad record does not hide the others
/// An unreadable or unparseable `<id>.json` is SKIPPED with a loud warning, not
/// propagated. It used to abort the whole listing through the `?`, and the three
/// callers each failed differently and badly: `list` swallowed the error into an
/// empty vec and told the operator nothing was installed, `upgrade` exited 1, and
/// `rewire::reconcile_cross_wiring` returned silently — so installing an agent
/// appeared to succeed while the cross-agent wiring never ran. One zero-length
/// file from a power loss disabled all three, for every agent, permanently: the
/// same record failed the same way on every subsequent run.
///
/// Skipping is the right default because these files are INDEPENDENT records.
/// Nine good sentinels are still nine correct answers, and the warning names the
/// file and the fix so the tenth is recoverable.
pub fn list_sentinels() -> std::io::Result<Vec<Sentinel>> {
    let dir = installed_dir();
    let entries = match std::fs::read_dir(&dir) {
        Ok(rd) => rd,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(e) => return Err(e),
    };
    let mut out = Vec::new();
    for entry in entries {
        // A per-entry stat failure skips that entry, for the same reason a corrupt
        // record does: one unreadable directory entry must not make every other
        // agent invisible.
        let entry = match entry {
            Ok(e) => e,
            Err(e) => {
                crate::plog!(
                    "agentlinux: skipping an unreadable entry in {} ({e})",
                    dir.display()
                );
                continue;
            }
        };
        let name = entry.file_name();
        let name = name.to_string_lossy();
        // Only `<id>.json`. A concurrent write's tmpfile is `.<id>.json.<pid>.…`
        // (see `sysio::mktemp_in`), which does not end in `.json`, so this
        // suffix test already excludes it — no separate tmp guard needed.
        let Some(id) = name.strip_suffix(".json") else {
            continue;
        };
        if id.is_empty() {
            continue;
        }
        match read_sentinel(id) {
            Ok(Some(s)) => out.push(s),
            // Raced with a `remove` between read_dir and open — not an error.
            Ok(None) => {}
            Err(e) => crate::plog!(
                "agentlinux: skipping unreadable install record {} ({e}). \
                 `{id}` will not appear as installed; delete that file to clear \
                 the warning, then re-install `{id}` if you still need it.",
                dir.join(format!("{id}.json")).display()
            ),
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

    /// An EMPTY `AGENTLINUX_STATE_DIR` is not a directory. `replace match guard
    /// !v.is_empty() with true` survived: with it the sentinel store resolves to
    /// `PathBuf::from("")` — a relative path in whatever the process's cwd
    /// happens to be — instead of the real `/opt` store. Every verb then reads
    /// and writes a different set of sentinels than the one on the host.
    #[test]
    fn an_empty_state_dir_seam_falls_back_to_the_real_store() {
        let mut env_scope = crate::test_support::EnvScope::new();

        env_scope.set("AGENTLINUX_STATE_DIR", "/tmp/fixture-state");
        assert_eq!(installed_dir(), PathBuf::from("/tmp/fixture-state"));

        env_scope.set("AGENTLINUX_STATE_DIR", "");
        assert_eq!(
            installed_dir(),
            PathBuf::from(DEFAULT_INSTALLED_DIR),
            "an EMPTY seam must fall back, not resolve to a relative path"
        );

        env_scope.unset("AGENTLINUX_STATE_DIR");
        assert_eq!(installed_dir(), PathBuf::from(DEFAULT_INSTALLED_DIR));
    }

    /// Every sentinel timestamp carries this shape, and `agentlinux upgrade`
    /// and the reuse audit both read them back. Replacing the function with ""
    /// or junk survived; either makes every `installed_at` unparseable.
    #[test]
    fn a_timestamp_has_the_iso8601_shape_the_sentinels_carry() {
        let t = now_iso8601();
        assert_eq!(t.len(), 20, "YYYY-MM-DDTHH:MM:SSZ is 20 bytes, got {t:?}");
        assert!(t.ends_with('Z'), "must be UTC-suffixed, got {t:?}");
        assert_eq!(&t[4..5], "-");
        assert_eq!(&t[10..11], "T");
        assert_eq!(&t[13..14], ":");
        // A plausible year rather than 1970 — the epoch read must reach through.
        let year: u32 = t[0..4].parse().expect("the year must be numeric");
        assert!((2020..2100).contains(&year), "implausible year in {t:?}");
    }

    /// ENOENT is "not installed"; every other I/O error is a real failure.
    /// Three of these guards had `with true` survive — collapsing the two, so a
    /// permission or type error silently reads as "this agent is not installed"
    /// and `remove` reports success having deleted nothing.
    #[test]
    fn absent_is_distinguished_from_unreadable_on_every_store_path() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let dir = tempdir().unwrap();
        env_scope.set("AGENTLINUX_STATE_DIR", dir.path());

        // read: absent → Ok(None); present-but-unreadable → Err.
        assert!(read_sentinel("nosuch").unwrap().is_none());
        std::fs::create_dir(dir.path().join("broken.json")).unwrap();
        assert!(
            read_sentinel("broken").is_err(),
            "a directory where a sentinel belongs is a failure, not an absence"
        );

        // delete: absent → Ok (idempotent); undeletable → Err.
        assert!(delete_sentinel("nosuch").is_ok(), "delete is idempotent");
        assert!(
            delete_sentinel("broken").is_err(),
            "a sentinel that cannot be removed must not report success"
        );
        std::fs::remove_dir(dir.path().join("broken.json")).unwrap();

        // list: missing dir → empty, not an error.
        let missing = dir.path().join("not-created-yet");
        env_scope.set("AGENTLINUX_STATE_DIR", &missing);
        assert_eq!(list_sentinels().unwrap().len(), 0);

        // list: state dir that is a FILE → a real error, not an empty store.
        let as_file = dir.path().join("state-is-a-file");
        std::fs::write(&as_file, b"not a dir").unwrap();
        env_scope.set("AGENTLINUX_STATE_DIR", &as_file);
        assert!(
            list_sentinels().is_err(),
            "an unreadable store must not read as an empty one — that would let \
             upgrade and list silently report nothing installed"
        );
    }

    /// The store's modes are the provisioner's: 0755 on the directory, 0644 on
    /// each sentinel. `replace set_mode with ()` survived, which leaves both to
    /// the ambient umask — and the unprivileged install user has to read what
    /// root wrote.
    #[test]
    fn the_store_and_its_sentinels_carry_explicit_modes() {
        use std::os::unix::fs::PermissionsExt;
        let mut env_scope = crate::test_support::EnvScope::new();
        let base = tempdir().unwrap();
        // A dir the write path must CREATE, so the 0755 is ours and not tempfile's.
        let dir = base.path().join("installed.d");
        env_scope.set("AGENTLINUX_STATE_DIR", &dir);

        // A RESTRICTIVE umask, deliberately. Under the default 022 a plain
        // `create_dir_all` already yields 0755, so `replace set_mode with ()`
        // survived — the assertion was satisfied by the ambient umask rather
        // than by the code. That is precisely the coin flip the explicit mode
        // exists to remove: root provisions with whatever umask it inherited,
        // and the unprivileged install user still has to read the store.
        let prev = unsafe { nix::libc::umask(0o077) };
        write_sentinel(&Sentinel::new(
            "rtk".into(),
            "0.42.4".into(),
            "curated".into(),
            false,
        ))
        .unwrap();
        unsafe { nix::libc::umask(prev) };

        let dir_mode = std::fs::metadata(&dir).unwrap().permissions().mode() & 0o777;
        assert_eq!(dir_mode, 0o755, "the store dir must be traversable");
        let file_mode = std::fs::metadata(dir.join("rtk.json"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(file_mode, 0o644, "the install user must be able to read it");
    }

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

    // One corrupt record must not hide the others. A zero-length `<id>.json` from
    // a power loss used to abort the whole listing, which made `list` report
    // nothing installed, `upgrade` exit 1, and cross-agent wiring silently skip —
    // for EVERY agent, on every subsequent run.
    #[test]
    fn one_corrupt_record_does_not_hide_the_healthy_ones() {
        let _g = crate::test_support::EnvScope::new();
        let dir = tempdir().unwrap();
        std::env::set_var("AGENTLINUX_STATE_DIR", dir.path());

        write_sentinel(&Sentinel::new(
            "gsd".into(),
            "1.7.0".into(),
            "curated".into(),
            false,
        ))
        .unwrap();
        write_sentinel(&Sentinel::new(
            "rtk".into(),
            "2.0.0".into(),
            "latest".into(),
            false,
        ))
        .unwrap();
        // The power-loss shape: present, zero-length, unparseable.
        std::fs::write(dir.path().join("claude-code.json"), b"").unwrap();
        // And the other shape: valid JSON, wrong schema.
        std::fs::write(dir.path().join("playwright.json"), b"{\"nope\":1}").unwrap();

        let mut ids: Vec<String> = list_sentinels()
            .unwrap()
            .into_iter()
            .map(|s| s.id)
            .collect();
        ids.sort();
        assert_eq!(
            ids,
            vec!["gsd".to_string(), "rtk".to_string()],
            "healthy records must survive a corrupt sibling"
        );

        std::env::remove_var("AGENTLINUX_STATE_DIR");
    }

    // The parse error names the FILE. Serde alone reports "expected value at line
    // 1 column 1", which does not say which record or where to find it.
    #[test]
    fn a_corrupt_record_error_names_the_file() {
        let _g = crate::test_support::EnvScope::new();
        let dir = tempdir().unwrap();
        std::env::set_var("AGENTLINUX_STATE_DIR", dir.path());
        std::fs::write(dir.path().join("broken.json"), b"{not json").unwrap();

        let err = read_sentinel("broken").unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("broken.json"), "msg={msg}");
        assert!(msg.contains("not a valid install record"), "msg={msg}");

        std::env::remove_var("AGENTLINUX_STATE_DIR");
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
