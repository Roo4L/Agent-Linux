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
use crate::provision::{self, log, ProvisionCtx, Resolutions};
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
    let name = match user_flag {
        Some(name) => name.to_string(),
        // M-1: the default/env-resolved user ($AGENTLINUX_USER > env-file > agent)
        // must pass the SAME reserved-name denylist the explicit --user path uses,
        // so both agree on what may become the install user.
        None => resolve_install_user(),
    };
    if validate_user_name(&name) {
        Ok(name)
    } else {
        eprintln!(
            "agentlinux provision: invalid install-user name '{name}' — must match \
             ^[a-z][a-z0-9_-]*$ and must not be root or a reserved/system account"
        );
        Err(ExitCode::from(EX_USAGE))
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
    // Step 10 — agent user.
    log::line("agentlinux provision: 10-agent-user");
    provision::agent_user::run(ctx).map_err(|e| {
        log::line(&format!(
            "agentlinux provision: 10-agent-user step failed: {e}"
        ));
        ExitCode::from(EX_SOFTWARE)
    })?;

    // Step 20 — sudoers. The user must exist before granting it sudo, so this
    // runs AFTER agent_user in the ordered vec.
    log::line("agentlinux provision: 20-sudoers");
    provision::sudoers::run(ctx).map_err(|e| {
        log::line(&format!(
            "agentlinux provision: 20-sudoers step failed: {e}"
        ));
        ExitCode::from(EX_SOFTWARE)
    })?;

    // Step 30 — nodejs. The NodeSource pre-Node bootstrap + RT-01 verify + RT-04
    // npm-prefix + REMEDIATE-01. Runs AFTER sudoers in numeric order.
    log::line("agentlinux provision: 30-nodejs");
    provision::nodejs::run(ctx).map_err(|e| {
        log::line(&format!("agentlinux provision: 30-nodejs step failed: {e}"));
        ExitCode::from(EX_SOFTWARE)
    })?;

    // Step 40 — path wiring. The four six-mode PATH artefacts (profile.d +
    // <home>/.bashrc --top + /etc/agentlinux.env + /etc/cron.d). Runs AFTER nodejs
    // (references the .npm-global prefix). Additive/unconditional.
    log::line("agentlinux provision: 40-path-wiring");
    provision::path_wiring::run(ctx).map_err(|e| {
        log::line(&format!(
            "agentlinux provision: 40-path-wiring step failed: {e}"
        ));
        ExitCode::from(EX_SOFTWARE)
    })?;

    // Step 50 — registry CLI. Stage the TS bundle + catalog snapshot + empty
    // state dir, symlink `agentlinux` onto the install user's PATH, verify as the
    // install user. Runs LAST (50 follows 40): the .npm-global/bin dir +
    // /etc/agentlinux.env must exist first.
    log::line("agentlinux provision: 50-registry-cli");
    provision::registry_cli::run(ctx).map_err(|e| {
        log::line(&format!(
            "agentlinux provision: 50-registry-cli step failed: {e}"
        ));
        ExitCode::from(EX_SOFTWARE)
    })?;
    Ok(())
}

/// `run_agent_adoption` port (agentlinux-install:341-346). After provisioning,
/// record any pre-existing reuse-eligible catalog agents into managed sentinels
/// via `agentlinux adopt --all` AS the install user. Best-effort: a failure must
/// NOT fail an otherwise-successful install (the Bash `|| log_warn`). The command
/// is dispatched through the Phase-56 dispatcher as the install user.
fn run_agent_adoption(user: &str) {
    log::line(&format!(
        "agentlinux provision: adopting pre-existing reuse-eligible agents as {user} (agentlinux adopt --all)"
    ));
    let argv: Vec<String> = ["agentlinux", "adopt", "--all"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let r = crate::dispatcher::as_user(user, &argv, &[], false, None);
    if r.exit_code != 0 {
        log::line(
            "agentlinux provision: agentlinux adopt --all reported a problem \
             (continuing; run it manually to retry)",
        );
    }
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

    // 2b. Adoption-safety gate (H-1, remediate.sh:109-126 / agentlinux-install:481-484):
    //     refuse to adopt an EXISTING system account (UID < 1000). This runs BEFORE
    //     both the purge path (so `userdel -r` can never remove a system/daemon
    //     account) AND the install path (so a system home is never overwritten +
    //     granted NOPASSWD sudo), for the explicit --user AND the default/env-
    //     resolved user alike. A non-existent name (created fresh / idempotent
    //     purge) and a regular login (UID >= 1000, adopted) both pass.
    if !provision::probe::user_adoptable(&install_user) {
        eprintln!(
            "agentlinux provision: refusing to adopt existing system account \
             '{install_user}' (UID < 1000). Choose a name that is free or a regular \
             login (UID >= 1000)."
        );
        return ExitCode::from(EX_USAGE);
    }

    // 3. --purge (Q3). Ordered 7-step teardown — runs BEFORE the log-file tee (the
    //    Bash purge removes the log LAST) and before distro detect (it seeds the
    //    family itself, like run_purge:375). Always exits 0. require_root is the
    //    caller's contract (main::dispatch); a non-root purge fails on the mutating
    //    syscalls, which is the correct surface.
    if args.purge {
        return run_purge(&install_user, &install_home, args.remove_nodejs);
    }

    // 4. Distro detect (the apt↔dnf fork point every later step branches on). Also
    //    needed by --report-only/--dry-run so the report reflects the real family.
    let distro = match distro::detect_distro_from_env() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("agentlinux provision: {e}");
            return ExitCode::from(EX_SOFTWARE);
        }
    };

    // 5. --report-only (Q3): emit the detection report + exit 0, ZERO mutation.
    //    Short-circuits before the DECIDE phase's per-agent gate iteration is
    //    even needed for a report — the report is the detected host state.
    if args.report_only {
        return report_only(&install_user, &distro);
    }

    // 6. DECIDE phase (PROV-02): probe the host + iterate the Rust `canonical_path`
    //    map IN-PROCESS, calling the pure `reuse::agent_decision` gate per id. NO
    //    Bash map read, NO `reuse-decision` shell-out — the Rust map is the single
    //    authoritative per-agent enumerator.
    let resolutions = Resolutions::from_decide(
        crate::CANONICAL_IDS,
        crate::canonical_path,
        crate::GSD_SYSTEM_PATH,
    );

    let ctx = ProvisionCtx {
        install_user,
        install_home,
        family: distro.family,
        resolutions,
        yes: args.yes,
        dry_run: args.dry_run,
    };

    // 7. --dry-run (Q3): print the pre-flight report + the per-agent decisions,
    //    exit 0, ZERO mutation. After the DECIDE phase so the report reflects every
    //    decision the real install would make.
    if ctx.dry_run {
        return dry_run_report(&ctx, &distro);
    }

    // 8. Open the install transcript (INST-01) — mirrors the Bash entrypoint's
    //    `install -m 0644 /dev/null "$LOG_FILE"` + tee. Best-effort: a create
    //    failure degrades to stderr-only (like the Bash pre-tee path).
    let log_path = log::init();
    log::line(&format!(
        "agentlinux-install v{} starting",
        crate::provision::registry_cli::agentlinux_version()
    ));

    // 9. Run the fixed ordered step vec. On success emit the `agentlinux-install
    //    complete` banner (INST-01) + run best-effort agent adoption.
    match run_steps(&ctx) {
        Ok(()) => {
            run_agent_adoption(&ctx.install_user);
            // M-3: only name the transcript path when it was actually persisted;
            // if log::init could not open the file, the banner must not assert a
            // file that does not exist.
            if log::is_active() {
                log::line(&format!(
                    "agentlinux-install complete (transcript: {})",
                    log_path.display()
                ));
            } else {
                log::line("agentlinux-install complete (stderr-only; transcript unavailable)");
            }
            ExitCode::SUCCESS
        }
        Err(code) => code,
    }
}

/// `run_purge` port (agentlinux-install:363-450) — the ordered 7-step teardown.
/// Every rm target is a LITERAL absolute path; the ONLY `$VAR`'d target is the
/// charset-validated install-user home, fed to `userdel -r` (NEVER `rm -rf $VAR`).
/// Recipe paths derive from the catalog snapshot keyed by the sentinel BASENAME
/// (T-57-15: a tampered sentinel cannot pick scripts to run as agent). Always
/// exits 0.
fn run_purge(user: &str, home: &str, remove_nodejs: bool) -> ExitCode {
    eprintln!("agentlinux provision: running --purge (destructive) — install user '{user}'");

    // Seed the family so the NodeSource-repo + pkg_remove steps dispatch correctly
    // (run_purge:375-377). Fall back to Debian if detection refuses so a teardown
    // never aborts mid-way and orphans the user (`|| true` + `:=debian`).
    let family = distro::detect_distro_from_env()
        .map(|d| d.family)
        .unwrap_or(distro::Family::Debian);

    let version = crate::provision::registry_cli::agentlinux_version();

    // Step 1: per-agent uninstall.sh for every sentinel. Look up recipe paths from
    // the catalog snapshot keyed by the sentinel BASENAME — NOT from sentinel JSON.
    let state_dir = std::path::PathBuf::from("/opt/agentlinux/state/installed.d");
    if state_dir.is_dir() {
        if let Ok(entries) = std::fs::read_dir(&state_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().is_none_or(|e| e != "json") {
                    continue;
                }
                let Some(id) = path.file_stem().and_then(|s| s.to_str()) else {
                    continue;
                };
                let recipe = format!("/opt/agentlinux/catalog/{version}/agents/{id}/uninstall.sh");
                if std::path::Path::new(&recipe).is_file() {
                    eprintln!("agentlinux provision: running uninstall.sh for {id}");
                    let argv: Vec<String> =
                        ["bash", &recipe].iter().map(|s| s.to_string()).collect();
                    // Recipes guard on ${AGENTLINUX_AGENT_HOME:?}; runner.ts is gone
                    // during --purge, so provide it explicitly (run_purge:395).
                    let env = vec![("AGENTLINUX_AGENT_HOME".to_string(), home.to_string())];
                    let r = crate::dispatcher::as_user(user, &argv, &env, false, None);
                    if r.exit_code != 0 {
                        eprintln!(
                            "agentlinux provision: uninstall.sh for {id} failed (continuing)"
                        );
                    }
                } else {
                    eprintln!(
                        "agentlinux provision: no uninstall.sh for {id} at {recipe}; skipping"
                    );
                }
                let _ = std::fs::remove_file(&path);
            }
        }
    }

    // Step 2: remove /opt/agentlinux (CLI dist, catalog snapshot, state) — LITERAL.
    let _ = std::fs::remove_dir_all("/opt/agentlinux");

    // Step 3 + 3.5: PATH artefacts + the sudoers drop-in — all LITERAL paths.
    for f in [
        "/etc/profile.d/agentlinux.sh",
        "/etc/agentlinux.env",
        "/etc/cron.d/agentlinux",
        "/etc/sudoers.d/agentlinux",
    ] {
        let _ = std::fs::remove_file(f);
    }

    // Step 4: NodeSource repo files — the single source of truth shared with the
    // 30-nodejs idempotency gate. Each path is a static in-code literal per family.
    for repo_file in crate::pkg::nodesource_repo_paths(family) {
        let _ = std::fs::remove_file(&repo_file);
    }

    // Step 5: optionally remove nodejs (opt-in — other users may depend on it).
    if remove_nodejs {
        eprintln!("agentlinux provision: removing nodejs package (family-correct purge)");
        if crate::pkg::pkg_remove(family, &["nodejs"]).is_err() {
            eprintln!("agentlinux provision: purge nodejs failed");
        }
        let _ = crate::pkg::pkg_autoremove(family);
    }

    // Step 6: remove the install user + its home. The name is charset-validated
    // upstream, so it is safe as a `userdel -r` argument (NEVER `rm -rf $VAR`).
    remove_install_user(user);

    // Step 7: LAST — remove the install log (LITERAL path).
    let _ = std::fs::remove_file(log::log_path());
    eprintln!("agentlinux provision: --purge complete");
    ExitCode::SUCCESS
}

/// Remove the install user + home via `userdel -r` (run_purge:438-445). `pkill -u`
/// first to avoid "user is logged in"; a userdel failure retries with `-rf`. The
/// name is charset-validated upstream — it is the ONLY `$VAR` fed to userdel, and
/// it never reaches an `rm -rf`.
fn remove_install_user(user: &str) {
    // `id <user>` — skip if the user does not exist.
    if !crate::provision::probe::user_exists(user) {
        return;
    }
    let _ = std::process::Command::new("pkill")
        .arg("-u")
        .arg(user)
        .status();
    std::thread::sleep(std::time::Duration::from_secs(1));
    let ok = std::process::Command::new("userdel")
        .arg("-r")
        .arg(user)
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !ok {
        eprintln!("agentlinux provision: userdel -r {user} failed; trying userdel -rf");
        let _ = std::process::Command::new("userdel")
            .arg("-rf")
            .arg(user)
            .status();
    }
}

/// `--report-only` (agentlinux-install:545-548): emit the detection report + exit
/// 0. ZERO mutation. The report is the detected host state — the per-agent
/// decisions + the resolved distro family.
fn report_only(user: &str, distro: &distro::Distro) -> ExitCode {
    emit_report(user, distro);
    ExitCode::SUCCESS
}

/// `--dry-run` (agentlinux-install:590-596): print the pre-flight report + exit 0.
/// ZERO mutation. After the DECIDE phase so the report reflects every decision the
/// real install would make.
fn dry_run_report(ctx: &ProvisionCtx, distro: &distro::Distro) -> ExitCode {
    eprintln!("agentlinux provision: [DRY-RUN] pre-flight report (no host mutation):");
    emit_report(&ctx.install_user, distro);
    for (id, res) in &ctx.resolutions.agents {
        eprintln!("agentlinux provision: [DRY-RUN] agents.{id} = {res:?}");
    }
    eprintln!(
        "agentlinux provision: [DRY-RUN] on apply, reuse-eligible agents are adopted \
         into managed sentinels (agentlinux adopt --all)"
    );
    eprintln!(
        "agentlinux provision: [DRY-RUN] exit 0 (no mutation; re-run without --dry-run to apply)"
    );
    ExitCode::SUCCESS
}

/// The shared detection-report body (the Rust analogue of `detect::emit_report`).
/// Prints the resolved install user + distro family + the per-agent decisions over
/// the Rust `canonical_path` map, sourced from the same in-process probe+gate the
/// install path uses. A report is read-only — NO mutation.
fn emit_report(user: &str, distro: &distro::Distro) {
    eprintln!("agentlinux provision: detection report");
    eprintln!("  install-user: {user}");
    eprintln!(
        "  distro: version={} family={:?}",
        distro.version, distro.family
    );
    for &id in crate::CANONICAL_IDS {
        let probe = crate::provision::probe::probe_agent(id);
        let decision = agentlinux_core::reuse::agent_decision(
            id,
            &probe.status,
            if probe.path.is_empty() {
                None
            } else {
                Some(probe.path.as_str())
            },
            crate::canonical_path(id),
            crate::GSD_SYSTEM_PATH,
        );
        eprintln!(
            "  agent {id}: status={} decision={}",
            probe.status,
            decision.as_str()
        );
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

    #[test]
    fn default_path_reserved_name_is_ex_usage() {
        // M-1: the default/env-resolved user must go through the SAME denylist.
        // Force $AGENTLINUX_USER to a reserved name and confirm the None (default)
        // path rejects it with EX_USAGE, exactly as the explicit --user path does.
        let _g = crate::test_support::env_guard();
        std::env::set_var("AGENTLINUX_USER", "root");
        assert_eq!(
            resolve_provision_user(None).unwrap_err(),
            ExitCode::from(EX_USAGE)
        );
        std::env::remove_var("AGENTLINUX_USER");
    }

    #[test]
    fn adoption_gate_refuses_uid_below_1000() {
        // H-1: an EXISTING system account (UID < 1000) is not adoptable — the gate
        // the purge path + install path both consult. `root` (UID 0) exists on
        // every host.
        assert!(!provision::probe::user_adoptable("root"));
        assert!(!provision::probe::user_adoptable("daemon"));
    }

    #[test]
    fn adoption_gate_allows_regular_login_and_nonexistent() {
        // A regular login (UID >= 1000) or a free name is adoptable — the agent
        // user (UID >= 1000) must still purge/install cleanly.
        assert!(provision::probe::user_adoptable(
            "nonexistent-user-xyz-9042"
        ));
        let self_uid = nix::unistd::Uid::current();
        if self_uid.as_raw() >= 1000 {
            if let Ok(Some(me)) = nix::unistd::User::from_uid(self_uid) {
                assert!(provision::probe::user_adoptable(&me.name));
            }
        }
    }
}
