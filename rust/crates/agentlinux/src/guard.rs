//! guard.rs — the CLI-05 invoker guard.
//!
//! The registry CLI must run as the CONFIGURED install user
//! (`resolve_install_user()` — env /
//! `/etc/agentlinux.env`, default `agent`). When the invoker differs, print the
//! exact two-line stderr diagnostic and exit 64 (EX_USAGE), matching the
//! `plugin/bin/agentlinux-install` convention.
//!
//! # The invoker is geteuid-backed, NOT an env var
//! The TS invoker is `os.userInfo().username`, which resolves the EFFECTIVE uid's
//! passwd entry — intentionally NOT a caller-controlled `$USER`, so a hostile
//! caller cannot spoof the guard by exporting `USER=agent`. In Rust that is
//! `nix::unistd::User::from_uid(geteuid())`. The username is exposed as an
//! optional param PURELY as a test DI seam (mirroring the TS default-param
//! signature); production callers pass `None` to resolve the real EUID.
//!
//! # Wired before every verb
//! The TS `preAction` hook runs `guardAgentUser(actionCommand.name())` before ANY
//! subcommand — including the read-only `list`. So `main.rs` calls this guard for
//! every verb (CLI-05: `agentlinux list` as root → exit 64).

use crate::recipe_env::resolve_install_user;
use nix::unistd::{geteuid, User};
use std::process::ExitCode;

/// EX_USAGE (sysexits.h) — the guard's fail-fast exit code.
const EX_USAGE: u8 = 64;

/// `require_root` — the PRE-Node provisioner entry guard.
///
/// Byte-for-behavior port of `plugin/bin/agentlinux-install:305-310`
/// (`require_root`). The `provision` entrypoint runs BEFORE any Node/agent-user
/// exists and performs privileged systems I/O (useradd, chown, locale files), so
/// it must assert EUID==0 — NOT `guard_agent_user`, which resolves the invoker's
/// passwd entry and REJECTS root (the provisioner's REQUIRED invoker). Routing
/// `provision` through the wrong guard would make every real `sudo agentlinux
/// provision` exit 64.
///
/// Returns `ExitCode::SUCCESS` when EUID==0; else prints the diagnostic to stderr
/// and returns `ExitCode::from(64)` (mirrors the Bash `exit "$EX_USAGE"`).
///
/// `euid` is `None` in production (resolve the real EUID) or `Some` in tests (the
/// DI seam mirroring `guard_agent_user`'s `invoker` param convention).
#[must_use]
pub fn require_root(euid: Option<u32>) -> ExitCode {
    let euid = euid.unwrap_or_else(|| geteuid().as_raw());
    if euid == 0 {
        ExitCode::SUCCESS
    } else {
        // Byte-for-byte with agentlinux-install:307.
        eprintln!("agentlinux provision must run as root (EUID != 0). Re-run under sudo.");
        ExitCode::from(EX_USAGE)
    }
}

/// Resolve the invoker username from the EFFECTIVE uid (mirrors TS
/// `os.userInfo().username`). Falls back to the numeric euid as a string when the
/// passwd lookup yields nothing (no matching entry) — a value that will never
/// equal a POSIX install-user name, so the guard still fails closed.
fn effective_username() -> String {
    match User::from_uid(geteuid()) {
        Ok(Some(user)) => user.name,
        // No passwd entry for the euid (or lookup error): fail closed — return a
        // token that cannot equal the configured user, so the guard denies.
        _ => geteuid().to_string(),
    }
}

/// The pure guard decision (testable without touching `process::exit`): does the
/// invoker match the configured install user? Returns `Ok(())` on match, or
/// `Err((install_user, invoker))` carrying the two names the diagnostic needs.
fn guard_decision(invoker: &str, install_user: &str) -> Result<(), (String, String)> {
    if invoker == install_user {
        Ok(())
    } else {
        Err((install_user.to_string(), invoker.to_string()))
    }
}

/// CLI-05 guard: fail fast (exit 64) when the invoker is not the configured
/// install user. Port of `guardAgentUser`.
///
/// Returns `ExitCode::SUCCESS` on a match (the caller proceeds to run the verb);
/// prints the two-line stderr diagnostic and returns `ExitCode::from(64)` on a
/// mismatch (the caller returns it immediately — this mirrors the TS
/// `process.exit(64)`, but returning an `ExitCode` keeps the bin's single
/// `main -> ExitCode` exit path).
///
/// `invoker` is `None` in production (resolve the real EUID username) or `Some`
/// in tests (the DI seam mirroring the TS default param).
#[must_use]
pub fn guard_agent_user(subcommand: &str, invoker: Option<&str>) -> ExitCode {
    let install_user = resolve_install_user();
    let invoker = invoker.map_or_else(effective_username, str::to_string);
    match guard_decision(&invoker, &install_user) {
        Ok(()) => ExitCode::SUCCESS,
        Err((install_user, invoker)) => {
            // Byte-for-byte with guard/user.ts:19-22 — two eprintln lines.
            eprintln!(
                "agentlinux: {subcommand} must run as user '{install_user}' (invoker: '{invoker}')"
            );
            eprintln!("  try: sudo -u {install_user} -H agentlinux {subcommand}");
            ExitCode::from(EX_USAGE)
        }
    }
}

#[cfg(test)]
mod guard_tests {
    use super::*;

    // guard_decision is the pure heart of the guard; test the DECISION (not the
    // process exit) so a mismatch is asserted without spawning a subprocess.

    #[test]
    fn matching_invoker_is_ok() {
        assert!(guard_decision("agent", "agent").is_ok());
    }

    #[test]
    fn mismatched_invoker_is_err_with_both_names() {
        // CLI-05: root invoking a verb configured for `agent` → denied, and the
        // diagnostic carries BOTH names (install user + invoker).
        let err = guard_decision("root", "agent").unwrap_err();
        assert_eq!(err, ("agent".to_string(), "root".to_string()));
    }

    #[test]
    fn mismatch_against_a_configured_non_agent_user() {
        // A `--user=claude` install gates on `claude` (AL-50 AC4): an `agent`
        // invoker is now the MISMATCH.
        let err = guard_decision("agent", "claude").unwrap_err();
        assert_eq!(err, ("claude".to_string(), "agent".to_string()));
    }

    /// Configure the install user the guard gates on, from a fixture env file.
    /// Both variables are restored when the returned scope drops.
    ///
    /// These two tests used to wrap their bodies in `if
    /// !Path::new("/etc/agentlinux.env").exists()` — so on any host AgentLinux
    /// had actually provisioned, and in the Docker/QEMU containers after
    /// `provision` runs, the guard's only public-API coverage silently
    /// evaporated and still reported green.
    fn with_install_user(user: &str) -> (crate::test_support::EnvScope, tempfile::TempDir) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("agentlinux.env");
        std::fs::write(&path, format!("AGENTLINUX_USER={user}\n")).unwrap();
        let mut scope = crate::test_support::EnvScope::new();
        scope
            .unset("AGENTLINUX_USER")
            .set("AGENTLINUX_ENV_FILE", &path);
        (scope, dir)
    }

    #[test]
    fn guard_agent_user_returns_success_when_invoker_matches() {
        let (_scope, _dir) = with_install_user("agent");
        assert_eq!(guard_agent_user("list", Some("agent")), ExitCode::SUCCESS);
    }

    #[test]
    fn guard_agent_user_returns_64_when_invoker_mismatches() {
        let (_scope, _dir) = with_install_user("agent");
        // root invoking against the configured `agent` user → EX_USAGE(64).
        assert_eq!(
            guard_agent_user("list", Some("root")),
            ExitCode::from(EX_USAGE)
        );
    }

    #[test]
    fn guard_agent_user_gates_on_the_configured_user_not_the_default() {
        // AL-50: a `--user=claude` install gates on `claude`, so the erstwhile
        // default `agent` is now the one that is refused. This is the assertion
        // the env-file-absent guard made unwritable.
        let (_scope, _dir) = with_install_user("claude");
        assert_eq!(guard_agent_user("list", Some("claude")), ExitCode::SUCCESS);
        assert_eq!(
            guard_agent_user("list", Some("agent")),
            ExitCode::from(EX_USAGE)
        );
    }

    #[test]
    fn effective_username_resolves_the_euid_not_the_user_env_var() {
        // T-56-07: the invoker is geteuid-backed precisely so a hostile caller
        // cannot spoof the guard by exporting USER=agent. Assert the spoof does
        // NOT take, and that the resolved name is the euid's real passwd entry.
        let mut scope = crate::test_support::EnvScope::new();
        scope.set("USER", "agent-spoofed-xyzzy");
        let resolved = effective_username();
        assert_ne!(resolved, "agent-spoofed-xyzzy");
        let expected = User::from_uid(geteuid())
            .ok()
            .flatten()
            .map_or_else(|| geteuid().to_string(), |u| u.name);
        assert_eq!(resolved, expected);
    }

    #[test]
    fn a_euid_with_no_passwd_entry_fails_closed() {
        // The fallback returns the numeric euid, which can never equal a POSIX
        // install-user name (`^[a-z]…`), so the guard denies rather than admits.
        let numeric = geteuid().to_string();
        assert!(guard_decision(&numeric, "agent").is_err());
    }

    // --- require_root: the provision entry guard is the INVERSE of
    // guard_agent_user — EUID==0 proceeds, a non-root invoker exits 64.

    #[test]
    fn require_root_success_for_euid_zero() {
        assert_eq!(require_root(Some(0)), ExitCode::SUCCESS);
    }

    #[test]
    fn require_root_exits_64_for_nonroot() {
        // A regular login uid (1000) → EX_USAGE(64), the opposite of the CLI-05
        // guard (which would ACCEPT a matching non-root invoker).
        assert_eq!(require_root(Some(1000)), ExitCode::from(EX_USAGE));
    }
}
