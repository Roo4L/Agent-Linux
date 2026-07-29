//! provision/agent_user.rs — port of `plugin/provisioner/10-agent-user.sh`.
//!
//! Reproduces the agent-user step's observable system state byte-faithfully:
//!   1. `ensure_user` (useradd: /bin/bash shell, real home, own group)
//!   2. `ensure_dir /home/<user> 0755 <user>:<user>`
//!   3. `locale_ensure C.UTF-8` (debian /etc/default/locale, rhel /etc/locale.conf)
//!   4. the DOC-02 `CLAUDE.md` marker block (tag `agentlinux-doc-02`, `--top`),
//!      then re-chown/chmod 0644 `<user>:<user>`.
//!
//! Dispatches on the pre-resolved `RESOLUTIONS[user]` token (the DECIDE phase's
//! output — the step only does I/O, never re-derives the decision):
//!   - `Reuse` | `Remediate` → skip Steps 1-3 (identity/locale unchanged), still
//!     write the DOC-02 block (additive/unconditional).
//!   - `Create` → run Steps 1-3.
//!   - `ReuseWithWarning` → log `[REUSE-WARN]`, skip 1-3, still write DOC-02.
//!   - `Bail` → unreachable (a bail exits 65 before the step loop); defensive Err.
//!
//! The DOC-02 body is the EXACT heredoc from 10-agent-user.sh:88-134, stored as a
//! single `&str` const so it round-trips byte-exact. The three anti-pattern
//! strings (`usr/local/bin`, `sudo npm install -g`, `second Node.js install`) MUST
//! be PRESENT — `10-installer.bats`'s DOC-02 tests positively grep them.

use crate::pkg;
use crate::provision::{ProvisionCtx, Resolution};
use crate::sysio::{self, Placement};
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

/// The DOC-02 CLAUDE.md body — byte-for-byte with the heredoc between the
/// `DOC02` delimiters in `10-agent-user.sh:88-134` (the content, NOT the shell
/// marker lines — `ensure_marker_block` adds those). `ensure_marker_block` emits
/// `begin\n{body}\n{end}\n`, and the Bash heredoc body has NO leading blank line
/// and NO trailing newline before the closing `DOC02`, so this const starts at
/// `# /home/agent/CLAUDE.md …` and ends at `… bug class AgentLinux exists to
/// prevent.` with no trailing newline (the `\n` after the body is supplied by
/// `ensure_marker_block`'s `{body}\n`).
const DOC02_BODY: &str = "\
# /home/agent/CLAUDE.md — AgentLinux agent-user guidance

## This environment is correctly owned

This agent user was provisioned by AgentLinux. Your home directory,
npm global prefix (arrives Phase 3), and per-tool config paths are all owned
by you. You do NOT need sudo for routine agent operations.

If you hit a permission error, that is a BUG in the environment — do NOT
paper over it by climbing the privilege ladder. Exit non-zero, log the
error, and let the human or AgentLinux maintainer diagnose.

## DO NOT (anti-patterns — canonical bugs AgentLinux exists to eliminate)

- **No wrapper shims under `/usr/local/bin/`.** A shim at `/usr/local/bin/claude`
  (or any tool) that `exec`s an agent-owned binary breaks Claude Code's
  self-update: the update rewrites the agent-owned binary, not the shim, so
  the next invocation still points at the old code. This is the canonical
  v0.1 / v0.2 bug that motivated this project.

- **No `sudo npm install -g`.** If `npm install -g <pkg>` fails with EACCES,
  the environment is broken. Fix the environment; do not work around it.
  The agent's npm prefix is under `$HOME` (arrives Phase 3); global installs
  work without sudo by design.

- **No second Node.js install (nvm, fnm, volta, manual tarball).** The system
  Node.js from NodeSource (Phase 3+) is correctly owned. A second Node.js
  install creates a PATH race that breaks cron and systemd invocations.

- **No `sudo $0 \"$@\"` self-re-exec.** If you need a privilege you do not
  have, stop and report — do not recover by climbing the privilege ladder.

- **No writes to installer-owned paths:** `/usr/local/lib/node_modules`,
  `/opt`, `/etc/agentlinux.env`, `/etc/profile.d/*.sh`, `/etc/sudoers.d/*`.

## Where you (the agent tool) SHOULD write

- `$HOME/.npm-global/` — npm globals (arrives Phase 3)
- `$HOME/.local/bin` — per-user scripts
- `$HOME/.config/<tool>/` — per-tool config
- `$HOME/.cache/<tool>/` — per-tool cache

## Signal when you hit a permission error

Exit non-zero, log the error, let the human or AgentLinux maintainer
diagnose. DO NOT \"recover\" by climbing the privilege ladder — that is
precisely the bug class AgentLinux exists to prevent.";

/// `run` — the 10-agent-user.sh port. `ctx.resolutions.user` selects the path;
/// the CREATE steps run only for `Create`, the DOC-02 block runs unconditionally
/// (except `Bail`, which is a defensive error).
pub fn run(ctx: &ProvisionCtx) -> io::Result<()> {
    let reused = match ctx.resolutions.user {
        Resolution::Create => false,
        Resolution::Reuse | Resolution::Remediate => {
            // `remediate` acts identically to `reuse` on the user's own identity;
            // the sudoers fix is Wave 2's job (RESOLUTIONS[sudoers]).
            eprintln!(
                "10-agent-user: REUSE branch — skipping useradd + locale for existing user '{}'",
                ctx.install_user
            );
            true
        }
        Resolution::ReuseWithWarning => {
            eprintln!(
                "[REUSE-WARN] component=user — skipped (user declined remediation; manual fix \
                 needed). Existing user '{}' unchanged.",
                ctx.install_user
            );
            true
        }
        Resolution::Bail => {
            // Unreachable — a bail exits 65 before the step loop; enumerate
            // defensively (mirrors 10-agent-user.sh:50-54).
            return Err(io::Error::other(
                "10-agent-user: unreachable bail arm — flush_bails_or_continue should have gated this",
            ));
        }
    };

    // Steps 1+2 (CREATE path) — only when the user was not reused.
    if !reused {
        // Step 1: install user (BHV-01). `ensure_user` is a no-op if the user
        // already exists; `ensure_dir` then corrects home mode/ownership.
        sysio::ensure_user(&ctx.install_user)?;
        let owner = format!("{u}:{u}", u = ctx.install_user);
        sysio::ensure_dir(Path::new(&ctx.install_home), 0o755, &owner)?;

        // Step 2: locale (BHV-01 — LANG/LC_ALL=C.UTF-8). The per-family branch
        // (debian /etc/default/locale vs rhel /etc/locale.conf) lives in pkg.rs.
        pkg::locale_ensure(ctx.family, "C.UTF-8")
            .map_err(|e| io::Error::other(format!("C.UTF-8 locale not available: {e}")))?;
    }

    // Step 3: DOC-02 CLAUDE.md (unconditional/additive). ensure_marker_block with
    // the stable `agentlinux-doc-02` tag + Top placement — re-runs are
    // idempotent, user content outside the block survives.
    let claude_md = Path::new(&ctx.install_home).join("CLAUDE.md");
    sysio::ensure_marker_block(&claude_md, "agentlinux-doc-02", Placement::Top, DOC02_BODY)?;

    // ensure_marker_block leaves the file root-owned at 0644 — re-assert 0644 and
    // chown <user>:<user> so the user can read + edit it outside the block
    // (10-agent-user.sh:139-140).
    std::fs::set_permissions(&claude_md, std::fs::Permissions::from_mode(0o644))?;
    let owner = format!("{u}:{u}", u = ctx.install_user);
    chown_user_group(&claude_md, &owner)?;
    eprintln!(
        "10-agent-user: wrote DOC-02 CLAUDE.md to {}",
        claude_md.display()
    );
    Ok(())
}

/// `chown <user>:<group> <path>` by name — resolve the passwd/group entries (the
/// `user` nix feature) and apply via `std::os::unix::fs::chown` (the sanctioned
/// syscall; nix's `fs` feature is not enabled). Mirrors `ensure_dir`'s owner
/// resolution in `sysio.rs`.
fn chown_user_group(path: &Path, owner: &str) -> io::Result<()> {
    let (user, group) = owner.split_once(':').ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "chown: owner must be user:group",
        )
    })?;
    let uid = nix::unistd::User::from_name(user)
        .map_err(|e| io::Error::other(format!("chown: user {user}: {e}")))?
        .ok_or_else(|| io::Error::other(format!("chown: unknown user {user}")))?
        .uid
        .as_raw();
    let gid = nix::unistd::Group::from_name(group)
        .map_err(|e| io::Error::other(format!("chown: group {group}: {e}")))?
        .ok_or_else(|| io::Error::other(format!("chown: unknown group {group}")))?
        .gid
        .as_raw();
    std::os::unix::fs::chown(path, Some(uid), Some(gid))
        .map_err(|e| io::Error::other(format!("chown {} failed: {e}", path.display())))
}

#[cfg(test)]
mod agent_user_tests {
    use super::*;

    // The three anti-pattern strings 10-installer.bats positively greps MUST be
    // present in the DOC-02 body constant (byte-fidelity anchor,
    // 10-agent-user.sh:84).
    #[test]
    fn doc02_body_contains_the_three_anti_pattern_strings() {
        assert!(DOC02_BODY.contains("usr/local/bin"));
        assert!(DOC02_BODY.contains("sudo npm install -g"));
        assert!(DOC02_BODY.contains("second Node.js install"));
    }

    // The body has NO trailing newline (ensure_marker_block supplies the `\n`
    // after {body}); a stray trailing newline would insert a blank line before
    // the end marker, breaking byte-fidelity vs the Bash heredoc.
    #[test]
    fn doc02_body_has_no_trailing_newline() {
        assert!(!DOC02_BODY.ends_with('\n'));
        assert!(DOC02_BODY.starts_with("# /home/agent/CLAUDE.md"));
    }

    // The full marker-block round-trip: writing DOC02_BODY through the ported
    // ensure_marker_block yields the exact begin/body/end frame with the three
    // strings present and the marker delimiters 10-installer.bats expects. This
    // exercises the byte contract WITHOUT needing root (temp file).
    #[test]
    fn ensure_marker_block_frames_doc02_body_byte_exact() {
        let d = tempfile::TempDir::new().unwrap();
        let f = d.path().join("CLAUDE.md");
        sysio::ensure_marker_block(&f, "agentlinux-doc-02", Placement::Top, DOC02_BODY).unwrap();
        let content = std::fs::read_to_string(&f).unwrap();
        assert!(content.starts_with("# >>> agentlinux-doc-02 begin >>>\n"));
        assert!(content.ends_with("# <<< agentlinux-doc-02 end <<<\n"));
        assert!(content.contains("usr/local/bin"));
        assert!(content.contains("sudo npm install -g"));
        assert!(content.contains("second Node.js install"));
        // Exactly one begin marker (idempotent framing).
        assert_eq!(
            content.matches("# >>> agentlinux-doc-02 begin >>>").count(),
            1
        );
    }

    // A `Bail` resolution is a defensive error (the step loop never sees it in
    // practice; a bail exits 65 upstream).
    #[test]
    fn bail_resolution_is_defensive_error() {
        let ctx = ProvisionCtx {
            install_user: "agent".into(),
            install_home: "/home/agent".into(),
            family: crate::distro::Family::Debian,
            resolutions: crate::provision::Resolutions {
                user: Resolution::Bail,
                sudoers: Resolution::Create,
                node: Resolution::Create,
                npm_prefix: Resolution::Create,
                agents: std::collections::BTreeMap::new(),
            },
            yes: false,
            dry_run: false,
        };
        assert!(run(&ctx).is_err());
    }
}
