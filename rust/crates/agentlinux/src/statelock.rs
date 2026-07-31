//! statelock.rs — one mutating `agentlinux` operation at a time, per host.
//!
//! Every verb that changes host state (`provision`, `install`, `remove`,
//! `upgrade`, `adopt`, `pin`) takes an exclusive advisory lock on a single file
//! before it does anything. `list` does not — a read-only listing has nothing to
//! serialize against, and blocking it would be a regression in a command people
//! run to find out what is going on.
//!
//! # What this prevents
//! Two concurrent runs both `npm install -g` into the SAME prefix and both write
//! into the same `installed.d/`. npm has no locking of its own on a global
//! prefix, so the interleaving can leave a half-linked `node_modules` that
//! neither run would produce alone. `mktemp_in`'s collision-hardening protects a
//! tmpfile NAME; it does nothing about two operations disagreeing about what the
//! host should look like. Sequencing them is the only fix that scales past the
//! individual races, because it needs no per-resource reasoning.
//!
//! # Why fail-fast rather than block
//! A caller that waits looks identical to a caller that hung, which is precisely
//! the confusion the timeout work elsewhere in this crate exists to remove. An
//! immediate, named refusal ("another agentlinux operation is running") tells the
//! operator what to do — wait for the other run, or go find it. `--wait-lock`
//! covers the automation case where blocking IS wanted.
//!
//! # Advisory, and that is enough
//! `flock(2)` binds them only because every writer is this same binary taking the
//! same lock. It is not a defence against a hostile process; nothing here treats
//! it as one.

use nix::fcntl::{Flock, FlockArg};
use std::fs::{File, OpenOptions};
use std::io;
use std::path::PathBuf;
use std::time::{Duration, Instant};

/// The lock file. Under the state root so it shares the lifetime and ownership of
/// what it protects, and survives no longer than the install itself.
const DEFAULT_LOCK_PATH: &str = "/opt/agentlinux/state/agentlinux.lock";

/// Overrides the lock path — the bats/unit-test seam, and the escape hatch for a
/// host whose `/opt` is read-only.
const LOCK_PATH_ENV: &str = "AGENTLINUX_LOCK_FILE";

/// How long `--wait-lock` waits before giving up. Long enough to sit behind a
/// slow install, short enough that a queued automation run fails inside a normal
/// job timeout instead of holding a runner forever.
const WAIT_TIMEOUT: Duration = Duration::from_secs(600);

/// Poll interval while waiting. `flock` has no timed variant, so a blocking
/// acquire cannot be bounded — polling the non-blocking form is what makes
/// `WAIT_TIMEOUT` enforceable.
const WAIT_POLL: Duration = Duration::from_millis(250);

/// Whether a caller queues behind a held lock or is refused immediately.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OnContention {
    /// Refuse at once, naming the other run. The default for an interactive verb.
    Fail,
    /// Wait up to `WAIT_TIMEOUT` for the other run to finish (`--wait-lock`).
    Wait,
}

/// A held host lock. Releases on drop — including on panic, and on process exit,
/// because the kernel drops `flock` with the fd.
///
/// Callers keep this alive for the whole operation; dropping it early would
/// re-open the window it exists to close. Hence `#[must_use]`.
#[derive(Debug)]
#[must_use = "the lock is released as soon as this is dropped"]
pub struct HostLock(#[allow(dead_code)] Flock<File>);

/// Resolve the lock file path: `$AGENTLINUX_LOCK_FILE` else the default.
fn lock_path() -> PathBuf {
    match std::env::var(LOCK_PATH_ENV) {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => PathBuf::from(DEFAULT_LOCK_PATH),
    }
}

/// Take the host-wide exclusive lock, or explain why we could not.
///
/// The lock file is created if absent (0644, root-owned in production). Its
/// CONTENTS are never read: `flock` state lives in the kernel, so an empty file
/// is the whole mechanism and there is no stale-PID file to garbage-collect —
/// a killed process releases the lock the moment its fd closes.
pub fn acquire(verb: &str, on_contention: OnContention) -> io::Result<HostLock> {
    let path = lock_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let file = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .truncate(false)
        .open(&path)
        .map_err(|e| {
            io::Error::new(
                e.kind(),
                format!("cannot open the operation lock {}: {e}", path.display()),
            )
        })?;

    let deadline = Instant::now() + WAIT_TIMEOUT;
    let mut file = file;
    loop {
        match Flock::lock(file, FlockArg::LockExclusiveNonblock) {
            Ok(flock) => return Ok(HostLock(flock)),
            // `Flock::lock` hands the File back on failure so a retry can reuse it.
            Err((returned, errno)) => {
                file = returned;
                if on_contention == OnContention::Fail {
                    return Err(io::Error::other(format!(
                        "another agentlinux operation is already running (lock: {}). \
                         `{verb}` would change the same install state, so it is \
                         refused rather than interleaved. Wait for the other run to \
                         finish, or re-run with --wait-lock to queue behind it.",
                        path.display()
                    )));
                }
                if Instant::now() >= deadline {
                    return Err(io::Error::other(format!(
                        "timed out after {}s waiting for another agentlinux \
                         operation to release {} (last error: {errno})",
                        WAIT_TIMEOUT.as_secs(),
                        path.display()
                    )));
                }
                std::thread::sleep(WAIT_POLL);
            }
        }
    }
}

#[cfg(test)]
mod statelock_tests {
    use super::*;

    /// Point the lock at a fresh temp file for the duration of one test.
    fn with_temp_lock<T>(body: impl FnOnce(&std::path::Path) -> T) -> T {
        let _g = crate::test_support::env_guard();
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("agentlinux.lock");
        std::env::set_var(LOCK_PATH_ENV, &path);
        let out = body(&path);
        std::env::remove_var(LOCK_PATH_ENV);
        out
    }

    // The uncontended case is invisible: acquire succeeds and the file exists.
    #[test]
    fn acquires_when_uncontended() {
        with_temp_lock(|path| {
            let held = acquire("install", OnContention::Fail).unwrap();
            assert!(path.exists());
            drop(held);
        });
    }

    // Releasing lets the next caller straight in — the lock must not leak state
    // into the file, because there is no stale-lock cleanup anywhere.
    #[test]
    fn releases_on_drop_so_the_next_run_proceeds() {
        with_temp_lock(|_| {
            drop(acquire("install", OnContention::Fail).unwrap());
            drop(acquire("upgrade", OnContention::Fail).unwrap());
            // A third time, to show nothing accumulates.
            drop(acquire("remove", OnContention::Fail).unwrap());
        });
    }

    // A second holder is refused with a message that names the verb and the path.
    // `flock` is per-OPEN-FILE-DESCRIPTION, so two opens in one process contend
    // exactly as two processes would.
    #[test]
    fn refuses_a_second_holder_with_an_actionable_message() {
        with_temp_lock(|path| {
            let _held = acquire("install", OnContention::Fail).unwrap();
            let err = acquire("upgrade", OnContention::Fail).unwrap_err();
            let msg = err.to_string();
            assert!(
                msg.contains("another agentlinux operation is already running"),
                "msg={msg}"
            );
            assert!(msg.contains("upgrade"), "must name the refused verb: {msg}");
            assert!(msg.contains("--wait-lock"), "must offer the way out: {msg}");
            assert!(
                msg.contains(&path.display().to_string()),
                "must name the lock file: {msg}"
            );
        });
    }

    // Waiting is bounded, and the wait ENDS when the holder releases.
    #[test]
    fn wait_mode_proceeds_once_the_holder_releases() {
        with_temp_lock(|_| {
            let held = acquire("install", OnContention::Fail).unwrap();
            let releaser = std::thread::spawn(move || {
                std::thread::sleep(Duration::from_millis(400));
                drop(held);
            });
            let start = Instant::now();
            let second = acquire("upgrade", OnContention::Wait).unwrap();
            assert!(
                start.elapsed() >= Duration::from_millis(300),
                "must actually have waited"
            );
            assert!(start.elapsed() < WAIT_TIMEOUT, "must not have hit the cap");
            drop(second);
            releaser.join().unwrap();
        });
    }
}
