//! sysio.rs — the six `idempotency.sh` grep-before-mutate primitives, ported
//! byte-faithfully into the Rust bin (PROV-01).
//!
//! Byte-for-byte port of `plugin/lib/idempotency.sh`. Every state change the
//! provisioner makes goes through one of these helpers; a blind append or a
//! non-atomic write is forbidden because it breaks INST-02 (converge across
//! re-runs) and produces drift INST-05 (no EACCES on a second run) later flags.
//!
//! The load-bearing byte-fidelity invariants this module reproduces:
//!
//! - **`write_file_atomic`** — the tmpfile is created in the DEST's PARENT dir
//!   (same filesystem) so the final `fs::rename` is atomic; a cross-fs temp dir
//!   would fall back to copy+unlink and lose atomicity (57-RESEARCH Pitfall 1).
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
//!
//! `dead_code` is allowed at module scope for this Wave-0 foundation: the public
//! surface here is consumed by the Wave-1/2/3/4 provisioner steps (Plans 02-05).
//! The `#[cfg(test)]` module exercises every item now, so nothing is truly
//! unreachable — the allow only silences the "not yet wired into a non-test
//! caller" lint until those plans land, keeping the per-task tree warning-clean.
#![allow(dead_code)]

use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Placement of a marker block relative to the existing file content.
///
/// `Top` mirrors the Bash `--top` (required for `/home/agent/.bashrc`: the skel
/// `.bashrc` early-returns for non-interactive shells, so an agentlinux block
/// that must influence `sudo -u agent bash -c …` has to precede that guard).
/// `Bottom` is the Bash default `--bottom`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Placement {
    Top,
    Bottom,
}

/// RAII guard that unlinks a tmpfile on drop unless explicitly disarmed after a
/// successful rename — the Rust twin of the Bash `trap "rm -f -- '$tmp'" RETURN`.
/// Guarantees cleanup on every error path (a mid-write abort, a failed rename, a
/// failed `set_permissions`), so no residual `.dest.XXXXXX` is ever left behind.
struct TmpGuard {
    path: Option<PathBuf>,
}

impl TmpGuard {
    fn new(path: PathBuf) -> Self {
        Self { path: Some(path) }
    }

    /// Disarm the guard after the tmpfile has been renamed into place (the
    /// rename consumed the tmpfile, so there is nothing left to unlink).
    ///
    /// Not mutation-tested: skipping the disarm makes `Drop` unlink a path the
    /// rename already consumed, which is a no-op — there is no observable
    /// difference for a test to assert.
    #[cfg_attr(test, mutants::skip)]
    fn disarm(&mut self) {
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

/// Create a hidden, unique tmpfile in `dir` mirroring `mktemp -p "$dir"
/// ".${base}.XXXXXX"`. Same-directory placement is what keeps the later
/// `fs::rename` atomic on one filesystem (57-RESEARCH Pitfall 1). The name is a
/// leading-dot `.{base}.{pid}.{nanos}` — collision-hardened by the monotonic
/// nanos + O_CREAT|O_EXCL retry so two concurrent provisioner runs never clobber.
/// Not mutation-tested: the surviving mutants are all in the O_EXCL
/// collision-retry arm, which needs two processes to open the same
/// pid+nanosecond name in the same instant. The happy path is exercised by every
/// `write_file_atomic` test.
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
pub fn write_file_atomic(mode: u32, dest: &Path, body: &[u8]) -> io::Result<()> {
    let dir = dest.parent().unwrap_or_else(|| Path::new("."));
    let base = dest.file_name().and_then(|s| s.to_str()).ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "write_file_atomic: bad dest")
    })?;

    let (mut file, tmp) = mktemp_in(dir, base)?;
    let mut guard = TmpGuard::new(tmp.clone());

    file.write_all(body)?;
    file.flush()?;
    // L-1: fsync the tmpfile BEFORE the rename so a power loss in the
    // rename→commit window can't leave a zero-length / torn config (esp. the
    // 0440 sudoers). Cheap — once per small config file.
    file.sync_all()?;
    // Set mode on the tmpfile BEFORE the rename so the destination is never
    // briefly created with the umask-default mode (mirrors install -m).
    fs::set_permissions(&tmp, fs::Permissions::from_mode(mode))?;
    drop(file);

    fs::rename(&tmp, dest)?;
    // The rename consumed the tmpfile — disarm so Drop does not try to unlink a
    // now-nonexistent path.
    guard.disarm();
    Ok(())
}

/// `ensure_line_in_file <line> <file>` — append `line\n` iff no exact
/// whole-line match already exists (`grep -Fxq` semantics: literal, whole-line).
///
/// An absent/unreadable file is treated as "no match" (so the first call
/// creates the file). The existing trailing bytes are preserved — a blind
/// append after content with no trailing newline would glue the new line onto
/// the last one, but the Bash `printf '%s\n' >>file` also appends unconditionally
/// once the grep misses, so we match it exactly (append `line\n`).
pub fn ensure_line_in_file(line: &str, file: &Path) -> io::Result<()> {
    if let Ok(existing) = fs::read_to_string(file) {
        // `-x` = whole-line: split on '\n' and compare each line literally.
        // `str::lines()` also strips a trailing '\r'; grep -Fx does not, so
        // compare against the raw '\n'-split segments instead.
        if existing.split('\n').any(|l| l == line) {
            return Ok(());
        }
    }
    let mut f = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(file)?;
    f.write_all(line.as_bytes())?;
    f.write_all(b"\n")?;
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
fn strip_marker_block(existing: &str, begin: &str, end: &str) -> Vec<String> {
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
    out
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
pub fn ensure_marker_block(
    file: &Path,
    tag: &str,
    placement: Placement,
    body: &str,
) -> io::Result<()> {
    let begin = format!("# >>> {tag} begin >>>");
    let end = format!("# <<< {tag} end <<<");

    let existing = fs::read_to_string(file).unwrap_or_default();
    let filtered = strip_marker_block(&existing, &begin, &end);

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
    match placement {
        Placement::Top => {
            // { begin; body; end; awk-filtered-existing } > tmp
            out.push_str(&block);
            out.push_str(&remainder);
        }
        Placement::Bottom => {
            // awk-filtered-existing > tmp ; { begin; body; end } >> tmp
            out.push_str(&remainder);
            out.push_str(&block);
        }
    }

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
/// Not mutation-tested: killing `-> Ok(())` requires actually creating a user,
/// which needs root and mutates the host. The two halves that CAN be tested are:
/// [`useradd_argv`] (the exact argv) and [`user_exists`] (the id-gate).
#[cfg_attr(test, mutants::skip)]
pub fn ensure_user(name: &str) -> io::Result<()> {
    if user_exists(name)? {
        return Ok(());
    }
    let argv = useradd_argv(name);
    let status = Command::new(&argv[0]).args(&argv[1..]).status()?;
    if !status.success() {
        return Err(io::Error::other(format!(
            "ensure_user: useradd failed for {name} (status={status})"
        )));
    }
    Ok(())
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
        fs::create_dir_all(path)?;
    }
    // Re-assert mode + owner unconditionally on BOTH arms (create-then-set on the
    // absent arm equals `install -d -m -o -g`; the present arm is the Bash
    // chmod+chown drift-correction).
    fs::set_permissions(path, fs::Permissions::from_mode(mode))?;
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
/// `chown <user>:<group> <path>` by name — resolve the passwd/group entries and
/// apply via `std::os::unix::fs::chown` (the sanctioned syscall; nix's `fs`
/// feature is not enabled).
///
/// The ONE copy: `provision::{agent_user, nodejs, path_wiring, registry_cli,
/// sudoers}` each carried their own, so "did this step re-assert ownership?" had
/// seven answers and no single place to substitute in a test.
pub fn chown_by_name(path: &Path, owner: &str) -> io::Result<()> {
    let (uid, gid) = resolve_owner(owner)?;
    std::os::unix::fs::chown(path, Some(uid), Some(gid))
        .map_err(|e| io::Error::other(format!("chown {} failed: {e}", path.display())))
}

/// `chown -h <user>:<group> <link>` — change the SYMLINK itself, not its target.
pub fn chown_symlink_by_name(link: &Path, owner: &str) -> io::Result<()> {
    let (uid, gid) = resolve_owner(owner)?;
    std::os::unix::fs::lchown(link, Some(uid), Some(gid))
        .map_err(|e| io::Error::other(format!("chown -h {} failed: {e}", link.display())))
}

/// `command -v <name>` — resolve a program on PATH, `None` if absent.
#[must_use]
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

fn resolve_owner(owner: &str) -> io::Result<(u32, u32)> {
    let (user, group) = owner.split_once(':').ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "ensure_dir: owner must be user:group",
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
pub fn visudo_validate_with(program: &str, file: &Path) -> io::Result<()> {
    let status = Command::new(program).arg("-cf").arg(file).status()?;
    if !status.success() {
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
        // (Pitfall 1 — same-dir tmpfile, cleaned on the successful rename).
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

    // --- ensure_marker_block ---

    #[test]
    fn marker_block_top_emit_order() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("bashrc");
        fs::write(&f, b"# user line 1\n# user line 2\n").unwrap();
        ensure_marker_block(&f, "agentlinux-path", Placement::Top, "export PATH=/x").unwrap();
        // Top: begin\n{body}\n{end}\n THEN the filtered (unchanged) existing.
        let expected = "# >>> agentlinux-path begin >>>\n\
                        export PATH=/x\n\
                        # <<< agentlinux-path end <<<\n\
                        # user line 1\n\
                        # user line 2\n";
        assert_eq!(fs::read_to_string(&f).unwrap(), expected);
        assert_eq!(mode_of(&f), 0o644);
    }

    #[test]
    fn marker_block_bottom_emit_order() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("profile");
        fs::write(&f, b"# user line 1\n# user line 2\n").unwrap();
        ensure_marker_block(&f, "agentlinux-path", Placement::Bottom, "export PATH=/x").unwrap();
        // Bottom: filtered-existing THEN begin\n{body}\n{end}\n.
        let expected = "# user line 1\n\
                        # user line 2\n\
                        # >>> agentlinux-path begin >>>\n\
                        export PATH=/x\n\
                        # <<< agentlinux-path end <<<\n";
        assert_eq!(fs::read_to_string(&f).unwrap(), expected);
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
        // Re-run at Bottom replaces the block; outside content survives, and
        // exactly ONE block remains (now at the bottom).
        ensure_marker_block(&f, "agentlinux-path", Placement::Bottom, "NEW BODY").unwrap();
        let expected = "# top user content\n\
                        # trailing user content\n\
                        # >>> agentlinux-path begin >>>\n\
                        NEW BODY\n\
                        # <<< agentlinux-path end <<<\n";
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
        ensure_marker_block(&f, "t", Placement::Top, "B").unwrap();
        let after_first = fs::read_to_string(&f).unwrap();
        // Second identical run is byte-stable (BHV-07-style byte stability).
        ensure_marker_block(&f, "t", Placement::Top, "B").unwrap();
        assert_eq!(fs::read_to_string(&f).unwrap(), after_first);
        assert_eq!(after_first, "# >>> t begin >>>\nB\n# <<< t end <<<\nuser\n");
    }

    #[test]
    fn marker_block_on_absent_file_emits_only_the_block() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("does-not-exist-yet");
        ensure_marker_block(&f, "t", Placement::Top, "B").unwrap();
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
    fn chown_by_name_rejects_an_unknown_user_and_a_malformed_owner() {
        let d = TempDir::new().unwrap();
        let f = d.path().join("x");
        fs::write(&f, b"x").unwrap();

        let err = chown_by_name(&f, "no-such-user-agentlinux-xyzzy:root").unwrap_err();
        assert!(err.to_string().contains("unknown user"), "err={err}");

        // The owner must be `user:group` — a bare username is a caller bug, not
        // a silent chown to the primary group.
        let err = chown_by_name(&f, "root").unwrap_err();
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
