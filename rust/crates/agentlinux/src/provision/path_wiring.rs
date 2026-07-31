//! provision/path_wiring.rs — the four PATH artefacts.
//!
//! Wires `<home>/.npm-global/bin` onto PATH across all SIX invocation modes
//! (BHV-02 SSH, BHV-03 cron, BHV-04 systemd, BHV-05 sudo -u [-i], BHV-06 login;
//! RT-02 PATH, RT-04 NPM_CONFIG_PREFIX) via FOUR artefacts, with observable state
//! byte-identical to the Bash provisioner on both distros:
//!  1. `/etc/profile.d/agentlinux.sh` (0644 root:root) — login + `sudo -u -i`
//!  2. `<home>/.bashrc` TOP marker block (0644 user:user) — SSH + `sudo -u bash -c`
//!  3. `/etc/agentlinux.env` (0644 root:root) — systemd EnvironmentFile
//!  4. `/etc/cron.d/agentlinux` (0644 root:root) — cron PATH header
//!
//! THE #1 RISK (byte-fidelity, 57-05): the RT-*/BHV-* bats grep these files'
//! EXACT contents across all six modes, and a cross-grep between artefacts 3 and
//! 4 enforces a byte-identical PATH line. The Bash heredocs are UNQUOTED for
//! artefacts 1/3/4 (`${_AL_HOME}`/`${_AL_USER}` interpolate; runtime shell vars
//! `\$PATH`/`\${LANG:-…}`/the re-source guard stay LITERAL via `\$`) and QUOTED
//! for artefact 2 (`<<'BASHRC'` — no interpolation). This port reproduces that
//! interpolate-user / literal-runtime-var split with `format!` where Bash
//! interpolates and plain literal bytes everywhere else.
//!
//! PATH ORDERING — an escalation-of-privilege concern: user-owned prefixes FIRST
//! (`<home>/.npm-global/bin` ends first, then `.local/bin`, then system) in EVERY
//! artefact — a stray `/usr/local/bin` shim must lose to the user-owned binary
//! (the canonical self-update bug). Artefacts 3+4 build their PATH line from the
//! ONE `recipe_env::canonical_path` source so systemd's EnvironmentFile
//! can never drift from cron's header.
//!
//! Runs UNCONDITIONALLY for both CREATE and REUSE — the artefacts are additive
//! (`ensure_marker_block` preserves user content outside its block; the three
//! root-owned files are installer-owned by contract). No RESOLUTIONS dispatch
//! On REUSE it emits the `[REMEDIATE-02]` marker.

use crate::provision::{ProvisionCtx, StepResolution};
use crate::recipe_env;
use crate::sysio;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

/// `run` — the 40-path-wiring.sh port. Resolves `_user`/`_home` from `ctx` and
/// writes the four artefacts unconditionally (additive), emitting the
/// `[REMEDIATE-02]` marker when the user was reused.
pub fn run(ctx: &ProvisionCtx) -> io::Result<()> {
    eprintln!("40-path-wiring: starting");

    // Resolved install user + home — derived from ctx,
    // never re-resolved. AL-59: every per-user path below interpolates these so an
    // accepted alternate install user is fully wired.
    let user = &ctx.install_user;
    let home = &ctx.install_home;
    let owner = format!("{user}:{user}");

    // REUSE → [REMEDIATE-02] marker. The wiring code is
    // identical for CREATE and REUSE; the marker only distinguishes re-attaching
    // PATH wiring from creating it in the transcript.
    if is_reused(ctx.resolutions.user) {
        eprintln!(
            "40-path-wiring: [REMEDIATE-02] component=user action=path-wiring-additive \
             user={user} (ensure_marker_block + write_file_atomic; user content outside \
             markers preserved)"
        );
    }

    // Ensure <home>/.local{,/bin} exist so the PATH prefix isn't a dangling
    // reference. ensure_dir re-asserts mode+ownership.
    sysio::ensure_dir(Path::new(&format!("{home}/.local")), 0o755, &owner)?;
    sysio::ensure_dir(Path::new(&format!("{home}/.local/bin")), 0o755, &owner)?;

    // The ONE canonical PATH string — reused for artefacts 3 AND 4 so the two
    // lines are byte-identical to each other AND to the recipe env
    // (; the cross-module test asserts the three-way equality).
    let canonical_path = recipe_env::canonical_path(home);

    // Artefact 1: /etc/profile.d/agentlinux.sh (0644 root:root).
    let profile = profile_d_content(user, home);
    sysio::write_file_atomic(
        0o644,
        Path::new("/etc/profile.d/agentlinux.sh"),
        profile.as_bytes(),
    )?;
    eprintln!("40-path-wiring: wrote /etc/profile.d/agentlinux.sh");

    // Artefact 2: <home>/.bashrc marker block at TOP (0644 user:user).
    let bashrc = format!("{home}/.bashrc");
    let bashrc_path = Path::new(&bashrc);
    // Create an empty user-owned file first if absent (minimal container with no
    // skel copy) so ensure_marker_block has a target.
    sysio::create_if_absent_0644(bashrc_path, &owner)?;
    sysio::ensure_marker_block(bashrc_path, "agentlinux-path", BASHRC_BODY)?;
    // ensure_marker_block writes via write_file_atomic(0o644, …) leaving the file
    // root-owned; re-assert <user>:<user> + 0644 so the user can edit outside the
    // block.
    std::fs::set_permissions(bashrc_path, std::fs::Permissions::from_mode(0o644))?;
    sysio::chown_by_name(bashrc_path, &owner)?;
    eprintln!("40-path-wiring: wrote agentlinux-path marker block to {bashrc} (--top)");

    // Artefact 3: /etc/agentlinux.env (0644 root:root) — literal KEY=VALUE.
    let env_file = agentlinux_env_content(user, home, &canonical_path);
    sysio::write_file_atomic(0o644, Path::new("/etc/agentlinux.env"), env_file.as_bytes())?;
    eprintln!("40-path-wiring: wrote /etc/agentlinux.env (systemd EnvironmentFile + cron header template)");

    // Artefact 4: /etc/cron.d/agentlinux (0644 root:root) — same PATH literal.
    let cron = cron_d_content(user, &canonical_path);
    sysio::write_file_atomic(0o644, Path::new("/etc/cron.d/agentlinux"), cron.as_bytes())?;
    eprintln!(
        "40-path-wiring: wrote /etc/cron.d/agentlinux (PATH + locale header; no default jobs)"
    );

    eprintln!("40-path-wiring: done (four artefacts written)");
    Ok(())
}

/// Whether the user was REUSED — drives the [REMEDIATE-02] marker. Mirrors the
/// Bash `REUSED_USER == true`: the additive PATH wiring is a Remediate for any
/// non-fresh identity, so both `Reuse` and `ReuseWithWarning` count as reused
/// (a `Remediate` token on the user component likewise means the identity was
/// pre-existing).
fn is_reused(user: StepResolution) -> bool {
    matches!(
        user,
        StepResolution::Reuse | StepResolution::ReuseWithWarning | StepResolution::Remediate
    )
}

/// The literal body of the `<home>/.bashrc` marker block (artefact 2) — the
/// Bash `<<'BASHRC'` QUOTED heredoc, so ZERO interpolation. `ensure_marker_block`
/// wraps this with the `# >>> agentlinux-path begin >>>` / `# <<< … end <<<`
/// markers and a trailing newline; the body itself has NO trailing newline (the
/// marker layer supplies the joiners), matching `printf '%s\n' "$body"`.
// Flush-left real-newline literal (NOT `\`-continuation — that ESCAPE strips the
// two-space indent on the `. /etc/profile.d/…` line). The leading `\` after the
// opening quote consumes only the first source newline; the rest is verbatim.
const BASHRC_BODY: &str = "\
# AgentLinux PATH guard — sources /etc/profile.d/agentlinux.sh unconditionally
# so non-interactive bash invocations (ssh host 'cmd', sudo -u <user> bash -c)
# see the correct PATH + locale BEFORE the skel .bashrc case-return guard.
if [ -f /etc/profile.d/agentlinux.sh ]; then
  . /etc/profile.d/agentlinux.sh
fi";

/// Artefact 1: `/etc/profile.d/agentlinux.sh`. Reproduces the UNQUOTED `PROFILE`
/// heredoc byte-for-byte: `{user}`/`{home}` interpolate
/// where Bash expands `${_AL_USER}`/`${_AL_HOME}`; every `\$`/`` \` `` escape
/// becomes a LITERAL `$`/`` ` `` (the runtime shell vars + re-source guard stay
/// literal). Trailing newline preserved (the heredoc's final `\n`).
fn profile_d_content(user: &str, home: &str) -> String {
    // NOTE (byte-fidelity): the two-space indent on the `case`-arm lines is
    // load-bearing. A Rust `\`-line-continuation ESCAPE strips leading whitespace
    // on the continued line, so we must NOT use `\<newline>` here — the literal
    // carries REAL embedded newlines (flush-left source lines) instead, preserving
    // the ` *:` / ` *)` indentation byte-for-byte.
    format!(
        "\
# AgentLinux login environment (generated by agentlinux-install).
# Sourced by /etc/profile on interactive login shells AND `sudo -u {user} -i`.
# Re-source guard: bails on second source in the same shell session so that
# rc reload (e.g. `exec bash -l`) does not double-prepend PATH entries.
[ -n \"${{AGENTLINUX_PROFILE_SOURCED:-}}\" ] && return
export AGENTLINUX_PROFILE_SOURCED=1

export LANG=\"${{LANG:-C.UTF-8}}\"
export LC_ALL=\"${{LC_ALL:-C.UTF-8}}\"
# Keep the Antigravity CLI's catalog-managed version authoritative. The
# upstream-supported variable is harmless when Antigravity is not installed.
export AGY_CLI_DISABLE_AUTO_UPDATE=true

# Prepend in order so {home}/.npm-global/bin lands FIRST in the final
# PATH (a stray /usr/local/bin shim must lose to the user-owned binary).
# Case-prepend stacks LIFO: the LAST successful case-block prepends in front
# of everything, so we put .local/bin FIRST and .npm-global/bin SECOND.
# Case-guards prevent double-prepend on re-source (idempotency).
case \":${{PATH}}:\" in
  *:{home}/.local/bin:*) : ;;
  *) PATH=\"{home}/.local/bin:${{PATH}}\" ;;
esac
case \":${{PATH}}:\" in
  *:{home}/.npm-global/bin:*) : ;;
  *) PATH=\"{home}/.npm-global/bin:${{PATH}}\" ;;
esac
export PATH
"
    )
}

/// Artefact 3: `/etc/agentlinux.env`. Literal `KEY=VALUE`, NO `export`, NO
/// expansion (systemd + cron parse this shape literally). The PATH line reuses
/// `path` (the ONE `recipe_env::canonical_path` source) so it is byte-identical
/// to artefact 4 and the recipe env. Trailing newline preserved
fn agentlinux_env_content(user: &str, home: &str, path: &str) -> String {
    format!(
        "PATH={path}\n\
NPM_CONFIG_PREFIX={home}/.npm-global\n\
AGENTLINUX_USER={user}\n\
AGENTLINUX_AGENT_HOME={home}\n\
LANG=C.UTF-8\n\
LC_ALL=C.UTF-8\n\
AGY_CLI_DISABLE_AUTO_UPDATE=true\n"
    )
}

/// Artefact 4: `/etc/cron.d/agentlinux`. The comment header (example job, do-NOT-
/// uncomment, naming the install user in the user column) + the SAME `path`
/// literal as artefact 3 + LANG/LC_ALL/AGY. vixie-cron does NOT expand `$PATH`, so
/// the PATH is written fully expanded and byte-identical to artefact 3
fn cron_d_content(user: &str, path: &str) -> String {
    format!(
        "# AgentLinux cron environment (generated by agentlinux-install).\n\
# Any cron job placed in this file inherits the PATH/locale below.\n\
# Phase 2 ships NO default jobs. Example shape (do NOT uncomment):\n\
#   0 3 * * * {user} /usr/bin/true\n\
\n\
PATH={path}\n\
LANG=C.UTF-8\n\
LC_ALL=C.UTF-8\n\
AGY_CLI_DISABLE_AUTO_UPDATE=true\n"
    )
}

#[cfg(test)]
mod path_wiring_tests {
    use super::*;

    // --- The #1-risk cross-module invariant: the artefact-3 PATH line ==
    //  artefact-4 PATH line == recipe_env::canonical_path (byte-for-byte). ---

    /// Extract the `PATH=` line's value from an artefact's rendered content.
    fn path_line(content: &str) -> &str {
        content
            .lines()
            .find_map(|l| l.strip_prefix("PATH="))
            .expect("artefact must carry a PATH= line")
    }

    #[test]
    fn artefact3_artefact4_recipe_env_path_lines_are_byte_identical() {
        // The cross-module invariant: all three PATH strings derive
        // from the ONE recipe_env::canonical_path source, so they cannot drift.
        let home = "/home/agent";
        let canonical = recipe_env::canonical_path(home);
        let env3 = agentlinux_env_content("agent", home, &canonical);
        let cron4 = cron_d_content("agent", &canonical);

        assert_eq!(path_line(&env3), path_line(&cron4));
        assert_eq!(path_line(&env3), canonical);
        // Pin the exact literal so a byte regression here is caught immediately.
        assert_eq!(
            canonical,
            "/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin"
        );
    }

    #[test]
    fn path_ordering_is_user_prefixes_first_in_every_artefact() {
        // .npm-global/bin FIRST, then .local/bin, then system
        // — in artefacts 3 and 4 (the literal PATH) AND the profile.d case-prepend.
        let home = "/home/agent";
        let canonical = recipe_env::canonical_path(home);
        // The literal PATH: npm-global/bin index < .local/bin index < /usr/local/bin.
        let npm = canonical.find("/home/agent/.npm-global/bin").unwrap();
        let local = canonical.find("/home/agent/.local/bin").unwrap();
        let ulb = canonical.find("/usr/local/bin").unwrap();
        assert!(
            npm < local && local < ulb,
            "user prefixes must precede system"
        );

        // profile.d: the .npm-global/bin case-block is emitted AFTER .local/bin so
        // it stacks LIFO in FRONT (lands first in the final PATH).
        let profile = profile_d_content("agent", home);
        let local_case = profile.find("*:/home/agent/.local/bin:*").unwrap();
        let npm_case = profile.find("*:/home/agent/.npm-global/bin:*").unwrap();
        assert!(
            local_case < npm_case,
            ".local/bin case precedes .npm-global/bin (LIFO)"
        );
    }

    // --- Interpolate-user / literal-runtime-vars across the artefacts. ---

    #[test]
    fn artefacts_interpolate_user_and_home_for_non_default_user() {
        // AL-59: an alternate install user is fully wired — every per-user path
        // interpolates the resolved user/home.
        let (user, home) = ("claude", "/home/claude");
        let canonical = recipe_env::canonical_path(home);

        let profile = profile_d_content(user, home);
        assert!(profile.contains("sudo -u claude -i"));
        assert!(profile.contains("PATH=\"/home/claude/.local/bin:${PATH}\""));
        assert!(profile.contains("PATH=\"/home/claude/.npm-global/bin:${PATH}\""));

        let env3 = agentlinux_env_content(user, home, &canonical);
        assert!(env3.contains("AGENTLINUX_USER=claude\n"));
        assert!(env3.contains("AGENTLINUX_AGENT_HOME=/home/claude\n"));
        assert!(env3.contains("NPM_CONFIG_PREFIX=/home/claude/.npm-global\n"));
        assert_eq!(path_line(&env3), canonical);

        let cron4 = cron_d_content(user, &canonical);
        assert!(cron4.contains("#   0 3 * * * claude /usr/bin/true\n"));
        assert_eq!(path_line(&cron4), canonical);
    }

    #[test]
    fn profile_d_keeps_runtime_shell_vars_literal() {
        // The UNQUOTED-heredoc split: runtime shell vars ($PATH, ${LANG:-…}, the
        // re-source guard) stay LITERAL in the emitted file — Bash escaped them
        // with `\$` so they are NOT expanded at write time.
        let profile = profile_d_content("agent", "/home/agent");
        assert!(profile.contains("[ -n \"${AGENTLINUX_PROFILE_SOURCED:-}\" ] && return"));
        assert!(profile.contains("export LANG=\"${LANG:-C.UTF-8}\""));
        assert!(profile.contains("export LC_ALL=\"${LC_ALL:-C.UTF-8}\""));
        assert!(profile.contains("case \":${PATH}:\" in"));
        // The literal backticks around `sudo -u … -i` / `exec bash -l`.
        assert!(profile.contains("`sudo -u agent -i`"));
        assert!(profile.contains("`exec bash -l`"));
    }

    // --- Byte-exact full-artefact snapshots for the default `agent` user. ---
    // These pin the EXACT bytes the RT-*/BHV-* bats grep. A drift in a trailing
    // newline, a marker delimiter, or a KEY=VALUE literal fails here first.

    #[test]
    fn profile_d_full_byte_snapshot_for_agent() {
        // Flush-left real-newline literal (NOT `\`-continuation, which would strip
        // the two-space `case`-arm indent) so this pins the EXACT bytes.
        let expected = "\
# AgentLinux login environment (generated by agentlinux-install).
# Sourced by /etc/profile on interactive login shells AND `sudo -u agent -i`.
# Re-source guard: bails on second source in the same shell session so that
# rc reload (e.g. `exec bash -l`) does not double-prepend PATH entries.
[ -n \"${AGENTLINUX_PROFILE_SOURCED:-}\" ] && return
export AGENTLINUX_PROFILE_SOURCED=1

export LANG=\"${LANG:-C.UTF-8}\"
export LC_ALL=\"${LC_ALL:-C.UTF-8}\"
# Keep the Antigravity CLI's catalog-managed version authoritative. The
# upstream-supported variable is harmless when Antigravity is not installed.
export AGY_CLI_DISABLE_AUTO_UPDATE=true

# Prepend in order so /home/agent/.npm-global/bin lands FIRST in the final
# PATH (a stray /usr/local/bin shim must lose to the user-owned binary).
# Case-prepend stacks LIFO: the LAST successful case-block prepends in front
# of everything, so we put .local/bin FIRST and .npm-global/bin SECOND.
# Case-guards prevent double-prepend on re-source (idempotency).
case \":${PATH}:\" in
  *:/home/agent/.local/bin:*) : ;;
  *) PATH=\"/home/agent/.local/bin:${PATH}\" ;;
esac
case \":${PATH}:\" in
  *:/home/agent/.npm-global/bin:*) : ;;
  *) PATH=\"/home/agent/.npm-global/bin:${PATH}\" ;;
esac
export PATH
";
        assert_eq!(profile_d_content("agent", "/home/agent"), expected);
    }

    #[test]
    fn agentlinux_env_full_byte_snapshot_for_agent() {
        let canonical = recipe_env::canonical_path("/home/agent");
        let expected = "PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin\n\
NPM_CONFIG_PREFIX=/home/agent/.npm-global\n\
AGENTLINUX_USER=agent\n\
AGENTLINUX_AGENT_HOME=/home/agent\n\
LANG=C.UTF-8\n\
LC_ALL=C.UTF-8\n\
AGY_CLI_DISABLE_AUTO_UPDATE=true\n";
        assert_eq!(
            agentlinux_env_content("agent", "/home/agent", &canonical),
            expected
        );
    }

    #[test]
    fn cron_d_full_byte_snapshot_for_agent() {
        let canonical = recipe_env::canonical_path("/home/agent");
        let expected = "# AgentLinux cron environment (generated by agentlinux-install).\n\
# Any cron job placed in this file inherits the PATH/locale below.\n\
# Phase 2 ships NO default jobs. Example shape (do NOT uncomment):\n\
#   0 3 * * * agent /usr/bin/true\n\
\n\
PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin\n\
LANG=C.UTF-8\n\
LC_ALL=C.UTF-8\n\
AGY_CLI_DISABLE_AUTO_UPDATE=true\n";
        assert_eq!(cron_d_content("agent", &canonical), expected);
    }

    #[test]
    fn bashrc_marker_block_body_is_the_quoted_literal() {
        // Artefact 2's body is the QUOTED heredoc — no interpolation, no trailing
        // newline (ensure_marker_block supplies the joiners). The full block the
        // bats grep for is begin\n{body}\n{end}\n at the TOP.
        assert_eq!(
            BASHRC_BODY,
            "\
# AgentLinux PATH guard — sources /etc/profile.d/agentlinux.sh unconditionally
# so non-interactive bash invocations (ssh host 'cmd', sudo -u <user> bash -c)
# see the correct PATH + locale BEFORE the skel .bashrc case-return guard.
if [ -f /etc/profile.d/agentlinux.sh ]; then
  . /etc/profile.d/agentlinux.sh
fi"
        );
        // Byte-fidelity: the indented `. /etc/profile.d/…` line keeps its two
        // leading spaces (the `\`-continuation-strip regression this test guards).
        assert!(BASHRC_BODY.contains("\n  . /etc/profile.d/agentlinux.sh\n"));
    }

    #[test]
    fn bashrc_marker_block_renders_at_top_over_existing_content() {
        // ensure_marker_block Placement::Top puts our guard-source BEFORE the skel
        // non-interactive early-return so SSH + sudo -u bash
        // -c pick up PATH. Exercised against a temp file (no root needed).
        let d = tempfile::TempDir::new().unwrap();
        let f = d.path().join(".bashrc");
        std::fs::write(&f, "case $- in *i*) ;; *) return;; esac\n# user tail\n").unwrap();
        sysio::ensure_marker_block(&f, "agentlinux-path", BASHRC_BODY).unwrap();
        let out = std::fs::read_to_string(&f).unwrap();
        // The begin marker precedes the skel early-return line (top placement).
        let begin = out.find("# >>> agentlinux-path begin >>>").unwrap();
        let skel = out.find("case $- in *i*)").unwrap();
        assert!(
            begin < skel,
            "marker block must be at TOP (before skel early-return)"
        );
        // User content outside the block survives.
        assert!(out.contains("# user tail\n"));
        // Exactly one block.
        assert_eq!(out.matches("# >>> agentlinux-path begin >>>").count(), 1);
    }

    #[test]
    fn is_reused_maps_reuse_family_true_create_false() {
        assert!(is_reused(StepResolution::Reuse));
        assert!(is_reused(StepResolution::ReuseWithWarning));
        assert!(is_reused(StepResolution::Remediate));
        assert!(!is_reused(StepResolution::Create));
    }
}
