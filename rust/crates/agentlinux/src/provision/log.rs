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

/// The single-slot rotation suffix. `init` moves the previous transcript here
/// before starting a fresh one.
const PREV_SUFFIX: &str = ".prev";

/// Create the install log (0644) and install the global handle, rotating any
/// existing transcript to `<log>.prev` first.
///
/// Mirrors the Bash `install -m 0644 /dev/null "$LOG_FILE"` in giving each run a
/// fresh transcript — every "the log contains no <bad string>" assertion depends
/// on that. The rotation is what makes the fresh start non-destructive: the
/// obvious response to a failed install is to run it again, and a plain truncate
/// destroyed the failing run's evidence at exactly the moment someone went
/// looking for it. One slot is enough — the run you want is the one before this.
///
/// A creation failure (not root / read-only fs) is non-fatal: `line` falls back
/// to stderr-only, exactly like the Bash pre-tee diagnostics path. On failure it
/// emits ONE loud stderr warning so the degraded-logging mode is visible instead
/// of silent. Returns the resolved path.
pub fn init() -> PathBuf {
    let path = log_path();
    // Best-effort rotation: a rename failure (no prior log, read-only dir) must
    // not stop the run — the fresh-transcript open below is what matters.
    if path.exists() {
        let mut prev = path.clone().into_os_string();
        prev.push(PREV_SUFFIX);
        let _ = fs::rename(&path, PathBuf::from(prev));
    }
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

/// `eprintln!` that also reaches the install transcript.
///
/// Every provisioner diagnostic goes through this. The steps used to write with
/// bare `eprintln!`, so `[REMEDIATE-01]`, `[REUSE-WARN]`, the chown decision and
/// the purge removals reached the console and NOTHING reached the file — the
/// transcript held about eight orchestrator lines and none of the detail an
/// operator opens it for. Identical stderr behaviour to `eprintln!`, so the bats
/// assertions that grep the command's output are unaffected.
///
/// Outside a provision run (the `install`/`upgrade` verbs) no log handle exists
/// and this degrades to stderr-only on its own — no caller needs to know which
/// context it is in.
#[macro_export]
macro_rules! plog {
    ($($arg:tt)*) => {
        $crate::provision::log::line(&std::format!($($arg)*))
    };
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

/// A `Write` sink that tees to stderr AND (best-effort) the install transcript.
///
/// The verbs take their diagnostic sink as `&mut dyn Write` so a test can assert
/// what they printed (ADR-019 §1). Production wired `std::io::stderr()` into that
/// seam, which meant every line through it reached the console and NONE reached
/// the transcript — the same gap `plog!` closed for the steps that print
/// directly, reopened one layer up. Wiring this in stderr's place keeps both
/// properties: the seam is still injectable, and what goes through it in
/// production is still recorded.
///
/// Outside a provision run no log handle exists and this degrades to stderr-only
/// on its own, exactly like [`line`].
pub struct TranscriptErr;

/// The production error sink: stderr, teed to the transcript. Use this wherever a
/// verb wires its real `err` seam.
#[must_use]
pub fn err_sink() -> TranscriptErr {
    TranscriptErr
}

impl Write for TranscriptErr {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        // stderr is the contract (bats greps it); the transcript is best-effort.
        // A write_all + full-length return keeps callers off the partial-write
        // retry path for a sink that is really two sinks.
        std::io::stderr().write_all(buf)?;
        if let Some(cell) = LOG.get() {
            if let Ok(mut guard) = cell.lock() {
                if let Some(f) = guard.as_mut() {
                    let _ = f.write_all(buf);
                    let _ = f.flush();
                }
            }
        }
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        std::io::stderr().flush()
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn log_path_prefers_the_env_seam_over_the_default() {
        let mut env = crate::test_support::EnvScope::new();
        env.unset("AGENTLINUX_LOG");
        assert_eq!(log_path(), PathBuf::from(DEFAULT_LOG));
        // An EMPTY value falls back rather than resolving to "": a caller that
        // exports the seam unset would otherwise open a relative path named "".
        env.set("AGENTLINUX_LOG", "");
        assert_eq!(log_path(), PathBuf::from(DEFAULT_LOG));
        env.set("AGENTLINUX_LOG", "/tmp/al.log");
        assert_eq!(log_path(), PathBuf::from("/tmp/al.log"));
    }

    /// Both directions of `is_active`, in ONE test on purpose.
    ///
    /// `LOG` is process-global, so two tests asserting opposite states would be
    /// order-dependent — the exact defect that made `cmd/provision`'s
    /// "transcript unavailable" banner unassertable and forced `log_active` to
    /// become a `ProvisionDeps` field. Holding the `EnvScope` lock across both
    /// halves makes the sequence deterministic; `init` re-seats the handle on
    /// every call, so the order below is the whole contract.
    ///
    /// The `AGENTLINUX_LOG` pin is not optional: without it `init()` truncates
    /// `/var/log/agentlinux-install.log`, and the Docker and QEMU harnesses run
    /// this suite as ROOT.
    #[test]
    fn is_active_follows_whether_init_actually_opened_the_file() {
        let dir = tempfile::tempdir().expect("tempdir");
        let mut env = crate::test_support::EnvScope::new();

        // Openable: the handle is live and the file is the 0644 the Bash
        // `install -m 0644` produced.
        let good = dir.path().join("install.log");
        env.set("AGENTLINUX_LOG", &good);
        assert_eq!(init(), good);
        assert!(is_active(), "a created transcript must report active");
        use std::os::unix::fs::PermissionsExt;
        let mode = fs::metadata(&good).expect("stat").permissions().mode() & 0o777;
        assert_eq!(mode, 0o644, "transcript mode");

        line("hello transcript");
        let body = fs::read_to_string(&good).expect("read");
        assert!(
            body.contains("hello transcript"),
            "line must reach the file"
        );

        // Un-openable (a path under a file, so it is ENOTDIR for every user
        // INCLUDING root — a permission-based fixture inverts under the root
        // harnesses). init must not panic, must still return the path, and
        // is_active must now be false so the banner stops naming it.
        let bad = good.join("not-a-dir").join("install.log");
        env.set("AGENTLINUX_LOG", &bad);
        assert_eq!(init(), bad);
        assert!(
            !is_active(),
            "an unopenable transcript must report inactive"
        );
        line("this must not panic");
        assert!(!bad.exists());
    }

    // Re-running keeps the PREVIOUS transcript at `<log>.prev`. The obvious
    // response to a failed install is to run it again, and a plain truncate
    // destroyed the failing run's evidence exactly when it was wanted.
    #[test]
    fn init_rotates_the_previous_transcript_instead_of_destroying_it() {
        let _g = crate::test_support::EnvScope::new();
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("install.log");
        std::env::set_var("AGENTLINUX_LOG", &path);

        init();
        line("run one: the failure worth keeping");
        init();
        line("run two");

        let prev = path.with_extension("log.prev");
        let prev_body = fs::read_to_string(&prev).unwrap();
        assert!(
            prev_body.contains("run one: the failure worth keeping"),
            "previous transcript lost: {prev_body:?}"
        );
        // …and the current transcript is FRESH, so every "the log contains no
        // <bad string>" assertion still describes this run only.
        let body = fs::read_to_string(&path).unwrap();
        assert!(body.contains("run two"));
        assert!(!body.contains("run one"), "current log not fresh: {body:?}");

        std::env::remove_var("AGENTLINUX_LOG");
    }

    // `plog!` reaches the transcript, not just stderr. This is the whole point of
    // the macro: the step markers an operator greps for used to exist only on the
    // console.
    #[test]
    fn plog_writes_step_markers_to_the_transcript() {
        let _g = crate::test_support::EnvScope::new();
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("install.log");
        std::env::set_var("AGENTLINUX_LOG", &path);

        init();
        crate::plog!("[REMEDIATE-01] strategy={}", "chown");
        crate::plog!("[REUSE-WARN] component=npm-prefix — skipped");

        let body = fs::read_to_string(&path).unwrap();
        assert!(body.contains("[REMEDIATE-01] strategy=chown"), "{body:?}");
        assert!(
            body.contains("[REUSE-WARN] component=npm-prefix"),
            "{body:?}"
        );

        std::env::remove_var("AGENTLINUX_LOG");
    }
}
