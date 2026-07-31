//! statelock.rs — one mutating `agentlinux` operation at a time, per host.
//!
//! Every verb that changes host state (`provision`, `install`, `remove`,
//! `upgrade`, `adopt`, `pin`) takes an exclusive advisory lock on a single file
//! before it does anything. `list` does not — a read-only listing has nothing to
//! serialize against, and blocking it would be a regression in a command people
//! run to find out what is going on. `--dry-run` and `--report-only` do not
//! either, for the same reason plus a stronger one: both promise to leave the
//! host byte-identical, and creating a lock file is a write.
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
//! # Two failure modes, deliberately opposite
//! **Contention fails CLOSED.** Another run holds the lock → refuse with
//! `EX_TEMPFAIL`, naming the file. A caller that waits looks identical to a
//! caller that hung, which is exactly the confusion the timeouts elsewhere in
//! this crate exist to remove; `--wait-lock` covers the automation case where
//! queueing IS wanted.
//!
//! **Unavailability fails OPEN.** If the lock file cannot be created or opened at
//! all — no `/run/lock`, a read-only filesystem, a container without the usual
//! layout — we warn loudly and proceed unlocked. Serializing concurrent runs is a
//! guard against a rare race; being unable to *set up* that guard must never be
//! the reason a single, uncontended install refuses to run. Making this the same
//! failure as contention would brick the tool on any host whose `/run` does not
//! look like ours.
//!
//! # Why `/run/lock`
//! It is the FHS home for lock files, it is `1777` so both root (during
//! `provision`) and the unprivileged install user (every later verb) can create
//! the file, and — the load-bearing part — it is OUTSIDE `/opt/agentlinux`, which
//! `--purge` deletes. A lock living inside the tree it protects stops protecting
//! that tree at the moment it matters most: `--purge` would unlink the file it was
//! holding, and the next run would create a fresh one and acquire it cleanly.
//!
//! Because the directory is world-writable, the file is opened `O_NOFOLLOW`: a
//! local user could otherwise plant a symlink there and have root open the target.
//!
//! # Advisory, and that is enough
//! `flock(2)` binds them only because every writer is this same binary taking the
//! same lock. It is not a defence against a hostile process; nothing here treats
//! it as one. In particular a local user can hold this lock and stall AgentLinux
//! operations — under ADR-012, where the install user already has
//! `NOPASSWD: ALL`, that is not a boundary worth defending.

use nix::fcntl::{Flock, FlockArg, OFlag};
use std::fs::{File, OpenOptions};
use std::io;
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;
use std::time::{Duration, Instant};

/// The lock file — FHS lock directory, world-writable, and outside the tree
/// `--purge` removes. See the module docs for why each of those three matters.
const DEFAULT_LOCK_PATH: &str = "/run/lock/agentlinux.lock";

/// Overrides the lock path — the bats/unit-test seam, and the escape hatch for a
/// host with an unusual `/run`.
const LOCK_PATH_ENV: &str = "AGENTLINUX_LOCK_FILE";

/// Set by a run that already holds the lock, for `agentlinux` processes it spawns
/// itself. Without it the nested call would contend with its own parent: the
/// provisioner holds the lock for the whole verb and then dispatches
/// `agentlinux adopt --all`, which would be refused by the run that started it.
pub const LOCK_INHERITED_ENV: &str = "AGENTLINUX_LOCK_INHERITED";

/// How long `--wait-lock` waits before giving up.
///
/// Must exceed the longest legitimate hold or the queue-behind option would give
/// up on a HEALTHY holder — a single recipe may legitimately run for the
/// 30-minute `DEFAULT_RECIPE_TIMEOUT_MS`, and a provision runs several. An hour
/// is comfortably past that while still bounded, so a queued automation run fails
/// inside a normal job timeout rather than holding a runner forever.
const WAIT_TIMEOUT: Duration = Duration::from_secs(3600);

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

/// A held host lock, or a documented absence of one.
///
/// Releases on drop — including on panic, and on process exit, because the kernel
/// drops `flock` with the fd. Callers keep it alive for the whole operation;
/// dropping it early would re-open the window it exists to close, hence
/// `#[must_use]`.
#[derive(Debug)]
#[must_use = "the lock is released as soon as this is dropped"]
pub enum HostLock {
    /// The lock is held for as long as this value lives.
    Held(#[allow(dead_code)] Flock<File>),
    /// Locking was unavailable on this host and the caller proceeded anyway. The
    /// warning has already been emitted.
    Unavailable,
    /// This process inherited the lock from the `agentlinux` run that spawned it.
    Inherited,
}

/// Resolve the lock file path: `$AGENTLINUX_LOCK_FILE` else the default.
fn lock_path() -> PathBuf {
    match std::env::var(LOCK_PATH_ENV) {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => PathBuf::from(DEFAULT_LOCK_PATH),
    }
}

/// Open the lock file, `O_NOFOLLOW`, preferring read-only.
///
/// Read-only first is what lets an unprivileged verb lock a file that `provision`
/// created as root: `flock(2)` locks the open file DESCRIPTION and does not care
/// about the access mode, so `O_RDONLY` on a root-owned `0644` file locks exactly
/// as well as `O_RDWR` would — and `O_RDWR` would fail with EACCES. Creation only
/// happens on the absent path, and needs write permission on the DIRECTORY, not
/// on the file.
fn open_lock_file(path: &std::path::Path) -> io::Result<File> {
    let nofollow = OFlag::O_NOFOLLOW.bits();
    match OpenOptions::new()
        .read(true)
        .custom_flags(nofollow)
        .open(path)
    {
        Ok(f) => Ok(f),
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            OpenOptions::new()
                .create(true)
                .read(true)
                .write(true)
                .truncate(false)
                .custom_flags(nofollow)
                .open(path)
        }
        Err(e) => Err(e),
    }
}

/// Take the host-wide exclusive lock.
///
/// `Ok` means the caller may proceed — holding the lock, or knowingly without it.
/// `Err` means another run holds it and this one must not continue.
///
/// The lock file's CONTENTS are never read: `flock` state lives in the kernel, so
/// an empty file is the whole mechanism and there is no stale-PID file to
/// garbage-collect — a killed process releases the lock the moment its fd closes.
pub fn acquire(verb: &str, on_contention: OnContention) -> io::Result<HostLock> {
    if std::env::var_os(LOCK_INHERITED_ENV).is_some() {
        return Ok(HostLock::Inherited);
    }
    let path = lock_path();
    let file = match open_lock_file(&path) {
        Ok(f) => f,
        // Fail OPEN: see the module docs. A host where we cannot even create the
        // lock file is not a host where every verb should stop working.
        Err(e) => {
            crate::plog!(
                "agentlinux: cannot open the operation lock {} ({e}) — continuing \
                 WITHOUT serialization. Do not run two agentlinux operations at \
                 once on this host.",
                path.display()
            );
            return Ok(HostLock::Unavailable);
        }
    };

    let deadline = Instant::now() + WAIT_TIMEOUT;
    let mut file = file;
    loop {
        match Flock::lock(file, FlockArg::LockExclusiveNonblock) {
            Ok(flock) => return Ok(HostLock::Held(flock)),
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
        std::env::remove_var(LOCK_INHERITED_ENV);
        let out = body(&path);
        std::env::remove_var(LOCK_PATH_ENV);
        out
    }

    fn is_held(l: &HostLock) -> bool {
        matches!(l, HostLock::Held(_))
    }

    // The uncontended case is invisible: acquire succeeds and the file exists.
    #[test]
    fn acquires_when_uncontended() {
        with_temp_lock(|path| {
            let held = acquire("install", OnContention::Fail).unwrap();
            assert!(is_held(&held));
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

    // An unprivileged verb must be able to lock a file `provision` created as
    // root. `flock` locks the open file description regardless of access mode, so
    // opening READ-ONLY is what makes that work — an O_RDWR open of a root-owned
    // 0644 file is EACCES, which would have made every agent-user verb exit 75 on
    // every provisioned host.
    #[test]
    fn locks_a_file_it_can_read_but_not_write() {
        with_temp_lock(|path| {
            std::fs::write(path, b"").unwrap();
            // Read-only for everyone, including the owner: stands in for
            // "root-owned 0644, opened by the agent user".
            let mut perms = std::fs::metadata(path).unwrap().permissions();
            std::os::unix::fs::PermissionsExt::set_mode(&mut perms, 0o444);
            std::fs::set_permissions(path, perms).unwrap();

            let held = acquire("install", OnContention::Fail).unwrap();
            assert!(is_held(&held), "read-only file must still be lockable");
        });
    }

    // A host where the lock CANNOT be created proceeds unlocked with a warning,
    // rather than failing every verb. Unavailability and contention are opposite
    // failure modes on purpose.
    #[test]
    fn unavailable_lock_fails_open_not_closed() {
        let _g = crate::test_support::env_guard();
        std::env::remove_var(LOCK_INHERITED_ENV);
        // A path under a FILE, so both the open and the create-parent fail.
        let dir = tempfile::tempdir().unwrap();
        let blocker = dir.path().join("not-a-dir");
        std::fs::write(&blocker, b"").unwrap();
        std::env::set_var(LOCK_PATH_ENV, blocker.join("agentlinux.lock"));

        let lock = acquire("install", OnContention::Fail).unwrap();
        assert!(matches!(lock, HostLock::Unavailable));

        std::env::remove_var(LOCK_PATH_ENV);
    }

    // A nested `agentlinux` spawned by a run that already holds the lock must not
    // contend with its own parent. `provision` holds the lock for the whole verb
    // and then dispatches `adopt --all`; without this the child is refused and the
    // post-provision adoption silently never happens.
    #[test]
    fn a_nested_run_inherits_rather_than_contending() {
        with_temp_lock(|_| {
            let _parent = acquire("provision", OnContention::Fail).unwrap();
            // The child sees the marker the parent sets on its env.
            std::env::set_var(LOCK_INHERITED_ENV, "1");
            let child = acquire("adopt", OnContention::Fail).unwrap();
            assert!(matches!(child, HostLock::Inherited));
            std::env::remove_var(LOCK_INHERITED_ENV);
        });
    }
}
