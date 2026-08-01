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
//! - **`ensure_line_in_owned_file`** — `grep -Fxq` semantics: literal, whole-line,
//!   append `line\n` only when no exact whole-line match already exists. Create,
//!   read, append, chmod and chown all happen through ONE descriptor, because
//!   every caller writes into a directory the install user owns while running as
//!   root — re-resolving the path between steps is a TOCTOU. Refuses symlinks,
//!   hardlinks, and anything that is not a regular file.
//! - **`ensure_marker_block`** — the awk-strip + emit-order algorithm is
//!   BYTE-load-bearing: the block (`begin\n{body}\n{end}\n`) is emitted FIRST,
//!   then the filtered remainder. A line equal to `begin` starts skipping, a line
//!   equal to `end` stops skipping, both marker lines are dropped, everything
//!   else survives byte-identical.
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
    ///
    /// Not mutation-tested: skipping the disarm makes `Drop` unlink a path the
    /// rename already consumed, which is a no-op — there is no observable
    /// difference for a test to assert.
    #[cfg_attr(test, mutants::skip)]
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
///
/// Not mutation-tested: every surviving mutant is in the O_EXCL collision-retry
/// arm, which needs two processes to open the same pid+nanosecond name in the
/// same instant. The happy path is exercised by every `write_file_atomic` test.
#[cfg_attr(test, mutants::skip)]
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
    // briefly created with the umask-default mode (mirrors install -m) — and set it
    // on the HANDLE, not the path. `dest.parent()` is the install user's home for
    // `~/.bashrc` and `~/CLAUDE.md`, so a path-based `set_permissions` re-resolves a
    // name the agent controls: the tmp name is unguessable but trivially observable
    // with inotify on your own directory, and unlinking it and symlinking it at
    // `/etc/shadow` in that window turned this into `chmod 0644 /etc/shadow` as
    // root. The rename then failed loudly — after the chmod had already landed.
    nix::sys::stat::fchmod(&file, nix::sys::stat::Mode::from_bits_truncate(mode)).map_err(|e| {
        context(
            &io::Error::from(e),
            &format!("chmod {mode:04o}"),
            dest,
            Some(&tmp),
        )
    })?;
    drop(file);

    fs::rename(&tmp, dest).map_err(|e| context(&e, "rename into place", dest, Some(&tmp)))?;
    // The rename consumed the tmpfile — disarm so Drop does not try to unlink a
    // now-nonexistent path.
    guard.disarm();
    // fsync the DIRECTORY, not just the file. `sync_all` above made the tmpfile's
    // CONTENT durable; it says nothing about the directory entry the rename created.
    // Lose that entry to a power cut and a first-time create — /etc/sudoers.d/
    // agentlinux, /etc/agentlinux.env — is simply absent on the next boot, after
    // the provisioner printed "complete". (An overwrite degrades more gently: the
    // old entry survives.) Narrow on ext4's default data=ordered, wide open on XFS
    // and on data=writeback.
    sync_parent_dir(dest);
    Ok(())
}

/// fsync a file's parent directory, making a just-created or just-renamed directory
/// entry durable. Best-effort by design: some filesystems refuse `O_RDONLY` fsync on
/// a directory, and a provisioner must not abort a correct write because the kernel
/// declined a durability hint. Failures are silent because the caller has already
/// succeeded at the part that matters — this only narrows a crash window.
pub(crate) fn sync_parent_dir(dest: &Path) {
    use std::os::unix::fs::OpenOptionsExt;
    // `Path::new("f").parent()` is Some("") — not None — so the `"."` fallback only
    // fires for a path with no parent component at all. Map the empty case too, or
    // the open fails ENOENT and the sync silently does nothing.
    let dir = match dest.parent() {
        Some(p) if !p.as_os_str().is_empty() => p,
        _ => Path::new("."),
    };
    // O_DIRECTORY|O_NONBLOCK: this crate's contract (ADR-022) is that every wait is
    // bounded, and a plain `File::open` on a FIFO blocks in open(2) until a writer
    // appears. The rename that just succeeded proves the parent was a directory, so
    // this is defence in depth rather than a live path — but "unreachable today"
    // is not a reason to leave an unbounded open in the write path.
    if let Ok(handle) = fs::OpenOptions::new()
        .read(true)
        .custom_flags((nix::fcntl::OFlag::O_DIRECTORY | nix::fcntl::OFlag::O_NONBLOCK).bits())
        .open(dir)
    {
        let _ = handle.sync_all();
    }
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

/// `ensure_line_in_file` + create-if-absent + chmod + chown, done through ONE file
/// descriptor.
///
/// Every caller of this used to be a four-call sequence — `create_if_absent_0644`,
/// `ensure_line_in_file`, `set_permissions`, `chown_by_name` — each re-resolving
/// the PATH. That is a root-side TOCTOU against a directory the install user owns:
/// hardening only the first call left the other three following a symlink the
/// agent could swap in afterwards, and one call site guarded the hardened helper
/// behind `if !path.exists()` (which follows), so a NON-dangling symlink skipped it
/// entirely. Root then appended to, chmod'd and chowned whatever the link pointed
/// at. Holding one fd across the whole operation removes the re-resolution: after
/// the open, every syscall addresses the inode, not the name.
///
/// Refusals, all before any write:
/// - a symlink at `path` (`O_NOFOLLOW` → ELOOP);
/// - anything not a regular file — a FIFO here would otherwise block the
///   provisioner forever in the read, unbounded, as root;
/// - `nlink > 1`. A hardlink is a regular file and passes every other check, so
///   `ln /etc/shadow ~/.npmrc` would have us append to and chown the real inode.
///   The kernel's `fs.protected_hardlinks` normally prevents creating that link,
///   but it is a sysctl an operator can turn off and nothing here should depend on
///   it silently.
///
/// `mode_if_created` is applied ONLY when this call creates the file. An existing
/// file keeps its mode: `~/.npmrc` holds npm auth tokens, and re-asserting 0644 on
/// every converge run silently widened an operator's deliberate 0600 back to
/// world-readable.
pub fn ensure_line_in_owned_file(
    line: &str,
    path: &Path,
    owner: &str,
    mode_if_created: u32,
    chown: fn(&Path, &str) -> io::Result<()>,
) -> io::Result<()> {
    use std::io::{Read, Seek, SeekFrom};
    use std::os::unix::fs::{MetadataExt, OpenOptionsExt};

    let nofollow = nix::fcntl::OFlag::O_NOFOLLOW.bits();
    let (mut file, created) = match fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .custom_flags(nofollow)
        .open(path)
    {
        Ok(f) => (f, true),
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {
            let f = fs::OpenOptions::new()
                .read(true)
                .write(true)
                .custom_flags(nofollow)
                .open(path)
                .map_err(|e| {
                    // ELOOP is O_NOFOLLOW refusing a symlink — the security case,
                    // worth naming rather than surfacing as "too many levels".
                    if e.raw_os_error() == Some(nix::errno::Errno::ELOOP as i32) {
                        io::Error::new(
                            io::ErrorKind::InvalidInput,
                            format!(
                                "refusing to write {} as root: it is a symlink",
                                path.display()
                            ),
                        )
                    } else {
                        context(&e, "open", path, None)
                    }
                })?;
            (f, false)
        }
        Err(e) => return Err(context(&e, "create", path, None)),
    };

    let md = file
        .metadata()
        .map_err(|e| context(&e, "stat the open handle for", path, None))?;
    if !md.is_file() || md.nlink() > 1 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "refusing to write {} as root: it is {}",
                path.display(),
                if md.nlink() > 1 {
                    "a hardlink to another file"
                } else {
                    "not a regular file"
                }
            ),
        ));
    }

    let mut existing = Vec::new();
    file.read_to_end(&mut existing)
        .map_err(|e| context(&e, "read", path, None))?;
    // `grep -Fxq` semantics on BYTES: literal, whole-line, encoding-agnostic. See
    // `ensure_line_in_file` for why this must not go through `read_to_string`.
    let present = existing
        .split(|b| *b == b'\n')
        .any(|seg| seg == line.as_bytes());

    if !present {
        // Append at the true end, and in ONE write: a split write that fails
        // between the bytes and the newline leaves a line the next whole-line
        // match can never see, so the run after it appends a duplicate.
        file.seek(SeekFrom::End(0))
            .map_err(|e| context(&e, "seek to append to", path, None))?;
        let mut record = Vec::with_capacity(line.len() + 2);
        // A file whose last line lacks a trailing newline would otherwise get our
        // record glued onto it, producing one corrupt line instead of two good ones.
        if !existing.is_empty() && !existing.ends_with(b"\n") {
            record.push(b'\n');
        }
        record.extend_from_slice(line.as_bytes());
        record.push(b'\n');
        file.write_all(&record)
            .map_err(|e| context(&e, "append to", path, None))?;
    }

    // NARROW, never widen. "Only on create" was too weak in the other direction:
    // the previous code forced 0644 every run, which accidentally repaired a
    // pre-existing world-WRITABLE `~/.npmrc` (0666 — a brownfield host, a tarball
    // unpacked with a zero umask). Leaving that alone means any local account can
    // write `prefix=` or npm's `script-shell` into a file we then chown to the
    // agent, and the next `npm install -g` runs against an attacker-chosen prefix
    // and shell. So: on create, exactly `mode_if_created`; on an existing file,
    // keep whatever the operator chose but strip group/other WRITE, which cannot
    // widen anything and cannot re-expose the 0600 token file the mode-preserving
    // behaviour exists to protect.
    let target_mode = if created {
        Some(mode_if_created)
    } else {
        let current = md.mode() & 0o7777;
        let narrowed = current & !0o022;
        (narrowed != current).then_some(narrowed)
    };
    if let Some(m) = target_mode {
        nix::sys::stat::fchmod(&file, nix::sys::stat::Mode::from_bits_truncate(m))
            .map_err(|e| context(&io::Error::from(e), "chmod", path, None))?;
    }
    // Through the caller's effect rather than an `fchown` on the handle above.
    // The one shared copy would resolve `owner` against the real passwd DB, and a
    // step test running under a TempDir with a fixture install user fails at
    // "unknown user" — the same reason `create_if_absent_0644` takes it. The
    // symlink hole stays shut regardless: the production effect
    // (`Effects::chown`) is `chown_by_name_nofollow`, which re-opens O_NOFOLLOW
    // and chowns the descriptor.
    chown(path, owner)
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
/// Operates on BYTES, not `&str`. The file being edited is a user's `~/.bashrc`
/// or `~/CLAUDE.md`, which is theirs to put anything in — a Latin-1 character in
/// a comment is enough to make it invalid UTF-8. Filtering bytes preserves every
/// surviving line exactly as it was, including ones we cannot decode.
fn strip_marker_block(existing: &[u8], begin: &str, end: &str) -> io::Result<Vec<Vec<u8>>> {
    let mut out: Vec<Vec<u8>> = Vec::new();
    let mut in_block = false;
    // awk reads records split on '\n'; a trailing '\n' does NOT create a final
    // empty record. Emulate by iterating lines and dropping the final empty
    // segment that `split` produces for newline-terminated input.
    let mut segments: Vec<&[u8]> = existing.split(|b| *b == b'\n').collect();
    if existing.ends_with(b"\n") {
        // The last segment is the empty slice after the final '\n' — awk never
        // sees it as a record.
        segments.pop();
    } else if existing.is_empty() {
        // No records at all.
        segments.clear();
    }
    for line in segments {
        if line == begin.as_bytes() {
            in_block = true;
            continue;
        }
        if line == end.as_bytes() {
            in_block = false;
            continue;
        }
        if !in_block {
            out.push(line.to_vec());
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

/// `ensure_marker_block <file> <tag>` — replace the content between
/// `# >>> <tag> begin >>>` / `# <<< <tag> end <<<` markers with `body`,
/// preserving all content OUTSIDE the markers byte-identical. Written via
/// `write_file_atomic(0o644, …)`.
///
/// The exact marker strings and the emit order are byte-load-bearing: the block
/// is emitted first, then the filtered remainder. Re-running replaces the block
/// in place, leaving exactly ONE block.
///
/// The block is always written at the TOP of the file. That is required, not
/// incidental: the skel `.bashrc` early-returns for non-interactive shells, so an
/// agentlinux block that must influence `sudo -u agent bash -c …` has to precede
/// that guard. Every caller needs this, so there is no placement knob to get
/// wrong.
///
/// # An unreadable file is refused, not treated as empty
/// The read is byte-oriented and a present-but-unreadable file is an error. The
/// previous `read_to_string(file).unwrap_or_default()` turned ANY read failure —
/// one non-UTF-8 byte, EACCES, EIO — into an empty "existing", so the filtered
/// remainder was empty and the atomic write replaced the whole file with just the
/// agentlinux block. A `~/.bashrc` or `~/CLAUDE.md` carrying a single Latin-1
/// character lost every line outside the markers. Same class as the unterminated
/// block above, and on a hotter path: the DOC-02 write runs on the REUSE branch
/// too, i.e. against files an existing operator already owns.
pub fn ensure_marker_block(file: &Path, tag: &str, body: &str) -> io::Result<()> {
    let begin = format!("# >>> {tag} begin >>>");
    let end = format!("# <<< {tag} end <<<");

    // `read_regular_file`, not `fs::read`: this runs as root on `~/.bashrc` and
    // `~/CLAUDE.md`, both inside a directory the install user owns. A plain read
    // follows symlinks — root would read `/etc/shadow`, `strip_marker_block` would
    // preserve every line of it, and `write_file_atomic` would publish the result
    // as a file the agent then owns. It also blocks forever on a FIFO.
    let existing = match read_regular_file(file) {
        Ok(Some(bytes)) => bytes,
        // Absent is the normal first-run case: no records to preserve.
        Ok(None) => Vec::new(),
        Err(e) => {
            return Err(io::Error::new(
                e.kind(),
                format!(
                    "cannot read {} to preserve the content outside the \
                     `{tag}` block (refusing to overwrite it blind): {e}",
                    file.display()
                ),
            ))
        }
    };
    let filtered = strip_marker_block(&existing, &begin, &end)
        .map_err(|e| io::Error::new(e.kind(), format!("{}: {e}", file.display())))?;

    // The block itself, printf '%s\n' three times → begin\n{body}\n{end}\n.
    let mut out: Vec<u8> = format!("{begin}\n{body}\n{end}\n").into_bytes();

    // The filtered remainder: awk prints each surviving record followed by a
    // newline (`print`), so join with '\n' AND add a trailing '\n' when there is
    // any content — reproducing the awk output byte-for-byte.
    for line in &filtered {
        out.extend_from_slice(line);
        out.push(b'\n');
    }

    write_file_atomic(0o644, file, &out)
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
/// Not mutation-tested: killing `-> Ok(())` requires actually creating a user,
/// which needs root and mutates the host. The two halves that CAN be tested are:
/// [`useradd_argv`] (the exact argv) and [`user_exists`] (the id-gate).
#[cfg_attr(test, mutants::skip)]
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
///
/// stdin is `/dev/null`. Under `curl … | sudo bash` the installer's own stdin is
/// the SCRIPT being executed, so a tool that prompts (`userdel` on a busy user,
/// `visudo` falling back to interactive) would consume the rest of the installer
/// and run whatever it read.
fn run_bounded(argv: &[String]) -> io::Result<i32> {
    let (program, args) = argv
        .split_first()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "run_bounded: empty argv"))?;
    let mut cmd = Command::new(program);
    // stdout/stderr stay INHERITED so `useradd: user 'x' is currently used by
    // process 123` reaches the console and the transcript. Capturing it to fold
    // into the error string would need a second bounded drain for no gain — these
    // tools are terse and the operator is already reading this output.
    cmd.args(args).stdin(std::process::Stdio::null());
    crate::dispatcher::own_process_group(&mut cmd);
    let mut child = cmd.spawn()?;
    let (code, _timed_out) = crate::dispatcher::wait_with_timeout(
        &mut child,
        Some(ADMIN_TOOL_TIMEOUT_MS),
        &argv.join(" "),
    );
    Ok(code)
}

/// `run_bounded` for a `&str` argv — the form the teardown paths already have.
pub(crate) fn run_bounded_argv(argv: &[&str]) -> io::Result<i32> {
    let owned: Vec<String> = argv.iter().map(|s| (*s).to_string()).collect();
    run_bounded(&owned)
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
    use std::os::unix::fs::OpenOptionsExt;

    let (uid, gid) = resolve_owner(owner)?;
    if !path.is_dir() {
        fs::create_dir_all(path).map_err(|e| context(&e, "create directory", path, None))?;
    }

    // Re-assert mode + owner through an O_NOFOLLOW|O_DIRECTORY HANDLE, not the path.
    //
    // Eight of this function's call sites are directories inside the install user's
    // own home (`~/.local`, `~/.local/bin`, `~/.npm-global{,/bin,/lib}`, the rebase
    // target). The previous shape resolved the path three times — `is_dir()`,
    // `set_permissions`, `chown` — and all three FOLLOW symlinks. That was a full
    // root-compromise primitive requiring no race whatsoever:
    //
    //     agent$ rm -rf ~/.local && ln -s /etc ~/.local
    //     root#  agentlinux provision      # any re-run, upgrade or repair
    //            => chmod 0755 /etc ; chown agent:agent /etc
    //
    // `fs.protected_symlinks` does not help — it covers world-writable sticky
    // directories like /tmp, not a link the agent owns in their own home, and it
    // gates follows in open(2), not chown(2)/chmod(2).
    //
    // `create_dir_all` above still resolves by path, so a symlink-to-a-directory is
    // not created anew; the handle below is what decides whether we then mutate it.
    // O_DIRECTORY makes "not a directory" ENOTDIR rather than something we chmod.
    let handle = fs::OpenOptions::new()
        .read(true)
        .custom_flags(
            (nix::fcntl::OFlag::O_NOFOLLOW
                | nix::fcntl::OFlag::O_DIRECTORY
                | nix::fcntl::OFlag::O_NONBLOCK)
                .bits(),
        )
        .open(path)
        .map_err(|e| {
            // With O_DIRECTORY, Linux reports a symlink at the final component as
            // ENOTDIR rather than the ELOOP that O_NOFOLLOW alone would give — so
            // check what is actually there rather than inferring from the errno,
            // otherwise the most security-relevant refusal prints "Not a directory".
            let is_link = fs::symlink_metadata(path)
                .map(|m| m.file_type().is_symlink())
                .unwrap_or(false);
            if is_link {
                io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!(
                        "refusing to chmod/chown {}: it is a symlink, not a directory \
                         — as root that would hand its TARGET to {owner}",
                        path.display()
                    ),
                )
            } else {
                context(&e, "open directory to chmod/chown", path, None)
            }
        })?;

    nix::sys::stat::fchmod(&handle, nix::sys::stat::Mode::from_bits_truncate(mode)).map_err(
        |e| {
            context(
                &io::Error::from(e),
                &format!("chmod {mode:04o}"),
                path,
                None,
            )
        },
    )?;
    nix::unistd::fchown(
        &handle,
        Some(nix::unistd::Uid::from_raw(uid)),
        Some(nix::unistd::Gid::from_raw(gid)),
    )
    .map_err(|e| {
        context(
            &io::Error::from(e),
            &format!("chown to {owner}"),
            path,
            None,
        )
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

/// Largest file any of these helpers will read into memory.
///
/// These reads happen as ROOT on files the install user can replace at will. A
/// sparse `~/.npmrc` of arbitrary size costs the agent nothing to create and would
/// otherwise be read whole, OOM-killing the provisioner — or, worse, something
/// else on the host. The real files are hundreds of bytes; 8 MiB is far past any
/// legitimate `.npmrc`, `.bashrc` or `CLAUDE.md`.
const MAX_CONFIG_BYTES: u64 = 8 * 1024 * 1024;

/// Open `path` for read+write, refusing anything that is not a plain, singly-linked
/// regular file, and never following a symlink at the final component.
///
/// This is the one primitive for touching a file inside a directory the install
/// user owns while running as root. Four hazards, all closed before the caller
/// sees a handle:
///
/// - **symlink** → `O_NOFOLLOW` gives ELOOP. Following one lets root read
///   `/etc/shadow` into an agent-readable file, or hand `/etc/ld.so.preload` to the
///   agent.
/// - **FIFO** → would block in `open(2)` forever with no writer. `O_RDWR` returns
///   immediately on a FIFO where `O_RDONLY` blocks, and `O_NONBLOCK` covers the
///   rest; the regular-file check then rejects it. Note the READ/WRITE MODE is what
///   prevents the hang, not the fstat — a refactor to "open read-only" would
///   reintroduce an unbounded root-side hang before any check could run.
/// - **hardlink** (`nlink > 1`) → a hardlink is a regular file and passes every
///   other test, so `ln /etc/shadow ~/.npmrc` would otherwise work. The kernel's
///   `fs.protected_hardlinks` normally prevents creating it, but that is a sysctl
///   an operator can disable and nothing here should depend on it silently.
/// - **oversized** → see `MAX_CONFIG_BYTES`.
///
/// One invariant this CANNOT enforce, stated so it is not forgotten: `O_NOFOLLOW`
/// constrains only the FINAL component. Every ancestor must be root-owned. That
/// holds today because homes are `/home/<user>` and `/home` is root-owned.
fn open_regular_nofollow(path: &Path, doing: &str) -> io::Result<fs::File> {
    use std::os::unix::fs::{MetadataExt, OpenOptionsExt};

    let file = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags((nix::fcntl::OFlag::O_NOFOLLOW | nix::fcntl::OFlag::O_NONBLOCK).bits())
        .open(path)
        .map_err(|e| {
            if e.raw_os_error() == Some(nix::errno::Errno::ELOOP as i32) {
                io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("refusing to {doing} {}: it is a symlink", path.display()),
                )
            } else {
                context(&e, &format!("open to {doing}"), path, None)
            }
        })?;

    let md = file
        .metadata()
        .map_err(|e| context(&e, "stat the open handle for", path, None))?;
    if !md.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "refusing to {doing} {}: it is not a regular file",
                path.display()
            ),
        ));
    }
    if md.nlink() > 1 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "refusing to {doing} {}: it has {} hard links, so writing it would \
                 modify another file (if this is a backup/dedup tool's doing, break \
                 the link and re-run)",
                path.display(),
                md.nlink()
            ),
        ));
    }
    if md.size() > MAX_CONFIG_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "refusing to {doing} {}: {} bytes exceeds the {MAX_CONFIG_BYTES}-byte \
                 config limit",
                path.display(),
                md.size()
            ),
        ));
    }
    Ok(file)
}

/// Read a config file the install user can influence, as root, safely.
///
/// `Ok(None)` when absent — the normal first-run case. Every other hazard is an
/// `Err` naming the path, never a silent empty read: a caller that treats "cannot
/// read" as "no content" rewrites the file from scratch and destroys whatever was
/// there.
pub fn read_regular_file(path: &Path) -> io::Result<Option<Vec<u8>>> {
    use std::io::Read;
    match open_regular_nofollow(path, "read") {
        Ok(mut f) => {
            let mut buf = Vec::new();
            f.read_to_end(&mut buf)
                .map_err(|e| context(&e, "read", path, None))?;
            Ok(Some(buf))
        }
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e),
    }
}

/// `chown <owner> <path>` where `owner` is `"user:group"` — the ONE chown helper,
/// and it refuses to traverse a symlink at the final component.
///
/// Five provisioner modules previously carried byte-identical private copies of a
/// path-based chown, each re-resolving the same passwd/group lookups with its own
/// error wording; a caller that needs to chown a whole TREE uses
/// `provision::remediate_npm_prefix::chown_recursive_by_name`.
///
/// The nofollow half matters because root chowns paths inside a directory the
/// install user owns.
/// The plain path-based chown follows links, so an agent that swaps a symlink in
/// after we wrote the file gets the link's TARGET handed to it. The open pins the
/// inode; the `fchown` on that handle cannot be redirected afterwards.
///
/// It goes through `open_regular_nofollow`, which matters for two reasons beyond
/// the symlink: a plain `O_RDONLY|O_NOFOLLOW` open BLOCKS INDEFINITELY on a FIFO
/// (verified — `O_RDWR` returns immediately, `O_RDONLY` waits for a writer), so an
/// agent who wins the window between a rename and this chown could wedge the
/// provisioner forever as root; and without an `nlink` check a hardlink to a
/// root-owned file is a regular non-symlink file that would be chowned to the
/// agent, leaving `fs.protected_hardlinks` as a silent load-bearing dependency.
pub fn chown_by_name_nofollow(path: &Path, owner: &str) -> io::Result<()> {
    let handle = open_regular_nofollow(path, "chown")?;
    let (uid, gid) = resolve_owner(owner)?;
    nix::unistd::fchown(
        &handle,
        Some(nix::unistd::Uid::from_raw(uid)),
        Some(nix::unistd::Gid::from_raw(gid)),
    )
    .map_err(|e| {
        context(
            &io::Error::from(e),
            &format!("chown to {owner}"),
            path,
            None,
        )
    })
}

/// `chown -h <owner> <link>` — change the SYMLINK itself, never its target.
///
/// The counterpart to [`chown_by_name_nofollow`] for the caller that must not
/// dereference: `registry_cli` chowns the `agentlinux` symlink it plants, and
/// following it would hand ownership of the binary the link points at.
pub fn chown_symlink_by_name(link: &Path, owner: &str) -> io::Result<()> {
    let (uid, gid) = resolve_owner(owner)?;
    std::os::unix::fs::lchown(link, Some(uid), Some(gid))
        .map_err(|e| io::Error::other(format!("chown -h {} failed: {e}", link.display())))
}

/// Create `path` empty at 0644 owned by `owner` if it does not exist; leave a
/// present file completely untouched (the caller's `ensure_line_in_file` mutates
/// it). Mirrors `install -m 0644 -o <u> -g <g> /dev/null <path>`.
///
/// Refuses to traverse a symlink at the final component. This runs as ROOT against
/// paths inside the install user's own home (`~/.npmrc`, `~/.bashrc`) on every
/// converge run, so the previous `exists()` + `File::create` + path-based chown —
/// all three of which follow symlinks — let an agent that plants
/// `~/.npmrc -> /etc/ld.so.preload` have that file created and chowned to itself.
/// No race was required, just a dangling symlink sitting there before a re-run.
///
/// `O_CREAT|O_EXCL|O_NOFOLLOW` collapses the check and the create into one atomic
/// syscall: EEXIST covers both "already a real file, leave it alone" and "something
/// is in the way", and `lstat` then tells those apart WITHOUT following. The MODE
/// is applied to the file DESCRIPTOR, so it cannot be redirected onto a different
/// inode.
///
/// `chown` is a parameter rather than a direct [`chown_by_name_nofollow`] call so a
/// provisioner step can pass its injected effect: the one shared copy resolves
/// `owner` against the real passwd DB, and a step test running under a TempDir with
/// a fixture install user fails at "unknown user" — which is what pushed each
/// caller to keep a private copy in the first place. The seam does NOT reopen the
/// symlink hole, because the production effect ([`Effects::chown`], wired to
/// [`chown_by_name_nofollow`]) re-opens `O_NOFOLLOW` and `fchown`s the handle. What
/// remains is a swap for another REGULAR file in the window, which buys an attacker
/// who already owns the directory nothing: a hardlink to a root-owned file is
/// refused by the `nlink` check on the far side.
pub fn create_if_absent_0644(
    path: &Path,
    owner: &str,
    chown: fn(&Path, &str) -> io::Result<()>,
) -> io::Result<()> {
    use std::os::unix::fs::OpenOptionsExt;

    let file = match fs::OpenOptions::new()
        .write(true)
        .create_new(true) // O_CREAT | O_EXCL
        .custom_flags(libc_o_nofollow())
        .open(path)
    {
        Ok(f) => f,
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {
            // Something occupies the path. A regular file is the normal re-run case
            // — leave it completely untouched, as documented. Anything else (a
            // symlink, a FIFO, a device) is refused loudly rather than written
            // through: this is a root-owned write, and the caller cannot tell from
            // a silent success that it landed somewhere else.
            let md = fs::symlink_metadata(path)
                .map_err(|e| context(&e, "stat the existing", path, None))?;
            if md.file_type().is_symlink() || !md.is_file() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!(
                        "refusing to write {} as root: it is a {}, not a regular file",
                        path.display(),
                        if md.file_type().is_symlink() {
                            "symlink"
                        } else {
                            "non-regular file"
                        }
                    ),
                ));
            }
            return Ok(());
        }
        Err(e) => return Err(context(&e, "create", path, None)),
    };

    nix::sys::stat::fchmod(&file, nix::sys::stat::Mode::from_bits_truncate(0o644))
        .map_err(|e| context(&io::Error::from(e), "chmod 0644", path, None))?;
    chown(path, owner)
}

/// `O_NOFOLLOW` as a raw flag for `custom_flags`.
fn libc_o_nofollow() -> i32 {
    nix::fcntl::OFlag::O_NOFOLLOW.bits()
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
///
/// Not mutation-tested: this wrapper only binds the program name, and killing
/// `-> Ok(())` here would need a real `visudo` on the test host. Both arms of the
/// logic live in [`visudo_validate_with`], which is tested.
#[cfg_attr(test, mutants::skip)]
pub fn visudo_validate(file: &Path) -> io::Result<()> {
    visudo_validate_with("visudo", file)
}

/// [`visudo_validate`] against a named program.
///
/// The program is a parameter so the ACCEPT and REJECT arms are both reachable
/// from a test (point it at `true`/`false`) on a host that may not ship visudo
/// at all. Guarding a test with "if visudo exists" would delete the assertion on
/// the minimal container images this code most needs to work on.
///
/// The wait goes through [`run_bounded`] like every other admin tool this module
/// shells out to: a `visudo` wedged on a locked `/etc/sudoers` would otherwise
/// block step 20 forever, as root, with nothing printed (ADR-022).
pub fn visudo_validate_with(program: &str, file: &Path) -> io::Result<()> {
    let argv = vec![
        program.to_string(),
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
    use std::os::unix::fs::{MetadataExt, PermissionsExt};
    use tempfile::TempDir;

    fn mode_of(p: &Path) -> u32 {
        fs::metadata(p).unwrap().permissions().mode() & 0o7777
    }

    /// `user:group` for the account running the tests. `fchown` to your own
    /// uid/gid succeeds unprivileged, so the ownership half of
    /// `ensure_line_in_owned_file` is exercised rather than skipped.
    fn self_owner() -> String {
        let u = nix::unistd::User::from_uid(nix::unistd::getuid())
            .ok()
            .flatten()
            .map(|u| u.name)
            .unwrap_or_else(|| "root".to_string());
        let g = nix::unistd::Group::from_gid(nix::unistd::getgid())
            .ok()
            .flatten()
            .map(|g| g.name)
            .unwrap_or_else(|| u.clone());
        format!("{u}:{g}")
    }

    /// REGRESSION: `ensure_dir` must not follow a symlink at the target.
    ///
    /// Eight call sites are directories inside the install user's own home. The
    /// path-based shape gave a full root-compromise primitive needing NO race:
    /// `ln -s /etc ~/.local` and the next `provision` did `chmod 0755 /etc` +
    /// `chown agent:agent /etc`. `fs.protected_symlinks` does not cover this — it
    /// guards world-writable sticky dirs, and it gates open(2), not chmod/chown.
    #[test]
    fn ensure_dir_refuses_a_symlink_and_leaves_the_target_alone() {
        let td = TempDir::new().unwrap();
        let victim = td.path().join("etc-stand-in");
        fs::create_dir(&victim).unwrap();
        fs::set_permissions(&victim, fs::Permissions::from_mode(0o700)).unwrap();
        let link = td.path().join(".local");
        std::os::unix::fs::symlink(&victim, &link).unwrap();

        let err = ensure_dir(&link, 0o755, &self_owner())
            .expect_err("a symlink at the target must be refused, not followed");
        assert!(err.to_string().contains("symlink"), "err={err}");
        assert_eq!(
            mode_of(&victim),
            0o700,
            "followed the symlink and chmod'd the target — as root this hands over /etc"
        );
    }

    /// The ordinary cases still work: a real directory gets its mode asserted on
    /// both the create and the already-present arm.
    #[test]
    fn ensure_dir_creates_and_reasserts_mode() {
        let td = TempDir::new().unwrap();
        let d = td.path().join("nested/dir");
        ensure_dir(&d, 0o755, &self_owner()).unwrap();
        assert_eq!(mode_of(&d), 0o755);

        fs::set_permissions(&d, fs::Permissions::from_mode(0o700)).unwrap();
        ensure_dir(&d, 0o755, &self_owner()).unwrap();
        assert_eq!(
            mode_of(&d),
            0o755,
            "drift was not corrected on the present arm"
        );
    }

    /// A world-writable config file must be narrowed, not left alone. The
    /// mode-preserving fix went too far in the other direction: the code it
    /// replaced forced 0644 every run, which accidentally repaired a 0666
    /// `~/.npmrc`. Leaving that writable lets any local account inject `prefix=` or
    /// npm's `script-shell` into a file we then chown to the agent.
    #[test]
    fn ensure_line_narrows_a_world_writable_file_but_keeps_a_tight_one() {
        let td = TempDir::new().unwrap();

        let loose = td.path().join("loose-npmrc");
        fs::write(&loose, b"# brownfield\n").unwrap();
        fs::set_permissions(&loose, fs::Permissions::from_mode(0o666)).unwrap();
        ensure_line_in_owned_file(
            "prefix=/x",
            &loose,
            &self_owner(),
            0o644,
            chown_by_name_nofollow,
        )
        .unwrap();
        assert_eq!(
            mode_of(&loose) & 0o022,
            0,
            "left a world-writable file we then chowned to the agent"
        );

        // A deliberately TIGHT file keeps its mode — narrowing must not widen.
        let tight = td.path().join("tight-npmrc");
        fs::write(&tight, b"//registry/:_authToken=s\n").unwrap();
        fs::set_permissions(&tight, fs::Permissions::from_mode(0o600)).unwrap();
        ensure_line_in_owned_file(
            "prefix=/x",
            &tight,
            &self_owner(),
            0o644,
            chown_by_name_nofollow,
        )
        .unwrap();
        assert_eq!(mode_of(&tight), 0o600, "widened a token file");
    }

    // --- create_if_absent_0644 symlink safety ---

    /// This helper runs as ROOT against `~/.npmrc` and `~/.bashrc` — paths the
    /// install user controls the directory of. A symlink planted there must never
    /// be written through, or a re-provision hands the agent any file on the host.
    /// The owner argument is deliberately a name that cannot resolve: the refusal
    /// has to happen BEFORE any ownership work, so the test proves the symlink was
    /// rejected rather than that the chown merely failed afterwards.
    #[test]
    fn create_if_absent_refuses_to_follow_a_planted_symlink() {
        let td = TempDir::new().unwrap();
        let victim = td.path().join("victim-must-not-be-created");
        let link = td.path().join(".npmrc");
        std::os::unix::fs::symlink(&victim, &link).unwrap();

        let err = create_if_absent_0644(
            &link,
            "no-such-user-cf19a4:no-such-group",
            chown_by_name_nofollow,
        )
        .expect_err("a symlink at the target must be refused, not followed");
        assert!(
            err.to_string().contains("symlink"),
            "the error must name the real cause; got: {err}"
        );
        assert!(
            !victim.exists(),
            "followed the symlink and created the target — as root this is an \
             arbitrary-file-create primitive"
        );
    }

    /// The normal re-run case must still be a silent no-op, and must NOT rewrite
    /// mode or owner on a file the operator may have deliberately adjusted.
    #[test]
    fn create_if_absent_leaves_an_existing_regular_file_untouched() {
        let td = TempDir::new().unwrap();
        let p = td.path().join(".npmrc");
        fs::write(&p, b"prefix=/custom\n").unwrap();
        fs::set_permissions(&p, fs::Permissions::from_mode(0o600)).unwrap();

        // Owner is unresolvable on purpose — an existing file must return before
        // any ownership work is attempted.
        create_if_absent_0644(
            &p,
            "no-such-user-cf19a4:no-such-group",
            chown_by_name_nofollow,
        )
        .unwrap();

        assert_eq!(fs::read(&p).unwrap(), b"prefix=/custom\n");
        assert_eq!(mode_of(&p), 0o600, "an existing file's mode was rewritten");
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

    // --- ensure_line_in_owned_file ---

    #[test]
    fn ensure_line_appends_once_then_noops() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("bashrc");
        fs::write(&f, b"# existing\n").unwrap();
        ensure_line_in_owned_file(
            "export FOO=bar",
            &f,
            &self_owner(),
            0o644,
            chown_by_name_nofollow,
        )
        .unwrap();
        assert_eq!(
            fs::read_to_string(&f).unwrap(),
            "# existing\nexport FOO=bar\n"
        );
        // Second call is a no-op (grep-before-append; a blind append would dup).
        ensure_line_in_owned_file(
            "export FOO=bar",
            &f,
            &self_owner(),
            0o644,
            chown_by_name_nofollow,
        )
        .unwrap();
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
        ensure_line_in_owned_file(
            "export FOO=bar",
            &f,
            &self_owner(),
            0o644,
            chown_by_name_nofollow,
        )
        .unwrap();
        assert_eq!(
            fs::read_to_string(&f).unwrap(),
            "export FOO=barbaz\nexport FOO=bar\n"
        );
    }

    #[test]
    fn ensure_line_creates_absent_file() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("new");
        ensure_line_in_owned_file("first", &f, &self_owner(), 0o644, chown_by_name_nofollow)
            .unwrap();
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
        fs::write(
            &f,
            b"//registry/:_authToken=\xffabc\nprefix=/home/agent/.npm-global\n",
        )
        .unwrap();

        for _ in 0..3 {
            ensure_line_in_owned_file(
                "prefix=/home/agent/.npm-global",
                &f,
                &self_owner(),
                0o644,
                chown_by_name_nofollow,
            )
            .unwrap();
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

    // Something that is not a regular file is an error, not a silent "no match".
    // Appending blind would duplicate the line on every converge run with nothing
    // saying why; and for the FIFO case below, reading it would block the
    // provisioner forever, as root, with no timeout on that path.
    #[test]
    fn ensure_line_refuses_a_directory_naming_the_path() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("as-a-dir");
        fs::create_dir(&f).unwrap();
        let err = ensure_line_in_owned_file("x", &f, &self_owner(), 0o644, chown_by_name_nofollow)
            .unwrap_err();
        assert!(
            err.to_string().contains("as-a-dir"),
            "the refusal must name the path it refused; err={err}"
        );
    }

    /// A FIFO planted where a config file is expected. Without the regular-file
    /// check this blocks in the read forever — an unbounded root-side hang inside
    /// step 30, which is precisely what ADR-022 forbids. Guarded by a worker
    /// thread so a regression fails the suite instead of wedging it.
    #[test]
    fn ensure_line_refuses_a_fifo_rather_than_blocking_on_it() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("npmrc-as-fifo");
        nix::unistd::mkfifo(&f, nix::sys::stat::Mode::from_bits_truncate(0o644)).unwrap();

        let (tx, rx) = std::sync::mpsc::channel();
        let owner = self_owner();
        let path = f.clone();
        std::thread::spawn(move || {
            let _ = tx.send(
                ensure_line_in_owned_file("x", &path, &owner, 0o644, chown_by_name_nofollow)
                    .is_err(),
            );
        });
        match rx.recv_timeout(std::time::Duration::from_secs(5)) {
            Ok(errored) => assert!(errored, "a FIFO must be refused, not written to"),
            Err(_) => panic!(
                "ensure_line_in_owned_file blocked on a FIFO — unbounded root-side \
                 hang in the provisioner"
            ),
        }
    }

    /// A hardlink to a sensitive file is a REGULAR file and passes every other
    /// check, so `ln /etc/shadow ~/.npmrc` would have root append to and chown the
    /// real inode. `fs.protected_hardlinks` normally prevents creating such a link
    /// across owners, but it is a sysctl an operator can disable and nothing here
    /// should silently depend on it.
    #[test]
    fn ensure_line_refuses_a_hardlink() {
        let d = TempDir::new().unwrap();
        let victim = d.path().join("victim");
        fs::write(&victim, b"secret\n").unwrap();
        let link = d.path().join(".npmrc");
        fs::hard_link(&victim, &link).unwrap();

        let err =
            ensure_line_in_owned_file("x", &link, &self_owner(), 0o644, chown_by_name_nofollow)
                .unwrap_err();
        assert!(err.to_string().contains("hardlink"), "err={err}");
        assert_eq!(
            fs::read(&victim).unwrap(),
            b"secret\n",
            "the linked inode was modified"
        );
    }

    /// A symlink whose target EXISTS — the shape that bypassed the old
    /// `if !path.exists()` guard, since `exists()` follows. The target must be
    /// untouched: as root this was an arbitrary-file append-and-chown.
    #[test]
    fn ensure_line_refuses_a_symlink_whose_target_exists() {
        let d = TempDir::new().unwrap();
        let victim = d.path().join("victim");
        fs::write(&victim, b"original\n").unwrap();
        let link = d.path().join(".npmrc");
        std::os::unix::fs::symlink(&victim, &link).unwrap();

        let err =
            ensure_line_in_owned_file("x", &link, &self_owner(), 0o644, chown_by_name_nofollow)
                .unwrap_err();
        assert!(err.to_string().contains("symlink"), "err={err}");
        assert_eq!(
            fs::read(&victim).unwrap(),
            b"original\n",
            "followed the symlink and wrote through it as root"
        );
    }

    /// An existing file keeps the mode the operator gave it. `~/.npmrc` holds npm
    /// auth tokens, and re-asserting 0644 on every converge run silently widened a
    /// deliberate 0600 back to world-readable.
    #[test]
    fn ensure_line_does_not_widen_an_existing_files_mode() {
        let d = TempDir::new().unwrap();
        let f = d.path().join(".npmrc");
        fs::write(&f, b"//registry/:_authToken=secret\n").unwrap();
        fs::set_permissions(&f, fs::Permissions::from_mode(0o600)).unwrap();

        ensure_line_in_owned_file(
            "prefix=/home/agent/.npm-global",
            &f,
            &self_owner(),
            0o644,
            chown_by_name_nofollow,
        )
        .unwrap();

        assert_eq!(mode_of(&f), 0o600, "widened a token file to world-readable");
        assert!(fs::read_to_string(&f).unwrap().contains("prefix="));
    }

    /// A file whose last line lacks a trailing newline must not have our record
    /// glued onto it — that produces one corrupt line instead of two good ones, and
    /// the whole-line match then never sees our line again, so the next run appends
    /// another one.
    #[test]
    fn ensure_line_separates_from_a_file_with_no_trailing_newline() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("npmrc");
        fs::write(&f, b"prefix=/old").unwrap();

        ensure_line_in_owned_file(
            "prefix=/new",
            &f,
            &self_owner(),
            0o644,
            chown_by_name_nofollow,
        )
        .unwrap();
        assert_eq!(
            fs::read_to_string(&f).unwrap(),
            "prefix=/old\nprefix=/new\n"
        );

        // And it is idempotent from that repaired state.
        ensure_line_in_owned_file(
            "prefix=/new",
            &f,
            &self_owner(),
            0o644,
            chown_by_name_nofollow,
        )
        .unwrap();
        assert_eq!(
            fs::read_to_string(&f).unwrap(),
            "prefix=/old\nprefix=/new\n"
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
        assert!(
            msg.contains("create directory"),
            "no operation named: {msg}"
        );
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

    // A file with a non-UTF-8 byte keeps every line outside the block. The old
    // `read_to_string(..).unwrap_or_default()` treated an undecodable file as
    // EMPTY, so the atomic write replaced the whole thing with just the agentlinux
    // block — one Latin-1 character in a `.bashrc` comment cost the user every
    // other line in the file.
    #[test]
    fn marker_block_preserves_a_non_utf8_file() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("bashrc");
        // 0xE9 is `é` in Latin-1 and invalid UTF-8.
        let original: &[u8] = b"# caf\xe9 aliases\nalias ll='ls -la'\nexport EDITOR=vi\n";
        fs::write(&f, original).unwrap();

        ensure_marker_block(&f, "agentlinux-path", "export PATH=/x").unwrap();

        let after = fs::read(&f).unwrap();
        assert!(
            after.windows(4).any(|w| w == b"caf\xe9"),
            "the undecodable line was lost"
        );
        assert!(
            after.windows(17).any(|w| w == b"alias ll='ls -la'"),
            "user content outside the block was lost"
        );
        assert!(
            after.windows(16).any(|w| w == b"export EDITOR=vi"),
            "a plain ASCII line after the undecodable one was lost"
        );
        assert!(after.starts_with(b"# >>> agentlinux-path begin >>>\n"));
    }

    // A present-but-unreadable file is refused rather than treated as empty —
    // otherwise the atomic write would replace it with only the block.
    #[test]
    fn marker_block_refuses_a_file_it_cannot_read() {
        let d = TempDir::new().unwrap();
        // A directory where a file is expected: the read fails with EISDIR.
        let f = d.path().join("as-a-dir");
        fs::create_dir(&f).unwrap();
        let err = ensure_marker_block(&f, "tag", "body").unwrap_err();
        assert!(
            err.to_string().contains("refusing to overwrite it blind"),
            "err={err}"
        );
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

#[cfg(test)]
mod sysio_seam_tests {
    //! The arms `cargo mutants` showed surviving: an error path with no
    //! assertion behind it is a function whose failure handling is decoration.
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn which_finds_a_program_on_path_and_misses_one_that_is_absent() {
        let sh = which("sh").expect("every POSIX host has sh on PATH");
        assert!(sh.ends_with("sh"), "{}", sh.display());
        assert!(sh.is_absolute());
        assert!(which("no-such-program-agentlinux-xyzzy").is_none());
    }

    #[test]
    fn chown_by_name_nofollow_rejects_an_unknown_user_and_a_malformed_owner() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("x");
        fs::write(&f, b"x").unwrap();

        let err = chown_by_name_nofollow(&f, "no-such-user-agentlinux-xyzzy:root").unwrap_err();
        assert!(err.to_string().contains("unknown user"), "err={err}");

        // The owner must be `user:group` — a bare username is a caller bug, not
        // a silent chown to the primary group.
        let err = chown_by_name_nofollow(&f, "root").unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
    }

    #[test]
    fn chown_symlink_by_name_rejects_an_unknown_user() {
        let d = TempDir::new().unwrap();
        let link = d.path().join("l");
        std::os::unix::fs::symlink("/nowhere", &link).unwrap();
        assert!(chown_symlink_by_name(&link, "no-such-user-agentlinux-xyzzy:root").is_err());
    }

    #[test]
    fn visudo_validate_maps_a_rejecting_checker_to_an_error() {
        // `false` exits non-zero for any argument — the "visudo rejected this
        // sudoers" arm, reachable on a host with no visudo installed.
        let d = TempDir::new().unwrap();
        let f = d.path().join("sudoers");
        fs::write(&f, b"agent ALL=(ALL) NOPASSWD: ALL\n").unwrap();

        let err = visudo_validate_with("false", &f).unwrap_err();
        assert!(err.to_string().contains("syntax check failed"), "err={err}");
        assert!(
            err.to_string().contains(&f.display().to_string()),
            "the error must name the file it rejected: {err}"
        );

        // …and an accepting checker is Ok.
        assert!(visudo_validate_with("true", &f).is_ok());
    }

    #[test]
    fn a_missing_checker_is_an_error_not_a_silent_pass() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("sudoers");
        fs::write(&f, b"x\n").unwrap();
        // ENOENT on the checker must NOT read as "the file is fine".
        assert!(visudo_validate_with("no-such-visudo-agentlinux-xyzzy", &f).is_err());
    }

    #[test]
    fn a_failed_write_leaves_no_residual_tmpfile() {
        // The TmpGuard's whole job. Renaming onto a path that is a DIRECTORY
        // fails (EISDIR), so the write aborts after the tmpfile exists.
        let d = TempDir::new().unwrap();
        let dest = d.path().join("dest");
        fs::create_dir(&dest).unwrap();

        assert!(write_file_atomic(0o644, &dest, b"body").is_err());

        let residue: Vec<String> = fs::read_dir(d.path())
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .filter(|n| n != "dest")
            .collect();
        assert!(residue.is_empty(), "leaked {residue:?}");
    }

    #[test]
    fn user_exists_gates_ensure_user_on_the_passwd_db() {
        assert!(user_exists("root").unwrap());
        assert!(!user_exists("no-such-user-agentlinux-xyzzy").unwrap());
    }
}
