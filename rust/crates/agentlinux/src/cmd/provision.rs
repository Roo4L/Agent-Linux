//! cmd/provision.rs — the Phase-57 provisioner ORCHESTRATOR shell.
//!
//! Reproduces the `plugin/bin/agentlinux-install` main() order skeleton
//! (agentlinux-install:452-613) as a fixed ordered step vec. Wave 1 wires ONLY
//! `agent_user` (10-agent-user.sh); the later steps
//! (`sudoers`/`nodejs`/`path_wiring`/`registry_cli`) are LOUD not-yet-wired
//! markers so a premature full run cannot silently skip a step — each later wave
//! replaces its marker with the real `run(&ctx)` call.
//!
//! Entry contract (Pitfall 7): this verb is dispatched through
//! `guard::require_root` (EUID==0) in `main::dispatch`, NOT the CLI-05
//! `guard_agent_user` (which rejects root). The provisioner runs BEFORE any
//! agent user / Node exists.
//!
//! DECIDE-THEN-ACT: Wave 1 seeds `Resolutions::seed_create()` directly (the full
//! detect→decide wiring lands in Wave 5); the step loop dispatches on the tokens
//! so Wave 5 swaps the seed without restructuring this file.

use crate::cli::ProvisionArgs;
use crate::distro;
use crate::provision::{self, ProvisionCtx, Resolutions};
use crate::recipe_env::resolve_install_user;
use std::process::ExitCode;

/// EX_USAGE (sysexits.h) — the flag-contradiction / bad-name exit code, matching
/// the Bash parse_args `exit "$EX_USAGE"`.
const EX_USAGE: u8 = 64;
/// EX_SOFTWARE (sysexits.h) — a runtime provisioner failure (a step's I/O error).
const EX_SOFTWARE: u8 = 70;

/// Reserved / system-account denylist — byte-for-byte with
/// `AGENTLINUX_RESERVED_USER_NAMES` (`plugin/lib/remediate.sh:78-82`). A name
/// matching the POSIX charset but on this list must NEVER become the install
/// user (granting NOPASSWD sudo to root/a daemon is an elevation hole — T-57-05).
const RESERVED_USER_NAMES: &[&str] = &[
    "root",
    "daemon",
    "bin",
    "sys",
    "sync",
    "games",
    "man",
    "lp",
    "mail",
    "news",
    "uucp",
    "proxy",
    "www-data",
    "backup",
    "list",
    "irc",
    "gnats",
    "nobody",
    "_apt",
    "systemd-network",
    "systemd-resolve",
    "systemd-timesync",
    "messagebus",
    "sshd",
];

/// `validate_user_name` port (`remediate.sh:92-107`): POSIX charset
/// (`^[a-z][a-z0-9_-]*$`) AND not a reserved/system account (case-insensitive,
/// plus the whole `systemd-*` prefix). PURE — the runtime UID<1000 adoption gate
/// (`user_adoptable`) is a separate check the full detect wiring lands in Wave 5.
fn validate_user_name(name: &str) -> bool {
    let mut chars = name.chars();
    match chars.next() {
        Some(c) if c.is_ascii_lowercase() => {}
        _ => return false, // empty or non-[a-z] first char
    }
    if !chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-') {
        return false;
    }
    let lower = name.to_ascii_lowercase();
    if lower.starts_with("systemd-") {
        return false;
    }
    !RESERVED_USER_NAMES.contains(&lower.as_str())
}

/// Resolve the install user with `--user` precedence: an explicit `--user` (when
/// valid) wins over `$AGENTLINUX_USER` / the env-file / `agent`; otherwise defer
/// to `resolve_install_user()` (which already applies the `$AGENTLINUX_USER` >
/// env-file > `agent` precedence, mirroring agentlinux-install:459-474). Returns
/// `Err` (→ EX_USAGE) on an explicit but invalid `--user`, matching the Bash
/// parse-time `validate_user_name` reject.
fn resolve_provision_user(user_flag: Option<&str>) -> Result<String, ExitCode> {
    match user_flag {
        Some(name) => {
            if validate_user_name(name) {
                Ok(name.to_string())
            } else {
                eprintln!(
                    "agentlinux provision: invalid install-user name '{name}' — must match \
                     ^[a-z][a-z0-9_-]*$ and must not be root or a reserved/system account"
                );
                Err(ExitCode::from(EX_USAGE))
            }
        }
        None => Ok(resolve_install_user()),
    }
}

/// Detect the two flag contradictions the Bash parse_args rejects
/// (agentlinux-install:244-272): `--yes`×`--no-yes` and `--dry-run`×`--yes`.
/// Returns the EX_USAGE exit on either, else `Ok(())`.
fn check_flag_contradictions(args: &ProvisionArgs) -> Result<(), ExitCode> {
    if args.yes && args.no_yes {
        eprintln!("agentlinux provision: contradictory flags — --yes and --no-yes");
        return Err(ExitCode::from(EX_USAGE));
    }
    if args.dry_run && args.yes {
        eprintln!(
            "agentlinux provision: contradictory flags — --dry-run forbids --yes \
             (dry-run never mutates; --yes is a mutation gate)"
        );
        return Err(ExitCode::from(EX_USAGE));
    }
    Ok(())
}

/// Validate `--report-format` (text|json) mirroring agentlinux-install:282-289.
fn check_report_format(args: &ProvisionArgs) -> Result<(), ExitCode> {
    match args.report_format.as_deref() {
        None | Some("text") | Some("json") => Ok(()),
        Some(other) => {
            eprintln!(
                "agentlinux provision: --report-format must be 'text' or 'json' (got: {other})"
            );
            Err(ExitCode::from(EX_USAGE))
        }
    }
}

/// The fixed ordered step vec — the Rust equivalent of `run_provisioners`'
/// numeric-ordered source (agentlinux-install:313-330), as an EXPLICIT vec (no
/// filesystem glob): `[agent_user, sudoers, nodejs, path_wiring, registry_cli]`.
/// Wave 1 wires `agent_user`; the rest are loud not-yet-wired markers each later
/// wave replaces with a real `run(&ctx)`.
fn run_steps(ctx: &ProvisionCtx) -> Result<(), ExitCode> {
    // Step 10 — agent user (Wave 1).
    provision::agent_user::run(ctx).map_err(|e| {
        eprintln!("agentlinux provision: 10-agent-user step failed: {e}");
        ExitCode::from(EX_SOFTWARE)
    })?;

    // Step 20 — sudoers (Wave 2). The user must exist before granting it sudo, so
    // this runs AFTER agent_user in the ordered vec.
    provision::sudoers::run(ctx).map_err(|e| {
        eprintln!("agentlinux provision: 20-sudoers step failed: {e}");
        ExitCode::from(EX_SOFTWARE)
    })?;

    // Step 30 — nodejs (Wave 3). The NodeSource pre-Node bootstrap + RT-01 verify +
    // RT-04 npm-prefix + REMEDIATE-01. Runs AFTER sudoers in numeric order (Node
    // install needs no sudoers, but follows 10→20→30).
    provision::nodejs::run(ctx).map_err(|e| {
        eprintln!("agentlinux provision: 30-nodejs step failed: {e}");
        ExitCode::from(EX_SOFTWARE)
    })?;

    // Step 40 — path wiring (Wave 4). The four six-mode PATH artefacts
    // (profile.d + <home>/.bashrc --top + /etc/agentlinux.env + /etc/cron.d).
    // Runs AFTER nodejs (40 follows 30): it references the .npm-global prefix
    // established by Wave 3. Additive/unconditional — no RESOLUTIONS dispatch.
    provision::path_wiring::run(ctx).map_err(|e| {
        eprintln!("agentlinux provision: 40-path-wiring step failed: {e}");
        ExitCode::from(EX_SOFTWARE)
    })?;

    // Step 50 — loud not-yet-wired marker (replaced by Wave 5). A premature full
    // run surfaces exactly what is missing instead of silently skipping a step
    // (T-57-03 fail-loud).
    eprintln!("agentlinux provision: 50-registry-cli step not-yet-wired (Wave 5)");
    Ok(())
}

/// `agentlinux provision` — the orchestrator entrypoint. Reproduces the Bash
/// main() order: validate flags → resolve+validate user → distro detect → seed
/// resolutions → build ctx → run the ordered step vec. `--report-only` /
/// `--dry-run` / `--purge` are structural stubs here (Wave 5 lands the report /
/// dry-run parity + purge); they return 0 with a loud "Wave 5" marker so the seam
/// exists.
pub fn provision(args: &ProvisionArgs) -> ExitCode {
    // 1. Flag validation (contradictions + report-format) → EX_USAGE on failure.
    if let Err(code) = check_flag_contradictions(args) {
        return code;
    }
    if let Err(code) = check_report_format(args) {
        return code;
    }

    // 2. Resolve + validate the install user (--user > $AGENTLINUX_USER > agent).
    let install_user = match resolve_provision_user(args.user.as_deref()) {
        Ok(u) => u,
        Err(code) => return code,
    };
    let install_home = format!("/home/{install_user}");

    // 3. --purge / --report-only structural stubs (Wave 5). Loud + exit 0 so the
    //    seam exists without pretending to do the work.
    if args.purge {
        eprintln!(
            "agentlinux provision: --purge is not-yet-wired (Wave 5); remove_nodejs={} — exit 0",
            args.remove_nodejs
        );
        return ExitCode::SUCCESS;
    }
    if args.report_only {
        eprintln!("agentlinux provision: --report-only is not-yet-wired (Wave 5) — exit 0");
        return ExitCode::SUCCESS;
    }

    // 4. Distro detect (the apt↔dnf fork point every later step branches on).
    let distro = match distro::detect_distro_from_env() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("agentlinux provision: {e}");
            return ExitCode::from(EX_SOFTWARE);
        }
    };

    // 5. DECIDE-phase seed (Wave 1: create for every component; Wave 5 swaps for
    //    the real detect→decide computation without touching the step loop).
    let resolutions = Resolutions::seed_create();

    let ctx = ProvisionCtx {
        install_user,
        install_home,
        family: distro.family,
        resolutions,
        yes: args.yes,
        dry_run: args.dry_run,
    };

    // 6. --dry-run structural stub (Wave 5 lands the pre-flight report parity).
    if ctx.dry_run {
        eprintln!(
            "agentlinux provision: --dry-run is not-yet-wired (Wave 5); no mutation — exit 0"
        );
        return ExitCode::SUCCESS;
    }

    // 7. Run the fixed ordered step vec.
    match run_steps(&ctx) {
        Ok(()) => ExitCode::SUCCESS,
        Err(code) => code,
    }
}

#[cfg(test)]
mod provision_tests {
    use super::*;

    fn args_default() -> ProvisionArgs {
        ProvisionArgs {
            user: None,
            yes: false,
            no_yes: false,
            dry_run: false,
            report_only: false,
            purge: false,
            remove_nodejs: false,
            report_format: None,
            verbose: false,
        }
    }

    #[test]
    fn contradiction_yes_no_yes_is_ex_usage() {
        let mut a = args_default();
        a.yes = true;
        a.no_yes = true;
        assert_eq!(
            check_flag_contradictions(&a).unwrap_err(),
            ExitCode::from(EX_USAGE)
        );
    }

    #[test]
    fn contradiction_dry_run_yes_is_ex_usage() {
        let mut a = args_default();
        a.dry_run = true;
        a.yes = true;
        assert_eq!(
            check_flag_contradictions(&a).unwrap_err(),
            ExitCode::from(EX_USAGE)
        );
    }

    #[test]
    fn no_contradiction_is_ok() {
        let a = args_default();
        assert!(check_flag_contradictions(&a).is_ok());
        let mut b = args_default();
        b.yes = true;
        assert!(check_flag_contradictions(&b).is_ok());
    }

    #[test]
    fn report_format_text_json_ok_other_is_ex_usage() {
        let mut a = args_default();
        a.report_format = Some("text".into());
        assert!(check_report_format(&a).is_ok());
        a.report_format = Some("json".into());
        assert!(check_report_format(&a).is_ok());
        a.report_format = Some("yaml".into());
        assert_eq!(
            check_report_format(&a).unwrap_err(),
            ExitCode::from(EX_USAGE)
        );
    }

    #[test]
    fn validate_user_name_charset_and_reserved() {
        assert!(validate_user_name("agent"));
        assert!(validate_user_name("claude"));
        assert!(validate_user_name("a1_-"));
        // First char must be [a-z].
        assert!(!validate_user_name(""));
        assert!(!validate_user_name("1agent"));
        assert!(!validate_user_name("Agent"));
        assert!(!validate_user_name("bad user"));
        // Reserved + systemd-* prefix.
        assert!(!validate_user_name("root"));
        assert!(!validate_user_name("nobody"));
        assert!(!validate_user_name("systemd-network"));
        assert!(!validate_user_name("systemd-anything"));
    }

    #[test]
    fn explicit_user_flag_valid_wins() {
        assert_eq!(resolve_provision_user(Some("claude")).unwrap(), "claude");
    }

    #[test]
    fn explicit_user_flag_invalid_is_ex_usage() {
        assert_eq!(
            resolve_provision_user(Some("root")).unwrap_err(),
            ExitCode::from(EX_USAGE)
        );
    }
}
