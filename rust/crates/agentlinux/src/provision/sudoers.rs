//! provision/sudoers.rs — step 20: the sudoers drop-in.
//!
//! Installs `/etc/sudoers.d/agentlinux` granting passwordless sudo to the
//! install user (scope: ALL commands, per ADR-012). Satisfies INST-06 (agent has
//! passwordless sudo), BHV-07 (the drop-in is mode 0440 root:root, visudo-clean,
//! byte-stable), and REMEDIATE-03.
//!
//! Security-critical: a malformed sudoers drop-in would lock out sudo host-wide
//! (DoS). The write path reproduces the Bash visudo TOCTOU belt exactly —
//! `visudo -cf` validates the tmpfile BEFORE the atomic 0440 install AND
//! re-verifies the installed file AFTER — so a syntactically-broken sudoers can
//! never land. A failed check aborts non-zero; it never installs.
//!
//! Both the CREATE (additive missing-file install) and the REMEDIATE
//! (state-overwriting drift fix) arms route through ONE `install_or_overwrite`
//! helper — the single source of truth mirroring the Bash single helper — so the
//! two arms cannot drift in semantics. The `action` label is purely diagnostic in
//! the `[REMEDIATE-03]` marker.
//!
//! Dispatches on the pre-resolved `RESOLUTIONS[sudoers]` token (the DECIDE
//! phase's output — the step only does I/O, never re-derives the decision):
//!  - `Reuse` → no-op (`[REUSE]` marker), the file is present + canonical.
//!  - `Create` → `install_or_overwrite("install")`.
//!  - `Remediate` → `install_or_overwrite("overwrite")` (the `--yes` gate already
//!    passed upstream; the label drives the `[REMEDIATE-03]` marker).
//!  - `ReuseWithWarning` → `[REUSE-WARN]` marker, leave the file as-is.
//!  - `Bail` → unreachable (a bail exits 65 before the step loop); defensive Err.

use crate::pkg;
use crate::provision::{ProvisionCtx, StepResolution};
use crate::sysio;
use std::io;
use std::path::Path;

/// The canonical sudoers drop-in path (byte-for-byte with
/// `remediate/sudoers.sh:36`).
const SUDOERS_FILE: &str = "/etc/sudoers.d/agentlinux";

/// The static ADR-012 header — byte-for-byte with the single-quoted heredoc in
/// `remediate/sudoers.sh:46-47`. The em-dash is the UTF-8 `—` (0xe2 0x80 0x94),
/// exactly as the Bash heredoc emits it. NO trailing newline here: the newline
/// after line 2 and before the NOPASSWD line is supplied when the content is
/// assembled (mirroring the Bash `content+=$(printf '\n%s …')`).
const SUDOERS_HEADER: &str = "\
# Installed by AgentLinux — grants passwordless sudo to the install user.
# Scope: ALL commands. See docs/decisions/012-agent-user-full-sudo.md.";

/// Build the byte-exact drop-in content for `user`.
///
/// Reproduces `remediate/sudoers.sh:45-49` + the `printf '%s\n'` write: the two
/// static header lines, then `<user> ALL=(ALL) NOPASSWD: ALL`, with a single
/// trailing newline (from the write's `%s\n`). `22-agent-sudo.bats` greps the
/// NOPASSWD line with `grep -Fx`, so it must be the exact whole line.
fn sudoers_content(user: &str) -> String {
    // header + '\n' + "<user> ALL=(ALL) NOPASSWD: ALL" + trailing '\n'.
    format!("{SUDOERS_HEADER}\n{user} ALL=(ALL) NOPASSWD: ALL\n")
}

/// `run` — the 20-sudoers.sh port. `ctx.resolutions.sudoers` selects the path.
///
/// Ensures `visudo` exists first (`pkg_install sudo` if absent — minimal
/// cloud/Docker images ship without it), re-asserts `/etc/sudoers.d` at
/// `0755 root:root`, then dispatches on the resolution token.
pub fn run(ctx: &ProvisionCtx) -> io::Result<()> {
    eprintln!("20-sudoers: starting");

    // Minimal images ship without the `sudo` package (which provides both `sudo`
    // and `visudo`); we need `visudo` to validate the drop-in. Install BEFORE the
    // dispatch so even REUSE/REMEDIATE arms have visudo for validation. Routes
    // through the family-correct pkg verb (apt on debian, dnf on rhel).
    if sysio::which("visudo").is_none() {
        eprintln!("20-sudoers: visudo not found; installing 'sudo' package");
        pkg::pkg_install(ctx.family, &["sudo"])?;
    }

    // ensure_dir re-asserts mode+ownership when the dir already exists (drift
    // correction) — matches `ensure_dir /etc/sudoers.d 0755 root:root`.
    sysio::ensure_dir(Path::new("/etc/sudoers.d"), 0o755, "root:root")?;

    match ctx.resolutions.sudoers {
        StepResolution::Reuse => {
            eprintln!(
                "20-sudoers: [REUSE] sudoers: {SUDOERS_FILE} already canonical (ADR-012 line present)"
            );
            eprintln!("20-sudoers: done");
            Ok(())
        }
        StepResolution::Create => {
            install_or_overwrite(ctx, "install")?;
            eprintln!(
                "20-sudoers: install user '{}' now has passwordless sudo (scope: ALL commands) — INST-06",
                ctx.install_user
            );
            eprintln!("20-sudoers: done");
            Ok(())
        }
        StepResolution::Remediate => {
            // The consent gate already passed upstream (a bail would have exited
            // 65 before the step loop if --yes were missing).
            install_or_overwrite(ctx, "overwrite")?;
            eprintln!(
                "20-sudoers: install user '{}' now has passwordless sudo (scope: ALL commands — drift remediated) — INST-06",
                ctx.install_user
            );
            eprintln!("20-sudoers: done");
            Ok(())
        }
        StepResolution::ReuseWithWarning => {
            // Operator declined the drift overwrite; leave the file as-is. The
            // operator now owns ensuring the grant works.
            eprintln!(
                "20-sudoers: [REUSE-WARN] component=sudoers — skipped (user declined remediation; \
                 manual fix needed). {SUDOERS_FILE} unchanged."
            );
            eprintln!("20-sudoers: done");
            Ok(())
        }
    }
}

/// The ONE source of truth for both the CREATE and the REMEDIATE arms (mirroring
/// the Bash single `remediate::sudoers::install_or_overwrite`). `action`
/// (`"install"` / `"overwrite"`) is purely diagnostic in the `[REMEDIATE-03]`
/// marker — the behavior is identical.
///
/// Composes the canonical ADR-012 content, writes it to a tmpfile, gates it
/// through `visudo -cf` (PRE-install), installs it atomically at 0440 root:root,
/// then RE-VERIFIES with `visudo -cf` (POST-install TOCTOU belt). A failure at
/// either visudo gate is a hard error — a malformed sudoers can never land.
fn install_or_overwrite(ctx: &ProvisionCtx, action: &str) -> io::Result<()> {
    let content = sudoers_content(&ctx.install_user);
    let dest = Path::new(SUDOERS_FILE);

    // Write the candidate to a tmpfile in the DEST's parent dir (/etc/sudoers.d)
    // so the later atomic install is same-filesystem. Validate it BEFORE it is
    // ever renamed into place: visudo -cf catches syntax errors while the real
    // drop-in is still untouched.
    let dir = dest.parent().unwrap_or_else(|| Path::new("/etc/sudoers.d"));
    let (mut tmp_file, tmp) = sysio::mktemp_in(dir, "agentlinux-sudoers")?;
    {
        use std::io::Write;
        tmp_file.write_all(content.as_bytes())?;
        tmp_file.flush()?;
    }
    drop(tmp_file);
    // The guard unlinks the validation tmpfile on EVERY exit path from here; it
    // stays alive to end-of-scope.
    let _guard = sysio::TmpGuard::new(tmp.clone());

    // Pre-install gate (TOCTOU belt, part 1): refuse to install a syntactically
    // invalid sudoers.
    if let Err(e) = sysio::visudo_validate(&tmp) {
        eprintln!(
            "20-sudoers: [REMEDIATE-03:visudo-fail] tmpfile syntax check failed; refusing to install {SUDOERS_FILE}"
        );
        return Err(e);
    }

    // Atomic install at 0440 root:root. write_file_atomic sets the mode on the
    // tmpfile before the rename (never a window at the wrong mode); it creates its
    // own same-dir tmpfile and renames it onto dest. The validation tmpfile above
    // is cleaned by `_guard` on function exit.
    sysio::write_file_atomic(0o440, dest, content.as_bytes())?;
    // install(1) -o root -g root: re-assert owner explicitly (write_file_atomic
    // sets mode but inherits the creating euid — root here, but be explicit so a
    // non-root-but-CAP_CHOWN caller still lands root:root).
    sysio::chown_by_name(dest, "root:root")?;

    // Post-install verify (TOCTOU belt, part 2): catches any corruption between
    // the rename and here — a post-install failure is a hard error.
    if let Err(e) = sysio::visudo_validate(dest) {
        eprintln!(
            "20-sudoers: [REMEDIATE-03:visudo-fail] post-install verify failed for {SUDOERS_FILE}"
        );
        return Err(e);
    }

    eprintln!(
        "20-sudoers: [REMEDIATE-03] component=sudoers action={action} path={SUDOERS_FILE} (mode 0440 root:root — ADR-012)"
    );
    Ok(())
}

#[cfg(test)]
mod sudoers_tests {
    use super::*;

    // The drop-in content is byte-exact: the two ADR-012 header lines, the
    // NOPASSWD grant line for the resolved user, and a single trailing newline.
    // `22-agent-sudo.bats` greps `agent ALL=(ALL) NOPASSWD: ALL` with grep -Fx,
    // so it must be the exact whole line.
    #[test]
    fn sudoers_content_is_byte_exact_for_agent() {
        let c = sudoers_content("agent");
        assert_eq!(
            c,
            "# Installed by AgentLinux — grants passwordless sudo to the install user.\n\
             # Scope: ALL commands. See docs/decisions/012-agent-user-full-sudo.md.\n\
             agent ALL=(ALL) NOPASSWD: ALL\n"
        );
    }

    // The NOPASSWD line splices the RESOLVED user (AL-50) — a non-default install
    // user lands in the username column verbatim.
    #[test]
    fn sudoers_content_splices_the_resolved_user() {
        let c = sudoers_content("claude");
        assert!(c.contains("\nclaude ALL=(ALL) NOPASSWD: ALL\n"));
        // Exactly one grant line.
        assert_eq!(c.matches("ALL=(ALL) NOPASSWD: ALL").count(), 1);
    }

    // The header is byte-for-byte the ADR-012 static header (the em-dash is the
    // UTF-8 `—`), with NO trailing newline (the assembler supplies newlines).
    #[test]
    fn header_is_the_adr012_static_text_no_trailing_newline() {
        assert!(SUDOERS_HEADER.starts_with(
            "# Installed by AgentLinux — grants passwordless sudo to the install user."
        ));
        assert!(SUDOERS_HEADER.ends_with("012-agent-user-full-sudo.md."));
        assert!(!SUDOERS_HEADER.ends_with('\n'));
        // The em-dash is the UTF-8 EM DASH, not an ASCII hyphen.
        assert!(SUDOERS_HEADER.contains('\u{2014}'));
    }
}
