//! provision/log.rs — the installer transcript tee.
//!
//! The Bash entrypoint (`plugin/bin/agentlinux-install`) redirects its whole
//! stdout+stderr through `tee -a "$LOG_FILE"` so the
//! install produces a greppable transcript at `/var/log/agentlinux-install.log`
//! (overridable via `$AGENTLINUX_LOG`) ending with the
//! `agentlinux-install complete (transcript: …)` banner (INST-01).
//!
//! The Rust provisioner reproduces the OBSERVABLE the bats assert — the log file
//! with the start/step/complete banner lines and the no-EACCES / no-apt-error
//! contract — without a full FD-redirect (no `libc`/`tee` fork under musl). This
//! module owns a process-global append handle to the log file; `init` creates the
//! file (0644, like `install -m 0644 /dev/null "$LOG_FILE"`), and `line` writes a
//! message to BOTH stderr (so docker output still shows it) and the log file.
//!
//! The individual provisioner steps keep their `eprintln!` diagnostics on stderr;
//! the orchestrator routes the banner + per-step markers through `line` so the
//! transcript carries exactly the lines the acceptance oracle greps. A step that
//! fails aborts before the complete banner — so INST-01 stays fail-loud (a
//! partial install never writes "complete").

use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

/// The default install-log path (byte-identical to the Bash `LOG_FILE` default).
const DEFAULT_LOG: &str = "/var/log/agentlinux-install.log";

/// The process-global append handle. `None` until `init` succeeds (or if the log
/// could not be created — then `line` degrades to stderr-only, never a panic).
static LOG: OnceLock<Mutex<Option<File>>> = OnceLock::new();

/// Resolve the log path: `$AGENTLINUX_LOG` (nonempty) else the default.
#[must_use]
pub fn log_path() -> PathBuf {
    match std::env::var("AGENTLINUX_LOG") {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => PathBuf::from(DEFAULT_LOG),
    }
}

/// Create/truncate the install log (0644) and install the global handle. Mirrors
/// the Bash `install -m 0644 /dev/null "$LOG_FILE"` (a fresh transcript per run).
/// A creation failure (not root / read-only fs) is non-fatal: `line` falls back
/// to stderr-only, exactly like the Bash pre-tee diagnostics path. On failure it
/// emits ONE loud stderr warning (M-3) so the degraded-logging mode is visible
/// instead of silent. Returns the resolved path.
pub fn init() -> PathBuf {
    let path = log_path();
    let handle = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&path)
        .ok();
    // Best-effort 0644 (install -m 0644). Ignore a chmod failure.
    if handle.is_some() {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o644));
    } else {
        // M-3: do not degrade silently — one loud warning that the transcript
        // is unavailable and the run continues on stderr-only logging.
        eprintln!(
            "agentlinux provision: cannot create transcript {} — continuing with \
             stderr-only logging",
            path.display()
        );
    }
    let cell = LOG.get_or_init(|| Mutex::new(None));
    if let Ok(mut guard) = cell.lock() {
        *guard = handle;
    }
    path
}

/// Whether the transcript handle is live (the log file was created). `false` when
/// `init` could not open the log — the completion banner uses this so it never
/// names a transcript file that was never persisted (M-3).
#[must_use]
pub fn is_active() -> bool {
    LOG.get()
        .and_then(|cell| cell.lock().ok().map(|g| g.is_some()))
        .unwrap_or(false)
}

/// Write one transcript line to stderr AND (best-effort) the log file. Poison on
/// the mutex degrades to stderr-only — a logging lock is never worth aborting an
/// install for.
pub fn line(msg: &str) {
    eprintln!("{msg}");
    if let Some(cell) = LOG.get() {
        if let Ok(mut guard) = cell.lock() {
            if let Some(f) = guard.as_mut() {
                let _ = writeln!(f, "{msg}");
                let _ = f.flush();
            }
        }
    }
}

#[cfg(test)]
mod log_tests {
    use super::*;
    use std::io::Read;

    #[test]
    fn log_path_honors_env_else_default() {
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope.unset("AGENTLINUX_LOG");
        assert_eq!(log_path(), PathBuf::from(DEFAULT_LOG));
        env_scope.set("AGENTLINUX_LOG", "/tmp/al-test.log");
        assert_eq!(log_path(), PathBuf::from("/tmp/al-test.log"));
        env_scope.unset("AGENTLINUX_LOG");
    }

    #[test]
    fn init_creates_log_and_line_appends() {
        let mut env_scope = crate::test_support::EnvScope::new();
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("install.log");
        env_scope.set("AGENTLINUX_LOG", &path);

        let resolved = init();
        assert_eq!(resolved, path);
        line("agentlinux-install v0.3.6 starting");
        line("agentlinux-install complete (transcript: x)");

        let mut body = String::new();
        File::open(&path)
            .unwrap()
            .read_to_string(&mut body)
            .unwrap();
        assert!(body.contains("agentlinux-install v0.3.6 starting"));
        assert!(body.contains("agentlinux-install complete"));

        env_scope.unset("AGENTLINUX_LOG");
    }
}
