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
//! `EX_TEMPFAIL` (75), naming the file. A caller that waits looks identical to a
//! caller that hung, which is exactly the confusion the timeouts elsewhere in
//! this crate exist to remove. There is deliberately no queue-and-wait option:
//! `EX_TEMPFAIL` is the conventional "try again later" signal, and an automation
//! author's `until agentlinux install x; do sleep 10; done` is both more flexible
//! than a built-in cap and something we do not have to carry.
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

/// Why a caller is allowed to proceed.
///
/// No caller matches on this — every variant means "go ahead", and the value
/// exists to be KEPT ALIVE: dropping it releases the lock, which is why it is
/// `#[must_use]`. The variants are here so a debug print and the tests can say
/// which case occurred. Releases on drop including on panic and on process exit,
/// because the kernel drops `flock` with the fd.
#[derive(Debug)]
#[must_use = "the lock is released as soon as this is dropped"]
pub enum HostLock {
    /// The lock is held for as long as this value lives. The `Flock` is never
    /// read — it is retained purely for its `Drop`.
    Held(#[allow(dead_code)] Flock<File>),
    /// Locking was unavailable on this host and the caller proceeded anyway. The
    /// warning has already been emitted.
    Unavailable,
    /// This process inherited the lock from the `agentlinux` run that spawned it.
    Inherited,
    /// The verb does not mutate host state, so no lock was sought.
    NotRequired,
}

/// Resolve the lock file path: `$AGENTLINUX_LOCK_FILE` else the default.
fn lock_path() -> PathBuf {
    match std::env::var(LOCK_PATH_ENV) {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => PathBuf::from(DEFAULT_LOCK_PATH),
    }
}

/// Why `open_lock_file` could not hand back a usable lock file. The two arms get
/// opposite treatment, which is the whole reason the type exists.
enum LockOpenError {
    /// The host cannot support the lock: no `/run/lock`, a read-only filesystem,
    /// no permission to create. A property of the machine, so we fail OPEN.
    Unavailable(io::Error),
    /// Something is sitting at the lock path that should not be — a symlink, a
    /// FIFO, a directory. `/run/lock` is world-writable, so that is a local user
    /// planting an object, not a host-shape problem, and we fail CLOSED.
    Hostile(String),
}

/// The open flags every attempt carries.
///
/// `O_NOFOLLOW` refuses a symlink at the final component. `O_NONBLOCK` is the
/// other half and is NOT optional: `O_NOFOLLOW` says nothing about other file
/// types, and `open()` on a FIFO blocks in the kernel until a writer appears —
/// no timeout, no signal escape, and nothing in this crate's bounding scheme
/// applies because it happens before any child is spawned. One
/// `mkfifo /run/lock/agentlinux.lock` by any local user would otherwise hang
/// every privileged verb forever, silently, before the transcript is even open.
fn lock_open_flags() -> i32 {
    // `.union()` rather than `|`: for DISJOINT flag bits `a | b` and `a ^ b` are the
    // same value, so the `| -> ^` mutant is equivalent and no test can kill it.
    // A blanket `mutants::skip` would also excuse the killable mutants in the same
    // function, which ADR-020 §4 forbids — so the operator goes instead.
    OFlag::O_NOFOLLOW.union(OFlag::O_NONBLOCK).bits()
}

/// Open the lock file, preferring read-only, and prove it is a regular file.
///
/// Read-only first is what lets an unprivileged verb lock a file that `provision`
/// created as root: `flock(2)` locks the open file DESCRIPTION and does not care
/// about the access mode, so `O_RDONLY` on a root-owned `0644` file locks exactly
/// as well as `O_RDWR` would — and `O_RDWR` would fail with EACCES. Creation only
/// happens on the absent path, and needs write permission on the DIRECTORY, not
/// on the file.
fn open_lock_file(path: &std::path::Path) -> Result<File, LockOpenError> {
    let file = match OpenOptions::new()
        .read(true)
        .custom_flags(lock_open_flags())
        .open(path)
    {
        Ok(f) => f,
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).map_err(LockOpenError::Unavailable)?;
            }
            OpenOptions::new()
                .create(true)
                .read(true)
                .write(true)
                .truncate(false)
                .custom_flags(lock_open_flags())
                .open(path)
                .map_err(LockOpenError::Unavailable)?
        }
        // ELOOP is what `O_NOFOLLOW` returns for a planted symlink. Routing it to
        // `Unavailable` would mean a one-line `ln -s` silently disabled host
        // serialization for every future run — the warning would scroll past and
        // nothing would ever repair the path.
        Err(e) if e.raw_os_error() == Some(nix::errno::Errno::ELOOP as i32) => {
            return Err(LockOpenError::Hostile(format!(
                "{} is a symlink; the lock path must be a regular file",
                path.display()
            )))
        }
        Err(e) => return Err(LockOpenError::Unavailable(e)),
    };

    // `O_NONBLOCK` kept the FIFO case from hanging; this is what makes it an
    // error rather than a lock taken on the wrong kind of object. A directory
    // opens and `flock`s perfectly well, which would hand an attacker a lockable
    // object they could hold indefinitely.
    match file.metadata() {
        Ok(m) if m.file_type().is_file() => Ok(file),
        Ok(m) => Err(LockOpenError::Hostile(format!(
            "{} is not a regular file ({:?}); refusing to lock it",
            path.display(),
            m.file_type()
        ))),
        Err(e) => Err(LockOpenError::Unavailable(e)),
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
pub fn acquire(verb: &str) -> io::Result<HostLock> {
    if std::env::var(LOCK_INHERITED_ENV).as_deref() == Ok("1") {
        // Announce it. This variable disables host serialization outright, and
        // anything that exports it — a shell profile, a CI job copying env
        // wholesale, a debugging session left over — silently turns the guard off
        // for every verb. A bypass nobody can see is worse than no bypass.
        crate::plog!(
            "agentlinux: {LOCK_INHERITED_ENV} is set — `{verb}` is treating the \
             host lock as already held by a parent run. If no agentlinux run \
             spawned this one, unset that variable: it disables serialization."
        );
        return Ok(HostLock::Inherited);
    }
    let path = lock_path();
    let file = match open_lock_file(&path) {
        Ok(f) => f,
        // Fail OPEN: a host that cannot support the lock is not a host where
        // every verb should stop working.
        Err(LockOpenError::Unavailable(e)) => {
            crate::plog!(
                "agentlinux: cannot open the operation lock {} ({e}) — continuing \
                 WITHOUT serialization. Do not run two agentlinux operations at \
                 once on this host. Point {LOCK_PATH_ENV} at a writable path to \
                 restore it.",
                path.display()
            );
            return Ok(HostLock::Unavailable);
        }
        // Fail CLOSED: something is squatting the path. Proceeding would disable
        // serialization for every future run, permanently and quietly, because
        // nothing here ever repairs the planted object.
        Err(LockOpenError::Hostile(what)) => {
            return Err(io::Error::other(format!(
                "refusing to run `{verb}`: {what}. `{}` is world-writable, so this \
                 is most likely another user squatting the path. Remove it (as \
                 root) and re-run.",
                path.parent().unwrap_or(&path).display()
            )))
        }
    };

    match Flock::lock(file, FlockArg::LockExclusiveNonblock) {
        Ok(flock) => Ok(HostLock::Held(flock)),
        Err((_returned, _errno)) => Err(io::Error::other(format!(
            "another agentlinux operation is already running (lock: {}). `{verb}` \
             would change the same install state, so it is refused rather than \
             interleaved — this is exit {}, the conventional \"try again later\". \
             Wait for the other run to finish, or retry in a loop.",
            path.display(),
            crate::EX_TEMPFAIL
        ))),
    }
}

#[cfg(test)]
mod statelock_tests {
    use super::*;

    /// Point the lock at a fresh temp file for the duration of one test.
    fn with_temp_lock<T>(body: impl FnOnce(&std::path::Path) -> T) -> T {
        let _g = crate::test_support::EnvScope::new();
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
            let held = acquire("install").unwrap();
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
            drop(acquire("install").unwrap());
            drop(acquire("upgrade").unwrap());
            drop(acquire("remove").unwrap());
        });
    }

    // A second holder is refused with a message that names the verb and the path.
    // `flock` is per-OPEN-FILE-DESCRIPTION, so two opens in one process contend
    // exactly as two processes would.
    #[test]
    fn refuses_a_second_holder_with_an_actionable_message() {
        with_temp_lock(|path| {
            let _held = acquire("install").unwrap();
            let err = acquire("upgrade").unwrap_err();
            let msg = err.to_string();
            assert!(
                msg.contains("another agentlinux operation is already running"),
                "msg={msg}"
            );
            assert!(msg.contains("upgrade"), "must name the refused verb: {msg}");
            assert!(
                msg.contains("try again later"),
                "must name the retry contract: {msg}"
            );
            assert!(msg.contains("75"), "must name the exit code: {msg}");
            assert!(
                msg.contains(&path.display().to_string()),
                "must name the lock file: {msg}"
            );
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

            let held = acquire("install").unwrap();
            assert!(is_held(&held), "read-only file must still be lockable");
        });
    }

    // A host where the lock CANNOT be created proceeds unlocked with a warning,
    // rather than failing every verb. Unavailability and contention are opposite
    // failure modes on purpose.
    #[test]
    fn unavailable_lock_fails_open_not_closed() {
        let _g = crate::test_support::EnvScope::new();
        std::env::remove_var(LOCK_INHERITED_ENV);
        // A path under a FILE, so both the open and the create-parent fail.
        let dir = tempfile::tempdir().unwrap();
        let blocker = dir.path().join("not-a-dir");
        std::fs::write(&blocker, b"").unwrap();
        std::env::set_var(LOCK_PATH_ENV, blocker.join("agentlinux.lock"));

        let lock = acquire("install").unwrap();
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
            let _parent = acquire("provision").unwrap();
            // The child sees the marker the parent sets on its env.
            std::env::set_var(LOCK_INHERITED_ENV, "1");
            let child = acquire("adopt").unwrap();
            assert!(matches!(child, HostLock::Inherited));
            std::env::remove_var(LOCK_INHERITED_ENV);
        });
    }

    // An EMPTY override is not an override. Without the non-empty guard,
    // `AGENTLINUX_LOCK_FILE=` — which is what an unset shell variable expands to
    // in `FOO="$BAR"` — resolves the lock to the empty path, which can never be
    // opened, so every verb on that host silently drops to `Unavailable` and
    // runs unserialized.
    #[test]
    fn an_empty_override_falls_back_to_the_default_path() {
        let _g = crate::test_support::EnvScope::new();
        std::env::set_var(LOCK_PATH_ENV, "");
        assert_eq!(lock_path(), PathBuf::from(DEFAULT_LOCK_PATH));
        std::env::set_var(LOCK_PATH_ENV, "/tmp/elsewhere.lock");
        assert_eq!(lock_path(), PathBuf::from("/tmp/elsewhere.lock"));
    }

    // A symlink at the lock path must fail CLOSED. This is the fail-open/
    // fail-closed split in one test: were the symlink followed (no `O_NOFOLLOW`)
    // or its ELOOP classified as `Unavailable`, the run would proceed —
    // locking the attacker's target file instead, or nothing at all — and no
    // future run would ever repair the planted link.
    #[test]
    fn a_symlink_at_the_lock_path_is_refused_rather_than_followed() {
        with_temp_lock(|path| {
            let target = path.with_file_name("attacker-target");
            std::fs::write(&target, b"").unwrap();
            std::os::unix::fs::symlink(&target, path).unwrap();

            let err = acquire("install").expect_err("a symlinked lock path must be refused");
            let msg = err.to_string();
            assert!(msg.contains("symlink"), "message must name the cause: {msg}");
            assert!(
                msg.contains("install"),
                "message must name the refused verb: {msg}"
            );
        });
    }

    // `O_NOFOLLOW` says nothing about file TYPE, so the type check is a separate
    // guard with its own failure mode: a directory opens and `flock`s perfectly
    // well, so accepting one hands a local user a lockable object they can hold
    // indefinitely — every privileged verb refused, forever, by a `mkdir`.
    #[test]
    fn a_directory_at_the_lock_path_is_refused_rather_than_locked() {
        with_temp_lock(|path| {
            std::fs::create_dir(path).unwrap();
            let err = acquire("upgrade").expect_err("a directory must not be lockable");
            assert!(
                err.to_string().contains("not a regular file"),
                "message must say what was wrong: {err}"
            );
        });
    }

    // The other half of `lock_open_flags`. Without `O_NONBLOCK`, `open()` on a
    // FIFO blocks in the kernel until a writer appears — no timeout, no signal
    // escape, before the transcript is even open. Run on a worker thread with a
    // bounded join so a regression fails this test in 10s instead of hanging the
    // suite the way it would hang the CLI.
    #[test]
    fn a_fifo_at_the_lock_path_is_refused_without_blocking() {
        with_temp_lock(|path| {
            nix::unistd::mkfifo(path, nix::sys::stat::Mode::from_bits_truncate(0o644)).unwrap();

            let (tx, rx) = std::sync::mpsc::channel();
            let owned = path.to_path_buf();
            std::thread::spawn(move || {
                std::env::set_var(LOCK_PATH_ENV, &owned);
                let _ = tx.send(acquire("remove").map(|l| format!("{l:?}")));
            });

            match rx.recv_timeout(std::time::Duration::from_secs(10)) {
                Ok(Err(e)) => assert!(
                    e.to_string().contains("not a regular file"),
                    "a FIFO must be refused as the wrong file type: {e}"
                ),
                Ok(Ok(lock)) => panic!("a FIFO must not be lockable, got {lock}"),
                Err(_) => panic!("acquire() blocked on a FIFO — O_NONBLOCK is missing"),
            }
        });
    }
}
