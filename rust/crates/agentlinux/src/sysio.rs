//! sysio.rs — the grep-before-mutate filesystem primitives (PROV-01).
//!
//! Every state change the provisioner makes goes through one of these helpers.
//! A blind append or a non-atomic write is forbidden: it breaks INST-02 (the run
//! must converge across re-runs) and produces the drift INST-05 later flags.
//!
//! The load-bearing invariants:
//!
//! - **`write_file_atomic`** — the tmpfile is created in the DEST's PARENT dir
//!   (same filesystem) so the final `fs::rename` is atomic; a cross-fs temp dir
//!   would fall back to copy+unlink and lose atomicity.
//!   The tmpfile is unlinked on EVERY error path (an RAII guard mirroring the
//!   Bash `trap "rm -f" RETURN`). Mode is set on the tmpfile BEFORE the rename so
//!   the destination is never briefly world-readable.
//! - **`ensure_line_in_file`** — `grep -Fxq` semantics: literal, whole-line,
//!   append `line\n` only when no exact whole-line match already exists.
//! - **`ensure_marker_block`** — the awk-strip + emit-order algorithm is
//!   BYTE-load-bearing: `--top` emits `begin\n{body}\n{end}\n` THEN the filtered
//!   remainder; `--bottom` emits the filtered remainder THEN the block. A line
//!   equal to `begin` starts skipping, a line equal to `end` stops skipping,
//!   both marker lines are dropped, everything else survives byte-identical.
//!   Written through `write_file_atomic(0o644, …)` exactly like the Bash
//!   `install -m 0644`. The `.bashrc`/`CLAUDE.md` bats grep these bytes.
//! - **`ensure_user`** — id-gated `useradd --create-home --shell /bin/bash
//!   --user-group <name>`; a NO-OP when the user already exists (never modifies
//!   an existing identity).
//! - **`ensure_dir`** — absent → create with mode+owner; present → RE-ASSERT
//!   mode+owner unconditionally so a re-run corrects out-of-band drift.
//! - **`visudo_validate`** — `visudo -cf <file>`; a non-zero check is an `Err`.

use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

/// RAII guard that unlinks a tmpfile on drop unless explicitly disarmed after a
/// successful rename — the Rust twin of the Bash `trap "rm -f -- '$tmp'" RETURN`.
/// Guarantees cleanup on every error path (a mid-write abort, a failed rename, a
/// failed `set_permissions`), so no residual `.dest.XXXXXX` is ever left behind.
pub(crate) struct TmpGuard {
    path: Option<PathBuf>,
}

impl TmpGuard {
    pub(crate) fn new(path: PathBuf) -> Self {
        Self { path: Some(path) }
    }

    /// Disarm the guard after the tmpfile has been renamed into place (the
    /// rename consumed the tmpfile, so there is nothing left to unlink).
    pub(crate) fn disarm(&mut self) {
        self.path = None;
    }
}

impl Drop for TmpGuard {
    fn drop(&mut self) {
        if let Some(ref p) = self.path {
            let _ = fs::remove_file(p);
        }
    }
}

/// Create a hidden, unique tmpfile in `dir`, mirroring `mktemp -p "$dir"
/// ".${base}.XXXXXX"`. Same-directory placement is what keeps a later
/// `fs::rename` atomic on one filesystem. The name is a leading-dot
/// `.{base}.{pid}.{nanos}.{attempt}` — collision-hardened by the monotonic nanos
/// plus an O_CREAT|O_EXCL retry, so two concurrent provisioner runs never clobber
/// each other.
pub(crate) fn mktemp_in(dir: &Path, base: &str) -> io::Result<(fs::File, PathBuf)> {
    use std::time::{SystemTime, UNIX_EPOCH};
    let pid = std::process::id();
    for attempt in 0..1000u32 {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let name = format!(".{base}.{pid}.{nanos}.{attempt}");
        let candidate = dir.join(name);
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&candidate)
        {
            Ok(f) => return Ok((f, candidate)),
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(io::Error::new(
        io::ErrorKind::AlreadyExists,
        "mktemp_in: exhausted unique-name attempts",
    ))
}

/// `write_file_atomic <mode> <dest>` — atomic full-file overwrite from `body`.
///
/// Writes `body` verbatim to a tmpfile in `dest`'s PARENT dir, sets `mode` on
/// the tmpfile, then atomically `fs::rename`s it onto `dest`. Same observable
/// result as `install -m <mode> <tmp> <dest>`: a re-run with identical body
/// yields a byte-identical file with no residual tmpfile, and the body is
/// preserved exactly including any trailing newline. The tmpfile is unlinked on
/// every error path (the `TmpGuard`), mirroring the Bash RETURN trap.
///
/// # Errors name the file and the step
/// Every failure is wrapped with the operation that failed and the path it failed
/// on. A raw `io::Error` here surfaced four steps up as
/// `40-path-wiring step failed: No such file or directory (os error 2)` — which of
/// the four artefacts, on which operation, was not recoverable without `strace`.
pub fn write_file_atomic(mode: u32, dest: &Path, body: &[u8]) -> io::Result<()> {
    let dir = dest.parent().unwrap_or_else(|| Path::new("."));
    let base = dest.file_name().and_then(|s| s.to_str()).ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("write_file_atomic: {} has no file name", dest.display()),
        )
    })?;

    let (mut file, tmp) = mktemp_in(dir, base)
        .map_err(|e| context(&e, "create a tmpfile next to", dest, Some(dir)))?;
    let mut guard = TmpGuard::new(tmp.clone());

    file.write_all(body)
        .and_then(|()| file.flush())
        // fsync the tmpfile BEFORE the rename so a power loss in the
        // rename→commit window can't leave a zero-length / torn config (esp. the
        // 0440 sudoers). Cheap — once per small config file.
        .and_then(|()| file.sync_all())
        .map_err(|e| context(&e, "write", dest, Some(&tmp)))?;
    // Set mode on the tmpfile BEFORE the rename so the destination is never
    // briefly created with the umask-default mode (mirrors install -m).
    fs::set_permissions(&tmp, fs::Permissions::from_mode(mode))
        .map_err(|e| context(&e, &format!("chmod {mode:04o}"), dest, Some(&tmp)))?;
    drop(file);

    fs::rename(&tmp, dest).map_err(|e| context(&e, "rename into place", dest, Some(&tmp)))?;
    // The rename consumed the tmpfile — disarm so Drop does not try to unlink a
    // now-nonexistent path.
    guard.disarm();
    Ok(())
}

/// Wrap an `io::Error` with the operation that failed and the path it failed on,
/// preserving the original `ErrorKind` so callers can still match on it.
///
/// `via` names the intermediate path when the failure happened on a tmpfile
/// rather than the destination — without it, an EACCES on the tmpfile reads as an
/// EACCES on a destination the operator can see is writable.
fn context(e: &io::Error, doing: &str, dest: &Path, via: Option<&Path>) -> io::Error {
    let where_ = match via {
        Some(v) if v != dest => format!("{} (via {})", dest.display(), v.display()),
        _ => dest.display().to_string(),
    };
    io::Error::new(e.kind(), format!("failed to {doing} {where_}: {e}"))
}

/// `ensure_line_in_file <line> <file>` — append `line\n` iff no exact
/// whole-line match already exists (`grep -Fxq` semantics: literal, whole-line).
///
/// An ABSENT file is treated as "no match" (so the first call creates it). A file
/// that exists but cannot be read is an ERROR, not a miss — see below.
///
/// The existing trailing bytes are preserved — a blind append after content with
/// no trailing newline would glue the new line onto the last one, but the Bash
/// `printf '%s\n' >>file` also appends unconditionally once the grep misses, so
/// we match it exactly (append `line\n`).
///
/// # Why the read is byte-oriented
/// Matching on BYTES rather than `read_to_string` is what makes the
/// grep-before-mutate contract hold. `read_to_string` fails on any non-UTF-8
/// byte, and the previous `if let Ok(existing)` swallowed that failure into "no
/// match" — so a `~/.npmrc` carrying one Latin-1 byte in a proxy password got
/// another `prefix=…` line appended on EVERY converge run. `grep -Fx`, the
/// semantics this reproduces, compares bytes and does not care about encoding.
pub fn ensure_line_in_file(line: &str, file: &Path) -> io::Result<()> {
    match fs::read(file) {
        Ok(existing) => {
            // `-x` = whole-line: split on b'\n' and compare each segment
            // literally. `str::lines()` also strips a trailing '\r'; grep -Fx
            // does not, so compare against the raw '\n'-split segments instead.
            if existing
                .split(|b| *b == b'\n')
                .any(|seg| seg == line.as_bytes())
            {
                return Ok(());
            }
        }
        Err(e) if e.kind() == io::ErrorKind::NotFound => {}
        // Anything else (EACCES, EIO, a directory in the way) means we could not
        // check. Appending blind would duplicate the line on every run; refusing
        // makes the operator fix the real problem.
        Err(e) => {
            return Err(io::Error::new(
                e.kind(),
                format!(
                    "ensure_line_in_file: cannot read {} to check for an existing \
                     line (refusing to append blind): {e}",
                    file.display()
                ),
            ))
        }
    }
    let mut f = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(file)?;
    // ONE write: `write_all(line)` followed by `write_all(b"\n")` is not an
    // atomic append, and an ENOSPC between them leaves a newline-less partial
    // line that the next whole-line match can never see — so the run after that
    // appends a duplicate.
    let mut record = Vec::with_capacity(line.len() + 1);
    record.extend_from_slice(line.as_bytes());
    record.push(b'\n');
    f.write_all(&record)?;
    Ok(())
}

/// Strip any pre-existing `[begin, end]` marker block from `existing`, dropping
/// BOTH marker lines and everything between them, keeping every other line —
/// exactly the awk filter:
/// ```awk
/// $0 == b { in_block=1; next }
/// $0 == e { in_block=0; next }
/// !in_block { print }
/// ```
/// Line-level, whole-line equality. Returns the surviving lines WITHOUT a
/// trailing newline joiner decision (the caller re-assembles). We split on '\n'
/// and, mirroring awk's record model, treat the content as newline-terminated
/// records: a trailing empty segment (from a final '\n') is preserved so a file
/// that ended in a newline keeps ending in one after filtering.
///
/// # Unterminated blocks are refused, not filtered
/// The awk filter this ports has no end-of-input check: with `in_block` still set
/// at EOF it drops every remaining line. So a user who hand-edits `~/.bashrc` and
/// deletes only the end marker loses everything below it on the next converge
/// run — data loss caused by the helper advertised as safe to re-run. We detect
/// that state and return an `Err` instead, leaving the file untouched.
fn strip_marker_block(existing: &str, begin: &str, end: &str) -> io::Result<Vec<String>> {
    let mut out = Vec::new();
    let mut in_block = false;
    // awk reads records split on '\n'; a trailing '\n' does NOT create a final
    // empty record. Emulate by iterating lines and dropping the final empty
    // segment that `split('\n')` produces for newline-terminated input.
    let mut segments: Vec<&str> = existing.split('\n').collect();
    if existing.ends_with('\n') {
        // The last segment is the empty string after the final '\n' — awk never
        // sees it as a record.
        segments.pop();
    } else if existing.is_empty() {
        // No records at all.
        segments.clear();
    }
    for line in segments {
        if line == begin {
            in_block = true;
            continue;
        }
        if line == end {
            in_block = false;
            continue;
        }
        if !in_block {
            out.push(line.to_string());
        }
    }
    if in_block {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "unterminated agentlinux block: found `{begin}` with no matching \
                 `{end}`. Refusing to rewrite the file — continuing would delete \
                 every line after the begin marker. Restore the end marker (or \
                 delete the begin marker) and re-run."
            ),
        ));
    }
    Ok(out)
}

/// `ensure_marker_block <file> <tag> [--top|--bottom]` — replace the content
/// between `# >>> <tag> begin >>>` / `# <<< <tag> end <<<` markers with `body`,
/// at the requested `placement`, preserving all content OUTSIDE the markers
/// byte-identical. Written via `write_file_atomic(0o644, …)`.
///
/// The exact marker strings + the emit order are byte-load-bearing. `Top` emits
/// `begin\n{body}\n{end}\n` then the filtered remainder; `Bottom` emits the
/// filtered remainder then `begin\n{body}\n{end}\n`. Re-running replaces the
/// block in place, leaving exactly ONE block.
/// The block is always written at the TOP of the file. That is required, not
/// incidental: the skel `.bashrc` early-returns for non-interactive shells, so an
/// agentlinux block that must influence `sudo -u agent bash -c …` has to precede
/// that guard. Every caller needs this, so there is no placement knob to get
/// wrong.
pub fn ensure_marker_block(file: &Path, tag: &str, body: &str) -> io::Result<()> {
    let begin = format!("# >>> {tag} begin >>>");
    let end = format!("# <<< {tag} end <<<");

    let existing = fs::read_to_string(file).unwrap_or_default();
    let filtered = strip_marker_block(&existing, &begin, &end).map_err(|e| {
        io::Error::new(e.kind(), format!("{}: {e}", file.display()))
    })?;

    // The block itself, printf '%s\n' three times → begin\n{body}\n{end}\n.
    let block = format!("{begin}\n{body}\n{end}\n");

    // The filtered remainder: awk prints each surviving record followed by a
    // newline (`print`), so join with '\n' AND add a trailing '\n' when there is
    // any content — reproducing the awk output byte-for-byte.
    let remainder = if filtered.is_empty() {
        String::new()
    } else {
        let mut s = filtered.join("\n");
        s.push('\n');
        s
    };

    let mut out = String::new();
    out.push_str(&block);
    out.push_str(&remainder);

    write_file_atomic(0o644, file, out.as_bytes())
}

/// Build the `useradd` argv the way `idempotency.sh` invokes it:
/// `useradd --create-home --shell /bin/bash --user-group <name>`. Factored out so
/// the unit test asserts the exact argv WITHOUT spawning a real `useradd` (which
/// would mutate `/etc/passwd`).
fn useradd_argv(name: &str) -> Vec<String> {
    vec![
        "useradd".to_string(),
        "--create-home".to_string(),
        "--shell".to_string(),
        "/bin/bash".to_string(),
        "--user-group".to_string(),
        name.to_string(),
    ]
}

/// `ensure_user <name>` — `useradd` only if the user is absent.
///
/// Resolves the user via `nix::unistd::User::from_name`; a hit is a NO-OP (never
/// modifies an existing identity — matches the Bash `id … && return 0`). A miss
/// runs `useradd --create-home --shell /bin/bash --user-group <name>`.
pub fn ensure_user(name: &str) -> io::Result<()> {
    if user_exists(name)? {
        return Ok(());
    }
    let argv = useradd_argv(name);
    let code = run_bounded(&argv)?;
    if code != 0 {
        return Err(io::Error::other(format!(
            "ensure_user: useradd failed for {name} (exit {code})"
        )));
    }
    Ok(())
}

/// Wall-clock bound on the local admin tools this module spawns.
///
/// `useradd` and `visudo` are local and fast, but both take locks — `useradd`
/// on `/etc/passwd`, `visudo` on `/etc/sudoers` — and a lock held by a stuck
/// process makes them wait forever. Two minutes is far beyond any legitimate run
/// and turns "the provision hangs with no output" into a named failure.
const ADMIN_TOOL_TIMEOUT_MS: u64 = 120_000;

/// Spawn a local admin tool bounded by `ADMIN_TOOL_TIMEOUT_MS`, in its own
/// process group so the timeout can tear the whole thing down. Returns its exit
/// code; a timeout surfaces as a non-zero code with the dispatcher's log line.
fn run_bounded(argv: &[String]) -> io::Result<i32> {
    let (program, args) = argv.split_first().ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "run_bounded: empty argv")
    })?;
    let mut cmd = Command::new(program);
    cmd.args(args);
    crate::dispatcher::own_process_group(&mut cmd);
    let mut child = cmd.spawn()?;
    let (code, _timed_out) =
        crate::dispatcher::wait_with_timeout(&mut child, Some(ADMIN_TOOL_TIMEOUT_MS), &argv.join(" "));
    Ok(code)
}

/// Whether a system user with `name` exists. Isolated so the exists-noop path is
/// unit-testable against a name that is virtually certain to exist (`root`) and
/// one that does not, without touching `/etc/passwd`.
fn user_exists(name: &str) -> io::Result<bool> {
    match nix::unistd::User::from_name(name) {
        Ok(u) => Ok(u.is_some()),
        Err(e) => Err(io::Error::other(format!(
            "ensure_user: User::from_name({name}) failed: {e}"
        ))),
    }
}

/// `ensure_dir <path> <mode> <user:group>` — create if absent (mode+owner), else
/// RE-ASSERT mode+owner unconditionally so a re-run corrects out-of-band drift
/// (matches the Bash `install -d` on the absent arm, `chmod` + `chown` on the
/// present arm). `owner` is `"user:group"`.
pub fn ensure_dir(path: &Path, mode: u32, owner: &str) -> io::Result<()> {
    let (uid, gid) = resolve_owner(owner)?;
    if !path.is_dir() {
        fs::create_dir_all(path).map_err(|e| context(&e, "create directory", path, None))?;
    }
    // Re-assert mode + owner unconditionally on BOTH arms (create-then-set on the
    // absent arm equals `install -d -m -o -g`; the present arm is the Bash
    // chmod+chown drift-correction).
    fs::set_permissions(path, fs::Permissions::from_mode(mode))
        .map_err(|e| context(&e, &format!("chmod {mode:04o}"), path, None))?;
    // `std::os::unix::fs::chown` (the plan's sanctioned syscall alternative —
    // `nix::unistd::chown` is gated behind nix's `fs` feature which we do NOT
    // enable; only `user` is on for the name→uid/gid resolution).
    std::os::unix::fs::chown(path, Some(uid), Some(gid)).map_err(|e| {
        io::Error::other(format!("ensure_dir: chown {} failed: {e}", path.display()))
    })?;
    Ok(())
}

/// Resolve a `"user:group"` string to `(uid, gid)` raw ids via the passwd/group
/// DBs (`nix::unistd::{User,Group}::from_name`, the `user` feature), matching the
/// Bash `chown user:group` name resolution. `${owner%:*}` / `${owner#*:}` split
/// on the FIRST colon.
pub fn resolve_owner(owner: &str) -> io::Result<(u32, u32)> {
    let (user, group) = owner.split_once(':').ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "resolve_owner: owner must be user:group",
        )
    })?;
    let uid = nix::unistd::User::from_name(user)
        .map_err(|e| io::Error::other(format!("resolve_owner: user {user}: {e}")))?
        .ok_or_else(|| io::Error::other(format!("resolve_owner: unknown user {user}")))?
        .uid
        .as_raw();
    let gid = nix::unistd::Group::from_name(group)
        .map_err(|e| io::Error::other(format!("resolve_owner: group {group}: {e}")))?
        .ok_or_else(|| io::Error::other(format!("resolve_owner: unknown group {group}")))?
        .gid
        .as_raw();
    Ok((uid, gid))
}

/// `chown <owner> <path>` where `owner` is `"user:group"` — the ONE chown helper.
///
/// Five provisioner modules previously carried byte-identical private copies of
/// this, each re-resolving the same passwd/group lookups with its own error
/// wording. Callers that need to chown a whole tree use
/// `provision::registry_cli::chown_recursive`, which builds on this.
pub fn chown_by_name(path: &Path, owner: &str) -> io::Result<()> {
    let (uid, gid) = resolve_owner(owner)?;
    std::os::unix::fs::chown(path, Some(uid), Some(gid))
        .map_err(|e| io::Error::other(format!("chown {} failed: {e}", path.display())))
}

/// Create `path` empty at 0644 owned by `owner` if it does not exist; leave a
/// present file completely untouched (the caller's `ensure_line_in_file` mutates
/// it). Mirrors `install -m 0644 -o <u> -g <g> /dev/null <path>`.
///
/// KNOWN LIMITATION: `path.exists()` FOLLOWS symlinks, and so do `File::create`
/// and the chown. A dangling symlink at `path` therefore causes the target to be
/// created and chowned to `owner` — no race required. Callers run this as root
/// against paths inside the agent's own home, so an agent that plants
/// `~/.npmrc -> /etc/ld.so.preload` gets that file created and handed to it. The
/// fix is `O_NOFOLLOW` plus `fchmod`/`fchown` on the open handle.
pub fn create_if_absent_0644(path: &Path, owner: &str) -> io::Result<()> {
    if path.exists() {
        return Ok(());
    }
    fs::File::create(path).map_err(|e| context(&e, "create", path, None))?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o644))
        .map_err(|e| context(&e, "chmod 0644", path, None))?;
    chown_by_name(path, owner)
}

/// `command -v <name>` — resolve a program on PATH, `None` if absent.
pub fn which(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths).find_map(|dir| {
            let cand = dir.join(name);
            if cand.is_file() {
                Some(cand)
            } else {
                None
            }
        })
    })
}

/// `visudo_validate <file>` — `visudo -cf <file>` safety check before installing
/// a sudoers drop-in. A non-zero check maps to an `Err`.
pub fn visudo_validate(file: &Path) -> io::Result<()> {
    let argv = vec![
        "visudo".to_string(),
        "-cf".to_string(),
        file.display().to_string(),
    ];
    if run_bounded(&argv)? != 0 {
        return Err(io::Error::other(format!(
            "visudo_validate: sudoers syntax check failed for {} (visudo -cf rejected)",
            file.display()
        )));
    }
    Ok(())
}

#[cfg(test)]
mod sysio_tests {
    use super::*;
    use std::os::unix::fs::MetadataExt;
    use tempfile::TempDir;

    fn mode_of(p: &Path) -> u32 {
        fs::metadata(p).unwrap().permissions().mode() & 0o7777
    }

    // --- write_file_atomic ---

    #[test]
    fn write_file_atomic_writes_body_verbatim_with_mode() {
        let d = TempDir::new().unwrap();
        let dest = d.path().join("file.conf");
        let body = b"LANG=C.UTF-8\nLC_ALL=C.UTF-8\n";
        write_file_atomic(0o644, &dest, body).unwrap();
        assert_eq!(fs::read(&dest).unwrap(), body);
        assert_eq!(mode_of(&dest), 0o644);
    }

    #[test]
    fn write_file_atomic_preserves_trailing_newline_and_reruns_identically() {
        let d = TempDir::new().unwrap();
        let dest = d.path().join("f");
        let body = b"one line no newline";
        write_file_atomic(0o600, &dest, body).unwrap();
        assert_eq!(fs::read(&dest).unwrap(), body); // no trailing newline added
        assert_eq!(mode_of(&dest), 0o600);
        // Re-run with identical body → byte-identical, still no residual tmpfile.
        write_file_atomic(0o600, &dest, body).unwrap();
        assert_eq!(fs::read(&dest).unwrap(), body);
    }

    #[test]
    fn write_file_atomic_tmpfile_in_parent_dir_and_no_residual() {
        let d = TempDir::new().unwrap();
        let dest = d.path().join("target.txt");
        write_file_atomic(0o644, &dest, b"x\n").unwrap();
        // The rename target is correct...
        assert_eq!(fs::read(&dest).unwrap(), b"x\n");
        // ...and no residual `.target.txt.*` tmpfile remains in the parent dir
        // (same-dir tmpfile, cleaned on the successful rename).
        let residuals: Vec<_> = fs::read_dir(d.path())
            .unwrap()
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|n| n.starts_with(".target.txt."))
            .collect();
        assert!(residuals.is_empty(), "residual tmpfile: {residuals:?}");
        // The parent dir holds exactly the destination.
        let entries: Vec<_> = fs::read_dir(d.path())
            .unwrap()
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(entries, vec!["target.txt".to_string()]);
    }

    #[test]
    fn write_file_atomic_overwrites_existing_and_leaves_no_tmp() {
        let d = TempDir::new().unwrap();
        let dest = d.path().join("dest");
        fs::write(&dest, b"OLD CONTENT that is longer\n").unwrap();
        write_file_atomic(0o644, &dest, b"new\n").unwrap();
        assert_eq!(fs::read(&dest).unwrap(), b"new\n");
        let count = fs::read_dir(d.path()).unwrap().count();
        assert_eq!(count, 1, "only the destination should remain");
    }

    // --- ensure_line_in_file ---

    #[test]
    fn ensure_line_appends_once_then_noops() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("bashrc");
        fs::write(&f, b"# existing\n").unwrap();
        ensure_line_in_file("export FOO=bar", &f).unwrap();
        assert_eq!(
            fs::read_to_string(&f).unwrap(),
            "# existing\nexport FOO=bar\n"
        );
        // Second call is a no-op (grep-before-append; a blind append would dup).
        ensure_line_in_file("export FOO=bar", &f).unwrap();
        assert_eq!(
            fs::read_to_string(&f).unwrap(),
            "# existing\nexport FOO=bar\n"
        );
    }

    #[test]
    fn ensure_line_whole_line_match_not_substring() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("f");
        fs::write(&f, b"export FOO=barbaz\n").unwrap();
        // `-Fx` whole-line: "export FOO=bar" is NOT a whole-line match of
        // "export FOO=barbaz", so it must be appended.
        ensure_line_in_file("export FOO=bar", &f).unwrap();
        assert_eq!(
            fs::read_to_string(&f).unwrap(),
            "export FOO=barbaz\nexport FOO=bar\n"
        );
    }

    #[test]
    fn ensure_line_creates_absent_file() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("new");
        ensure_line_in_file("first", &f).unwrap();
        assert_eq!(fs::read_to_string(&f).unwrap(), "first\n");
    }

    // A file with a non-UTF-8 byte still matches, so the line is appended ONCE.
    // `read_to_string` fails on such a file, and swallowing that failure into
    // "no match" appended a duplicate on every converge run — an `~/.npmrc`
    // carrying a Latin-1 byte in a proxy password accumulated one `prefix=` line
    // per provision.
    #[test]
    fn ensure_line_is_idempotent_on_a_non_utf8_file() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("npmrc");
        // 0xFF is not valid UTF-8 anywhere.
        fs::write(&f, b"//registry/:_authToken=\xffabc\nprefix=/home/agent/.npm-global\n").unwrap();

        for _ in 0..3 {
            ensure_line_in_file("prefix=/home/agent/.npm-global", &f).unwrap();
        }

        let raw = fs::read(&f).unwrap();
        let occurrences = raw
            .split(|b| *b == b'\n')
            .filter(|seg| *seg == b"prefix=/home/agent/.npm-global")
            .count();
        assert_eq!(occurrences, 1, "duplicate appended on a non-UTF-8 file");
        // The undecodable byte survives untouched.
        assert!(raw.contains(&0xff), "existing bytes must be preserved");
    }

    // An unreadable EXISTING file is an error, not a silent "no match" — the
    // append would duplicate on every run and nothing would say why.
    #[test]
    fn ensure_line_refuses_when_it_cannot_read_an_existing_file() {
        let d = TempDir::new().unwrap();
        // A directory where a file is expected: readable path, unreadable content.
        let f = d.path().join("as-a-dir");
        fs::create_dir(&f).unwrap();
        let err = ensure_line_in_file("x", &f).unwrap_err();
        assert!(
            err.to_string().contains("refusing to append blind"),
            "err={err}"
        );
    }

    // A failed atomic write names the operation AND the file. The orchestrator
    // adds only a step name, so a raw io::Error surfaced as
    // "40-path-wiring step failed: No such file or directory (os error 2)" —
    // which of four artefacts, on which operation, needed strace to answer.
    #[test]
    fn atomic_write_failure_names_the_operation_and_the_file() {
        let missing = Path::new("/nonexistent-agentlinux-dir/artefact.conf");
        let err = write_file_atomic(0o644, missing, b"x").unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("artefact.conf"), "no file named: {msg}");
        assert!(msg.contains("failed to"), "no operation named: {msg}");
        // The original kind survives so callers can still match on it.
        assert_eq!(err.kind(), io::ErrorKind::NotFound);
    }

    // The same for a directory step.
    #[test]
    fn ensure_dir_failure_names_the_operation_and_the_path() {
        let d = TempDir::new().unwrap();
        // A FILE where a directory is expected: create_dir_all fails on it.
        let f = d.path().join("not-a-dir");
        fs::write(&f, b"").unwrap();
        let nested = f.join("child");
        let err = ensure_dir(&nested, 0o755, "root:root").unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("child"), "no path named: {msg}");
        assert!(msg.contains("create directory"), "no operation named: {msg}");
    }

    // --- ensure_marker_block ---

    #[test]
    fn marker_block_emits_before_existing_content() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("bashrc");
        fs::write(&f, b"# user line 1\n# user line 2\n").unwrap();
        ensure_marker_block(&f, "agentlinux-path", "export PATH=/x").unwrap();
        // begin\n{body}\n{end}\n THEN the filtered (unchanged) existing — the
        // block must precede the skel .bashrc non-interactive early-return.
        let expected = "# >>> agentlinux-path begin >>>\n\
                        export PATH=/x\n\
                        # <<< agentlinux-path end <<<\n\
                        # user line 1\n\
                        # user line 2\n";
        assert_eq!(fs::read_to_string(&f).unwrap(), expected);
        assert_eq!(mode_of(&f), 0o644);
    }

    // A user who deletes the END marker while hand-editing must not lose the
    // lines below it. The awk filter this ports would drop from the begin marker
    // to EOF; we refuse and leave the file byte-identical.
    #[test]
    fn unterminated_block_refuses_instead_of_deleting_the_rest_of_the_file() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("bashrc");
        let mangled = "# >>> agentlinux-path begin >>>\n\
                       export PATH=/x\n\
                       alias ll='ls -la'\n\
                       alias gs='git status'\n";
        fs::write(&f, mangled).unwrap();

        let err = ensure_marker_block(&f, "agentlinux-path", "export PATH=/y").unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidData);
        assert!(err.to_string().contains("unterminated"), "err={err}");
        // The message has to be actionable — it names the file and the way out.
        assert!(err.to_string().contains("bashrc"), "err={err}");
        assert!(err.to_string().contains("end marker"), "err={err}");
        // And nothing was written.
        assert_eq!(fs::read_to_string(&f).unwrap(), mangled);
    }

    // The refusal is specific to an UNTERMINATED block: a well-formed one still
    // round-trips, so the guard cannot be blamed for a broken happy path.
    #[test]
    fn a_terminated_block_still_round_trips_after_the_guard() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("bashrc");
        fs::write(&f, b"alias ll='ls -la'\n").unwrap();
        ensure_marker_block(&f, "tag", "body").unwrap();
        ensure_marker_block(&f, "tag", "body2").unwrap();
        let content = fs::read_to_string(&f).unwrap();
        assert_eq!(content.matches("# >>> tag begin >>>").count(), 1);
        assert!(content.contains("body2"));
        assert!(content.contains("alias ll='ls -la'"));
    }

    #[test]
    fn marker_block_roundtrip_replaces_and_preserves_outside_content() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("bashrc");
        // A file with a STALE block sandwiched between user content.
        let seed = "# top user content\n\
                    # >>> agentlinux-path begin >>>\n\
                    OLD BODY LINE A\n\
                    OLD BODY LINE B\n\
                    # <<< agentlinux-path end <<<\n\
                    # trailing user content\n";
        fs::write(&f, seed).unwrap();
        // A re-run replaces the block; outside content survives, and exactly ONE
        // block remains (hoisted to the top).
        ensure_marker_block(&f, "agentlinux-path", "NEW BODY").unwrap();
        let expected = "# >>> agentlinux-path begin >>>\n\
                        NEW BODY\n\
                        # <<< agentlinux-path end <<<\n\
                        # top user content\n\
                        # trailing user content\n";
        assert_eq!(fs::read_to_string(&f).unwrap(), expected);
        // Precisely one begin marker.
        assert_eq!(
            fs::read_to_string(&f)
                .unwrap()
                .matches("# >>> agentlinux-path begin >>>")
                .count(),
            1
        );
    }

    #[test]
    fn marker_block_top_roundtrip_idempotent() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("bashrc");
        fs::write(&f, b"user\n").unwrap();
        ensure_marker_block(&f, "t", "B").unwrap();
        let after_first = fs::read_to_string(&f).unwrap();
        // Second identical run is byte-stable (BHV-07-style byte stability).
        ensure_marker_block(&f, "t", "B").unwrap();
        assert_eq!(fs::read_to_string(&f).unwrap(), after_first);
        assert_eq!(after_first, "# >>> t begin >>>\nB\n# <<< t end <<<\nuser\n");
    }

    #[test]
    fn marker_block_on_absent_file_emits_only_the_block() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("does-not-exist-yet");
        ensure_marker_block(&f, "t", "B").unwrap();
        assert_eq!(
            fs::read_to_string(&f).unwrap(),
            "# >>> t begin >>>\nB\n# <<< t end <<<\n"
        );
    }

    // --- ensure_dir ---

    #[test]
    fn ensure_dir_creates_with_mode_and_owner() {
        let d = TempDir::new().unwrap();
        let sub = d.path().join("a/b/c");
        // Own the created dir as our own uid:gid (resolved by name) so the test
        // runs unprivileged. Resolve the current user/group names.
        let uid = nix::unistd::getuid();
        let gid = nix::unistd::getgid();
        let uname = nix::unistd::User::from_uid(uid).unwrap().unwrap().name;
        let gname = nix::unistd::Group::from_gid(gid).unwrap().unwrap().name;
        let owner = format!("{uname}:{gname}");
        ensure_dir(&sub, 0o755, &owner).unwrap();
        assert!(sub.is_dir());
        assert_eq!(mode_of(&sub), 0o755);
        let md = fs::metadata(&sub).unwrap();
        assert_eq!(md.uid(), uid.as_raw());
        assert_eq!(md.gid(), gid.as_raw());
    }

    #[test]
    fn ensure_dir_reasserts_mode_on_drift() {
        let d = TempDir::new().unwrap();
        let sub = d.path().join("drift");
        let uid = nix::unistd::getuid();
        let gid = nix::unistd::getgid();
        let uname = nix::unistd::User::from_uid(uid).unwrap().unwrap().name;
        let gname = nix::unistd::Group::from_gid(gid).unwrap().unwrap().name;
        let owner = format!("{uname}:{gname}");
        // Pre-create with a DRIFTED mode.
        fs::create_dir(&sub).unwrap();
        fs::set_permissions(&sub, fs::Permissions::from_mode(0o700)).unwrap();
        assert_eq!(mode_of(&sub), 0o700);
        // Present arm re-asserts mode unconditionally (drift correction).
        ensure_dir(&sub, 0o755, &owner).unwrap();
        assert_eq!(mode_of(&sub), 0o755);
    }

    // --- ensure_user ---

    #[test]
    fn ensure_user_argv_is_byte_exact() {
        assert_eq!(
            useradd_argv("agent"),
            vec![
                "useradd",
                "--create-home",
                "--shell",
                "/bin/bash",
                "--user-group",
                "agent",
            ]
        );
    }

    #[test]
    fn ensure_user_noop_for_existing_user() {
        // `root` exists on every host — ensure_user must be a no-op and must NOT
        // attempt to spawn useradd (which would fail unprivileged and mutate
        // /etc/passwd if it succeeded). A successful Ok(()) with root present
        // proves the id-gate short-circuits before any spawn.
        assert!(user_exists("root").unwrap());
        ensure_user("root").unwrap();
    }

    #[test]
    fn user_exists_false_for_absent_user() {
        // A name virtually certain to be absent.
        assert!(!user_exists("agentlinux-nonexistent-user-xyzzy").unwrap());
    }
}
