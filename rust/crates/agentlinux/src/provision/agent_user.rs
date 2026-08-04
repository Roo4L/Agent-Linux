//! provision/agent_user.rs — step 10: the install user and its home.
//!
//! Reproduces the agent-user step's observable system state byte-faithfully:
//!  1. `ensure_user` (useradd: /bin/bash shell, real home, own group)
//!  2. `ensure_dir /home/<user> 0755 <user>:<user>`
//!  3. `locale_ensure C.UTF-8` (debian /etc/default/locale, rhel /etc/locale.conf)
//!  4. the DOC-02 `CLAUDE.md` marker block (tag `agentlinux-doc-02`, `--top`),
//!     then re-chown/chmod 0644 `<user>:<user>`.
//!
//! Dispatches on the pre-resolved `RESOLUTIONS[user]` token (the DECIDE phase's
//! output — the step only does I/O, never re-derives the decision). The gate
//! covers Step 1 ONLY:
//!  - `Reuse` | `Remediate` → skip Step 1 (identity + home ownership unchanged).
//!  - `Create` → run Step 1.
//!  - `ReuseWithWarning` → log `[REUSE-WARN]`, skip Step 1.
//!  - `Bail` → unreachable (a bail exits 65 before the step loop); defensive Err.
//!
//! Steps 2 (locale) and 3 (DOC-02) run on EVERY branch. Both are idempotent,
//! system- rather than identity-scoped, and self-verifying, so a re-run repairs a
//! host left half-provisioned by an earlier failure instead of skipping past it.
//!
//! The DOC-02 body is the EXACT heredoc from 10-agent-user.sh:88-134, stored as a
//! single `&str` const so it round-trips byte-exact. The three anti-pattern
//! strings (`usr/local/bin`, `sudo npm install -g`, `second Node.js install`) MUST
//! be PRESENT — `10-installer.bats`'s DOC-02 tests positively grep them.

use crate::pkg;
use crate::provision::{ProvisionCtx, StepResolution};
use crate::sysio;
use std::io;
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
///
/// Not mutation-tested: an ADR-019 §5 seam gap. Reaches `useradd` with no
/// injection point, so its mutants are unreachable until `Effects` covers the
/// user-creation path. Skipped with a back-reference rather than left to redden
/// the enforcing gate for whoever's diff lands here (ADR-020 §4, third case).
#[cfg_attr(test, mutants::skip)]
pub fn run(ctx: &ProvisionCtx) -> io::Result<()> {
    let reused = match ctx.resolutions.user {
        StepResolution::Create => false,
        StepResolution::Reuse | StepResolution::Remediate => {
            // `remediate` acts identically to `reuse` on the user's own identity;
            // the sudoers fix is step 20's job (RESOLUTIONS[sudoers]).
            crate::plog!(
                "10-agent-user: REUSE branch — skipping useradd for existing user '{}' \
                 (locale + CLAUDE.md still enforced)",
                ctx.install_user
            );
            true
        }
        StepResolution::ReuseWithWarning => {
            crate::plog!(
                "[REUSE-WARN] component=user — skipped (user declined remediation; manual fix \
                 needed). Existing user '{}' unchanged.",
                ctx.install_user
            );
            true
        }
    };

    // Step 1 (CREATE path only) — identity. `ensure_user` is a no-op if the user
    // already exists; `ensure_dir` then corrects home mode/ownership. Both stay
    // gated: the REUSE contract is that an existing user's identity and home
    // ownership are left exactly as the operator had them.
    if !reused {
        sysio::ensure_user(&ctx.install_user)?;
        let owner = format!("{u}:{u}", u = ctx.install_user);
        sysio::ensure_dir(Path::new(&ctx.install_home), 0o755, &owner)?;
    }

    // Step 2: locale (BHV-01 — LANG/LC_ALL=C.UTF-8), UNCONDITIONAL.
    //
    // This is deliberately outside the REUSE gate. The locale is system-wide
    // state, not part of the user's identity, and `locale_ensure` both enforces
    // and VERIFIES it (`locale -a`), so re-running on a conforming host is a
    // cheap no-op.
    //
    // Gating it was a silent-failure hole. `user_state` classifies on the shell
    // alone, so once step 1 has created the user, the host reads as `Conforming`
    // forever after — even if the run that created it died at this very line.
    // Run 1: user created, locale fails, exit 70. Run 2: `Conforming` → REUSE →
    // locale skipped → every later step passes → `agentlinux-install complete`,
    // exit 0, with LANG/LC_ALL never set. The failure was permanent (no retry
    // could ever reach the skipped step) and silent (the installer reported
    // success). Running the step unconditionally is what makes a retry repair a
    // half-provisioned host.
    //
    // The per-family branch (debian /etc/default/locale vs rhel /etc/locale.conf)
    // lives in pkg.rs.
    pkg::locale_ensure(ctx.family, "C.UTF-8")
        .map_err(|e| io::Error::other(format!("C.UTF-8 locale not available: {e}")))?;

    // Step 3: DOC-02 CLAUDE.md (unconditional/additive). ensure_marker_block with
    // the stable `agentlinux-doc-02` tag + Top placement — re-runs are
    // idempotent, user content outside the block survives.
    let claude_md = Path::new(&ctx.install_home).join("CLAUDE.md");
    let owner = format!("{u}:{u}", u = ctx.install_user);
    // Same hardening `.bashrc` gets in step 40 — these two files are written by
    // adjacent steps into the same agent-owned directory and must not diverge.
    // Without the create-if-absent guard, a pre-planted `~/CLAUDE.md -> /etc/shadow`
    // had root read the target, preserve every line of it through the marker strip,
    // and publish it back as a 0644 file chowned to the agent. No race required.
    sysio::create_if_absent_0644(&claude_md, &owner, ctx.fx.chown)?;
    sysio::ensure_marker_block(&claude_md, "agentlinux-doc-02", DOC02_BODY)?;

    // `write_file_atomic` already set 0644 on the tmpfile before the rename, so the
    // mode is correct; only ownership needs re-asserting (the fresh inode is
    // root-owned). Through an O_NOFOLLOW handle — a path-based chown here would
    // hand over the target of a symlink swapped in after the rename.
    sysio::chown_by_name_nofollow(&claude_md, &owner)?;
    crate::plog!(
        "10-agent-user: wrote DOC-02 CLAUDE.md to {}",
        claude_md.display()
    );
    Ok(())
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
        sysio::ensure_marker_block(&f, "agentlinux-doc-02", DOC02_BODY).unwrap();
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
}
