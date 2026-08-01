//! cmd/provision.rs — the provisioner ORCHESTRATOR.
//!
//! Owns the order of a provision run and nothing else: validate flags → resolve
//! and gate the install user → detect the distro → DECIDE → flush bails → run
//! the ordered steps in `STEPS` → adopt pre-existing agents. Every step's actual
//! work lives in `crate::provision::<step>`.
//!
//! # Entry contract
//! This verb is dispatched through `guard::require_root` (EUID==0) in
//! `main::dispatch`, NOT the CLI-05 `guard_agent_user` — which resolves the
//! invoker's passwd entry and REJECTS root, the provisioner's required invoker.
//! Routing it through the wrong guard would make every real
//! `sudo agentlinux provision` exit 64. The provisioner runs BEFORE any agent
//! user or Node exists.
//!
//! # DECIDE-THEN-ACT
//! Every per-component decision is made up front, before any mutation. A host
//! that refuses a remediation exits 65 while still byte-identical. The steps
//! receive settled `StepResolution` tokens and only do I/O.

use crate::cli::ProvisionArgs;
use crate::distro;
use crate::provision::{self, log, ProvisionCtx, Resolutions};
use crate::recipe_env::resolve_install_user;
use std::io;
use std::process::ExitCode;

/// EX_USAGE (sysexits.h) — the flag-contradiction / bad-name exit code, matching
/// the Bash parse_args `exit "$EX_USAGE"`.
const EX_USAGE: u8 = 64;
/// EX_SOFTWARE (sysexits.h) — a runtime provisioner failure (a step's I/O error).
const EX_SOFTWARE: u8 = 70;
/// EX_DATAERR (sysexits.h) — incompatible host state (a wrong-shell user bail /
/// an operator-declined alt-user prompt).
const EX_DATAERR: u8 = 65;

/// Reserved / system-account denylist — byte-for-byte with
/// the reserved-name denylist. A name
/// matching the POSIX charset but on this list must NEVER become the install
/// user (granting NOPASSWD sudo to root/a daemon is an elevation hole —).
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
/// (`user_adoptable`) is a separate check — see `check_user_adoptable`.
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
        crate::plog!(
            "agentlinux provision: invalid install-user name '{name}' — must match \
             ^[a-z][a-z0-9_-]*$ and must not be root or a reserved/system account"
        );
        Err(ExitCode::from(EX_USAGE))
    }
}

/// UX-04 wrong-shell alt-user gate (`prompt::alt_user_or_bail`). Returns the user
/// to provision under: the same name when it is absent or shell-conforming; the
/// operator-chosen alternate on a TTY; else an `Err(exit)` — 65 for a non-TTY
/// bail-with-hint or an EOF decline, 64 for 3 invalid names. On a TTY the accepted
/// alternate is a fresh user provisioned via the normal Create path.
fn resolve_wrong_shell(user: &str) -> Result<String, ExitCode> {
    if provision::probe::user_state(user) != provision::probe::UserState::WrongShell {
        return Ok(user.to_string());
    }
    let suggested = provision::wizard::find_alt_user_name();

    if !provision::wizard::stdin_is_tty() {
        crate::plog!("agentlinux: existing user \"{user}\" is incompatible (wrong-shell).");
        match suggested.as_deref() {
            Some(s) => crate::plog!("Re-run with --user={s} or fix the existing user manually."),
            None => crate::plog!(
                "Re-run with --user=NAME (no auto-suggested name available — agent2..agent99 \
                 all taken) or fix the existing user manually."
            ),
        }
        return Err(ExitCode::from(EX_DATAERR));
    }

    crate::plog!(
        "pre-flight: existing user \"{user}\" has a wrong shell (DET-01 requires bash + a \
         writable home)."
    );
    crate::plog!("AgentLinux can create a new install user instead.");
    match suggested.as_deref() {
        Some(s) => crate::plog!("Suggested alternate name: {s}"),
        None => crate::plog!("No auto-suggested name available (agent2..agent99 all taken)."),
    }

    match provision::wizard::alt_user_prompt(suggested.as_deref(), &validate_user_name) {
        provision::wizard::AltUser::Chosen(name) => {
            crate::plog!("[ALT-USER] accepted: {name}");
            Ok(name)
        }
        provision::wizard::AltUser::DeclinedEof => {
            crate::plog!("[ALT-USER] declined — exiting 65 (EOF on prompt)");
            Err(ExitCode::from(EX_DATAERR))
        }
        provision::wizard::AltUser::Exhausted => {
            crate::plog!("[ALT-USER] 3 invalid responses — exiting 64 EX_USAGE");
            Err(ExitCode::from(EX_USAGE))
        }
    }
}

/// Adoption-safety gate (H-1): refuse to adopt an EXISTING system account
/// (UID < 1000).
///
/// Called at two points, both load-bearing: once before the purge path, so
/// `userdel -r` can never remove a system/daemon account; and again after the
/// alt-user prompt, because that branch can swap in an operator-TYPED name that
/// never passed the first check. `validate_user_name`'s reserved denylist is not
/// exhaustive of system accounts, so the passwd-DB gate has to run on the FINAL
/// name. A non-existent name and a regular login (UID >= 1000) both pass.
fn check_user_adoptable(install_user: &str) -> Result<(), ExitCode> {
    if provision::probe::user_adoptable(install_user) {
        return Ok(());
    }
    crate::plog!(
        "agentlinux provision: refusing to adopt existing system account \
         '{install_user}' (UID < 1000). Choose a name that is free or a regular \
         login (UID >= 1000)."
    );
    Err(ExitCode::from(EX_USAGE))
}

/// Detect the two flag contradictions parse_args rejects: `--yes`×`--no-yes` and
/// `--dry-run`×`--yes`. Returns the EX_USAGE exit on either, else `Ok(())`.
fn check_flag_contradictions(args: &ProvisionArgs) -> Result<(), ExitCode> {
    if args.yes && args.no_yes {
        crate::plog!("agentlinux provision: contradictory flags — --yes and --no-yes");
        return Err(ExitCode::from(EX_USAGE));
    }
    if args.dry_run && args.yes {
        crate::plog!(
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
            crate::plog!(
                "agentlinux provision: --report-format must be 'text' or 'json' (got: {other})"
            );
            Err(ExitCode::from(EX_USAGE))
        }
    }
}

/// The provisioner steps, in the order they must run. An explicit table rather
/// than a filesystem glob, so the order is reviewable here and cannot change
/// because a file was renamed.
///
/// The ordering constraints, which is why this is a sequence and not a set:
///  10 → 20 the user must exist before it can be granted sudo
///  20 → 30 the NodeSource bootstrap installs packages
///  30 → 40 the PATH artefacts reference the `.npm-global` prefix Node created
///  40 → 50 the symlink target dir and `/etc/agentlinux.env` must exist first
type Step = (&'static str, fn(&ProvisionCtx) -> io::Result<()>);

const STEPS: &[Step] = &[
    ("10-agent-user", provision::agent_user::run),
    ("20-sudoers", provision::sudoers::run),
    ("30-nodejs", provision::nodejs::run),
    ("40-path-wiring", provision::path_wiring::run),
    ("50-registry-cli", provision::registry_cli::run),
];

/// Run every step in `STEPS` in order, stopping at the first failure.
fn run_steps(ctx: &ProvisionCtx) -> Result<(), ExitCode> {
    for (label, step) in STEPS {
        log::line(&format!("agentlinux provision: {label}"));
        step(ctx).map_err(|e| {
            log::line(&format!("agentlinux provision: {label} step failed: {e}"));
            ExitCode::from(EX_SOFTWARE)
        })?;
    }
    Ok(())
}

/// `run_agent_adoption` port. After provisioning,
/// record any pre-existing reuse-eligible catalog agents into managed sentinels
/// via `agentlinux adopt --all` AS the install user. Best-effort: a failure must
/// NOT fail an otherwise-successful install (the Bash `|| log_warn`). The command
/// is dispatched through the dispatcher as the install user.
///
/// Two departures from a bare `["agentlinux","adopt","--all"]` dispatch — both
/// required because the dispatcher runs `sudo -u <user>` NON-login (the Bash used
/// `as_user_login`, which sourced the agent profile + `/etc/agentlinux.env`):
///  1. Invoke the ABSOLUTE staged symlink (`<home>/.npm-global/bin/agentlinux`),
///     not the bare name. `sudo`'s `secure_path` governs command lookup and does
///     NOT include the agent's `~/.npm-global/bin`, so a bare name is ENOENT →
///     exit 1 → a spurious "reported a problem" on EVERY greenfield provision
///     (OBS-01). An absolute path bypasses PATH lookup entirely.
///  2. Supply an explicit child env — the canonical PATH/HOME plus any inherited
///     `AGENTLINUX_*` seams — so the child resolves the state/catalog dirs the
///     same way the login shell would (real runs fall through to the `/opt`
///     defaults; the bats harness's seam vars are forwarded).
fn run_agent_adoption(user: &str, home: &str) {
    log::line(&format!(
        "agentlinux provision: adopting pre-existing reuse-eligible agents as {user} (agentlinux adopt --all)"
    ));
    let bin = format!("{home}/.npm-global/bin/agentlinux");
    let argv: Vec<String> = [bin.as_str(), "adopt", "--all"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let env = adoption_child_env(home);
    // Bound the wait: this is the LAST step of an unattended greenfield provision,
    // so an adopt that ever hangs (a probe that shells out, an NFS-backed home)
    // must not hang the whole installer after the real work is already done. A
    // buffered timeout collapses to exit 1 → the best-effort warning below.
    let r = crate::dispatcher::as_user(
        user,
        &argv,
        &env,
        crate::dispatcher::Capture::Buffered,
        Some(ADOPTION_TIMEOUT_MS),
    );
    if r.exit_code != 0 {
        // Now that the ENOENT false-positive is gone (absolute path + resolvable
        // env), a non-zero here is a REAL adopt failure — surface the exit code +
        // a trimmed stderr so an operator can diagnose it without re-running.
        // Collapse whitespace + cap length (char-boundary-safe — never slice by
        // byte index, which panics mid-UTF-8) so a noisy stderr stays one log line.
        let detail: String = r
            .stderr
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ")
            .chars()
            .take(200)
            .collect();
        log::line(&format!(
            "agentlinux provision: agentlinux adopt --all reported a problem \
             (exit {}; continuing; run it manually to retry){}",
            r.exit_code,
            if detail.is_empty() {
                String::new()
            } else {
                format!(": {detail}")
            },
        ));
    }
}

/// Bound on the best-effort post-provision adoption dispatch (see
/// `run_agent_adoption`). Generous — `adopt --all` is normally sub-second — but
/// finite so a hung adopt can never wedge an unattended install.
const ADOPTION_TIMEOUT_MS: u64 = 60_000;

/// The child environment for the best-effort adoption dispatch: the canonical
/// `PATH`/`HOME` for the install home, plus every `AGENTLINUX_*` variable present
/// in the provisioner's own environment (the bats seams + any release override).
/// Forwarding the seams — rather than an empty env — is what lets the child
/// resolve the same state/catalog dirs a login-shell invocation would.
fn adoption_child_env(home: &str) -> Vec<(String, String)> {
    let mut env: Vec<(String, String)> = vec![
        ("PATH".to_string(), crate::recipe_env::canonical_path(home)),
        ("HOME".to_string(), home.to_string()),
        // This provision run is HOLDING the host lock for its whole duration, and
        // the child is another `agentlinux` that would try to take the same lock.
        // Without the marker the child contends with its own parent, is refused,
        // and the post-provision adoption of pre-existing agents silently never
        // runs — visible only as a generic "adopt --all reported a problem".
        (
            crate::statelock::LOCK_INHERITED_ENV.to_string(),
            "1".to_string(),
        ),
    ];
    for (k, v) in std::env::vars() {
        // Don't let an inherited copy of the marker double up on the explicit one
        // set above — the child would see two values for the same key.
        if k.starts_with("AGENTLINUX_") && k != crate::statelock::LOCK_INHERITED_ENV {
            env.push((k, v));
        }
    }
    env
}

/// `agentlinux provision` — the orchestrator entrypoint.
///
/// Order: validate flags → resolve + gate the install user → `--purge` (if
/// asked) → detect the distro → DECIDE → `--dry-run`/`--report-only` (if asked)
/// → flush bails → open the transcript → run `STEPS` → adopt.
///
/// `--report-only` and `--dry-run` are read-only and return before the step
/// loop. `--purge` is a live teardown: it runs the uninstall recipes, removes
/// `/opt/agentlinux`, deletes the `/etc` artefacts and `userdel -r`s the user.
pub fn provision(args: &ProvisionArgs) -> ExitCode {
    // 1. Flag validation (contradictions + report-format) → EX_USAGE on failure.
    if let Err(code) = check_flag_contradictions(args) {
        return code;
    }
    if let Err(code) = check_report_format(args) {
        return code;
    }

    // 2. Resolve + validate the install user (--user > $AGENTLINUX_USER > agent).
    //  AL-50 AC3: when no --user is given AND we are on an interactive terminal
    //  AND the host is greenfield, prompt for the install user (ported from the
    //  Bash prompt::choose_install_user). The curl-installer path passes --user
    //  (or is non-TTY), so it never prompts. The wizard's result is already
    //  validated; a bare Enter / EOF / 3 invalid tries fall back to the default.
    // 1b. Open the install transcript (INST-01) — mirrors the Bash entrypoint's
    //  `install -m 0644 /dev/null "$LOG_FILE"` + tee, with single-slot rotation so
    //  a re-run does not destroy the failing run's evidence.
    //
    //  As early as it can be. It used to sit after the DECIDE phase and after
    //  `flush_or_exit`, so every outcome worth diagnosing — a wrong-shell host
    //  refused at the alt-user gate, a brownfield host that bails, an unsupported
    //  distro, the whole `--purge` teardown — produced NO transcript, and left the
    //  PREVIOUS run's file in place to be read as this one's. Only the two pure
    //  usage errors above (contradictory flags, a bad `--report-format`) now
    //  precede it, and neither touches the host.
    //
    //  `--dry-run` and `--report-only` are excluded: both are zero-mutation
    //  previews and creating the transcript would be a write.
    let log_path = if args.dry_run || args.report_only {
        log::log_path()
    } else {
        let path = log::init();
        log::line(&format!(
            "agentlinux-install v{} starting",
            crate::provision::registry_cli::agentlinux_version()
        ));
        path
    };

    let default_user = resolve_install_user();
    let default_home = format!("/home/{default_user}");
    let install_user = if args.user.is_none()
        && !args.dry_run
        && provision::wizard::stdin_is_tty()
        && provision::wizard::should_prompt_install_user(&default_user, &default_home)
    {
        provision::wizard::choose_install_user(&default_user, &validate_user_name)
    } else {
        match resolve_provision_user(args.user.as_deref()) {
            Ok(u) => u,
            Err(code) => return code,
        }
    };
    let install_home = format!("/home/{install_user}");

    // 2b. Adoption-safety gate, BEFORE the purge path and the install path alike.
    if let Err(exit) = check_user_adoptable(&install_user) {
        return exit;
    }

    // 3. --purge (Q3). Ordered 7-step teardown — runs BEFORE the log-file tee (the
    //  Bash purge removes the log LAST) and before distro detect (it seeds the
    //  family itself, like run_purge:375). Always exits 0. require_root is the
    //  caller's contract (main::dispatch); a non-root purge fails on the mutating
    //  syscalls, which is the correct surface.
    if args.purge {
        return run_purge(&install_user, &install_home, args.remove_nodejs);
    }

    // 4. Distro detect (the apt↔dnf fork point every later step branches on). Also
    //  needed by --report-only/--dry-run so the report reflects the real family.
    let distro = match distro::detect_distro_from_env() {
        Ok(d) => d,
        Err(e) => {
            crate::plog!("agentlinux provision: {e}");
            return ExitCode::from(EX_SOFTWARE);
        }
    };

    // 5. --report-only (Q3): emit the detection report + exit 0, ZERO mutation.
    //  Short-circuits before the DECIDE phase's per-agent gate iteration is
    //  even needed for a report — the report is the detected host state.
    if args.report_only {
        return report_only(
            &install_user,
            &install_home,
            &distro,
            args.report_format.as_deref(),
        );
    }

    // 5b. UX-04 wrong-shell alt-user gate. An EXISTING install user with a non-bash
    //  shell cannot be adopted (no chsh handler). On the real path (not report /
    //  dry-run — those preview the bail): a TTY prompts for an alternate name,
    //  a non-TTY prints the `--user=<suggested>` hint + exits 65. An accepted
    //  alternate is a FRESH user, so the normal Create path fully provisions it.
    let pre_alt_user = install_user.clone();
    let install_user = if args.dry_run {
        install_user
    } else {
        match resolve_wrong_shell(&install_user) {
            Ok(u) => u,
            Err(code) => return code,
        }
    };
    let install_home = format!("/home/{install_user}");
    // Whether the alt-user gate swapped in a fresh name (a newly-created user) —
    // drives the partial-provision recovery hint on a step failure below.
    let alt_user_chosen = install_user != pre_alt_user;

    // 5c. Re-gate: the alt-user branch above may have swapped in an operator-TYPED
    //  name that never passed the gate at step 2b.
    if let Err(exit) = check_user_adoptable(&install_user) {
        return exit;
    }

    // 6. --dry-run: print the pre-flight report, exit 0, ZERO mutation. The
    //  per-agent decisions are computed by `emit_report` — the one place that
    //  probe+gate loop runs.
    //
    //  This returns BEFORE the DECIDE phase, and must stay there. `decide_core`
    //  resolves a `NeedsPrompt` verdict by asking the operator on /dev/tty, and
    //  `check_flag_contradictions` forbids `--dry-run --yes`, so under `--dry-run`
    //  consent can never be pre-granted. Running DECIDE first therefore let a
    //  preview BLOCK indefinitely on a brownfield host with a drifted sudoers
    //  drop-in or a mis-owned npm prefix — waiting for consent to a change it was
    //  never going to apply, and then discarding the answer, since
    //  `dry_run_report` takes no resolutions. A preview must never be able to
    //  wedge an unattended orchestration step.
    if args.dry_run {
        return dry_run_report(&install_user, &install_home, &distro);
    }

    // 7. DECIDE phase: probe the host for the core components (REMEDIATE-01
    //  npm-prefix chown/rebase + REMEDIATE-03 sudoers drift), overwriting the
    //  default `Create` tokens with the real verdict and aggregating a bail when
    //  a state-overwriting remediation is refused (non-TTY, no --yes). ZERO
    //  mutation here — `flush_or_exit` below short-circuits (exit 65) BEFORE the
    //  step loop, so a refused host stays byte-identical.
    let mut resolutions = Resolutions::default();
    let mut bails: Vec<provision::remediate::Bail> = Vec::new();
    provision::remediate::decide_core(
        &install_user,
        &install_home,
        args.yes,
        &mut resolutions,
        &mut bails,
    );

    // 7b. Flush aggregated bails: if any core component resolved to an
    //  unconsented state-overwrite, print the [BAIL] lines + exit 65 (EX_DATAERR)
    //  NOW — before log-init / the step loop mutates anything.
    provision::remediate::flush_or_exit(&bails);

    // Past the flush, no token can still be `Bail`; narrowing here is what lets
    // every step dispatch over four cases instead of five.
    let resolutions = match resolutions.into_step() {
        Ok(r) => r,
        Err(component) => {
            crate::plog!(
                "agentlinux provision: internal error — RESOLUTIONS[{component}] is still \
                 'bail' after the bail flush; refusing to mutate the host"
            );
            return ExitCode::from(EX_SOFTWARE);
        }
    };

    let ctx = ProvisionCtx {
        install_user,
        install_home,
        family: distro.family,
        resolutions,
    };

    // 8. Run the fixed ordered step vec. On success emit the `agentlinux-install
    //  complete` banner (INST-01) + run best-effort agent adoption.
    match run_steps(&ctx) {
        Ok(()) => {
            // DETECT-phase cache write (detect/agents.sh): scan the host for every
            // catalog agent + persist `/run/agentlinux-detect.json`. Runs AFTER the
            // steps (PATH wiring + Node are in place, so the login-shell probe
            // resolves agent-owned bins) and BEFORE adoption, so a subsequent
            // `agentlinux install <id>` / `adopt --all` reads real host state and
            // REUSE-03 / REMEDIATE-04 can fire. Best-effort (logs on failure).
            crate::detect::scan_and_write(&ctx.install_user, &ctx.install_home);
            run_agent_adoption(&ctx.install_user, &ctx.install_home);
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
        Err(code) => {
            // Operability: an accepted alt-user is created fresh mid-run. If a
            // later step failed, that user is left half-provisioned — name the
            // recovery verbs so an orphan is a one-command fix, not a mystery.
            if alt_user_chosen {
                log::line(&format!(
                    "agentlinux provision: NOTE — newly-created install user '{u}' was only \
                     partially provisioned before this failure. Re-run \
                     `agentlinux provision --user {u}` to resume, or \
                     `agentlinux provision --purge --user {u}` to remove it.",
                    u = ctx.install_user
                ));
            }
            code
        }
    }
}

/// `run_purge` port — the ordered 7-step teardown.
/// Every rm target is a LITERAL absolute path; the ONLY `$VAR`'d target is the
/// charset-validated install-user home, fed to `userdel -r` (NEVER `rm -rf $VAR`).
/// Recipe paths derive from the catalog snapshot keyed by the sentinel BASENAME
/// (a tampered sentinel cannot pick scripts to run as agent).
///
/// Never aborts early — every step runs whatever the ones before it did, because a
/// half-torn-down host is worse than a fully-attempted one. But the exit code is
/// honest: 0 only when nothing the purge targeted is still present, 1 when
/// something survived (the account, `/opt/agentlinux`, or a `/etc` drop-in).
fn run_purge(user: &str, home: &str, remove_nodejs: bool) -> ExitCode {
    crate::plog!("agentlinux provision: running --purge (destructive) — install user '{user}'");

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
                    crate::plog!("agentlinux provision: running uninstall.sh for {id}");
                    let argv: Vec<String> =
                        ["bash", &recipe].iter().map(|s| s.to_string()).collect();
                    // Recipes guard on ${AGENTLINUX_AGENT_HOME:?}; runner.ts is gone
                    // during --purge, so provide it explicitly (run_purge:395).
                    let env = vec![("AGENTLINUX_AGENT_HOME".to_string(), home.to_string())];
                    // Bounded like every other recipe run. An uninstall recipe that
                    // wedges must not stop `--purge` — the whole point of the verb
                    // is to leave the host clean, and a per-recipe failure is
                    // already non-fatal here (the teardown continues below).
                    let r = crate::dispatcher::as_user(
                        user,
                        &argv,
                        &env,
                        crate::dispatcher::Capture::Buffered,
                        crate::dispatcher::recipe_timeout_ms(),
                    );
                    if r.exit_code != 0 {
                        crate::plog!(
                            "agentlinux provision: uninstall.sh for {id} failed (continuing)"
                        );
                    }
                } else {
                    crate::plog!(
                        "agentlinux provision: no uninstall.sh for {id} at {recipe}; skipping"
                    );
                }
                let _ = std::fs::remove_file(&path);
            }
        }
    }

    // A teardown that leaves something behind must not report success: the operator
    // reads `$?`, and an automated teardown-then-reprovision has nothing else to go
    // on. Every removal below still runs regardless of what failed before it —
    // `--purge` gets the host as clean as it can — but each one that leaves its
    // target in place is recorded here and turns the final exit code non-zero.
    // "Already absent" is the goal state, not a failure; only a path that still
    // EXISTS after we tried to remove it counts.
    let mut leftovers: Vec<String> = Vec::new();

    // Step 2: remove /opt/agentlinux (CLI dist, catalog snapshot, state) — LITERAL.
    let _ = std::fs::remove_dir_all("/opt/agentlinux");
    if std::path::Path::new("/opt/agentlinux").exists() {
        leftovers.push("/opt/agentlinux".to_string());
    }

    // Step 3 + 3.5: PATH artefacts + the sudoers drop-in — all LITERAL paths.
    for f in [
        "/etc/profile.d/agentlinux.sh",
        "/etc/agentlinux.env",
        "/etc/cron.d/agentlinux",
        "/etc/sudoers.d/agentlinux",
    ] {
        let _ = std::fs::remove_file(f);
        // The sudoers drop-in matters most: a surviving `NOPASSWD: ALL` grant on a
        // host the operator believes is torn down is a standing privilege the purge
        // was supposed to revoke. Note this checks OUR file only — sudo reads all of
        // /etc/sudoers.d plus /etc/sudoers, so a hand-copied `agentlinux.bak` or a
        // line an operator moved into /etc/sudoers survives a clean purge. Verifying
        // that would mean parsing sudoers, which we do not do; the log line below is
        // worded to claim only what this loop actually checked.
        if std::path::Path::new(f).exists() {
            leftovers.push(f.to_string());
        }
    }

    // Step 4: NodeSource repo files — the single source of truth shared with the
    // 30-nodejs idempotency gate. Each path is a static in-code literal per family.
    for repo_file in crate::pkg::nodesource_repo_paths(family) {
        let _ = std::fs::remove_file(&repo_file);
    }

    // Step 5: optionally remove nodejs (opt-in — other users may depend on it).
    if remove_nodejs {
        crate::plog!("agentlinux provision: removing nodejs package (family-correct purge)");
        if crate::pkg::pkg_remove(family, &["nodejs"]).is_err() {
            crate::plog!("agentlinux provision: purge nodejs failed");
        }
        let _ = crate::pkg::pkg_autoremove(family);
    }

    // Step 6: remove the install user + its home. The name is charset-validated
    // upstream, so it is safe as a `userdel -r` argument (NEVER `rm -rf $VAR`).
    remove_install_user(user);
    // Re-probe rather than trusting the exit code: `userdel -rf` can report failure
    // while having removed the account, and can report success on some paths while
    // leaving it. What the next run cares about is whether the account is gone.
    if crate::provision::probe::user_exists(user) {
        leftovers.push(format!("user '{user}'"));
    }
    // The HOME is a separate question from the account. `userdel -r` routinely exits
    // 12 ("can't remove home directory") while still deleting the passwd entry — a
    // bind mount, an immutable file, or a home the user does not own all produce
    // it. The account then looks gone, `leftovers` is empty, and the purge reports
    // success over a directory still holding ~/.claude/.credentials.json,
    // ~/.config/gh/hosts.yml and ~/.npmrc. Worse, the uid is now unallocated, so the
    // next useradd that recycles it silently inherits ownership of those secrets.
    if !home.is_empty() && std::path::Path::new(home).exists() {
        leftovers.push(format!("home '{home}' (may hold credentials)"));
    }

    // Step 7: LAST — remove the install log (LITERAL path). Note this unlinks the
    // transcript this function has been writing to, so anything below reaches
    // stderr only — which is why the verdict is computed and logged FIRST.
    if leftovers.is_empty() {
        crate::plog!("agentlinux provision: --purge complete");
        let _ = std::fs::remove_file(log::log_path());
        return ExitCode::SUCCESS;
    }

    crate::plog!(
        "agentlinux provision: --purge INCOMPLETE — still present: {}. The host is \
         NOT fully torn down; re-run --purge or remove these by hand.",
        leftovers.join(", ")
    );
    let _ = std::fs::remove_file(log::log_path());
    ExitCode::FAILURE
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
    // Bounded, like every other spawn: `userdel` takes the `/etc/passwd` lock, and
    // a lock held by a stuck process makes it wait forever. `--purge` is the last
    // thing an operator runs when they want the host clean; hanging there with no
    // output is the worst place to do it.
    let _ = crate::sysio::run_bounded_argv(&["pkill", "-u", user]);
    std::thread::sleep(std::time::Duration::from_secs(1));
    let ok = crate::sysio::run_bounded_argv(&["userdel", "-r", user]).is_ok_and(|c| c == 0);
    if !ok {
        crate::plog!("agentlinux provision: userdel -r {user} failed; trying userdel -rf");
        let _ = crate::sysio::run_bounded_argv(&["userdel", "-rf", user]);
    }
}

/// `--report-only`: emit the detection report + exit
/// 0. ZERO host mutation. The report is the detected host state — the per-agent
///    decisions + the resolved distro family.
///
/// Like the Bash `detect::run_once`, this REFRESHES the detect cache
/// (`/run/agentlinux-detect.json`) as its first act: `--report-only` is the
/// sanctioned way to re-scan a host after a brownfield change (e.g. planting a
/// tool at its managed path) so a subsequent `agentlinux list`/`adopt` reads
/// current state. The cache lives on tmpfs and is NOT host state — the
/// NO-MUTATION contract covers `/etc`, `/home`, `/etc/passwd`, not `/run`.
///
/// `--report-format=json` emits the full PATH-probe agents section as
/// `{components:{agents:[...]}}` on STDOUT (the only shape any test consumes — the
/// DET-04 brownfield-detection suite); the default `text` format prints the
/// human report to stderr. The scan runs once either way and refreshes the cache.
fn report_only(user: &str, home: &str, distro: &distro::Distro, format: Option<&str>) -> ExitCode {
    if format == Some("json") {
        let report = crate::detect::scan_persist_report_json(user, home);
        // STDOUT only, nothing else — the DET-04 tests pipe the whole output to jq.
        println!(
            "{}",
            serde_json::to_string_pretty(&report)
                .unwrap_or_else(|_| String::from("{\"components\":{\"agents\":[]}}"))
        );
    } else {
        crate::detect::scan_and_write(user, home);
        emit_report(user, distro);
    }
    ExitCode::SUCCESS
}

/// `--dry-run`: print the pre-flight report + exit 0.
/// ZERO mutation. After the DECIDE phase so the report reflects every decision the
/// real install would make.
fn dry_run_report(user: &str, home: &str, distro: &distro::Distro) -> ExitCode {
    crate::plog!("agentlinux provision: [DRY-RUN] pre-flight report (no host mutation):");
    // Refresh the detect cache (tmpfs, not host state) so the pre-flight report
    // reflects current host state. See report_only for the NO-MUTATION rationale.
    crate::detect::scan_and_write(user, home);
    emit_report(user, distro);
    crate::plog!(
        "agentlinux provision: [DRY-RUN] on apply, reuse-eligible agents are adopted \
         into managed sentinels (agentlinux adopt --all)"
    );
    crate::plog!(
        "agentlinux provision: [DRY-RUN] exit 0 (no mutation; re-run without --dry-run to apply)"
    );
    ExitCode::SUCCESS
}

/// The shared detection-report body (the Rust analogue of `detect::emit_report`).
/// Prints the resolved install user + distro family + the per-agent decisions over
/// the Rust `canonical_path` map, sourced from the same in-process probe+gate the
/// install path uses. A report is read-only — NO mutation.
fn emit_report(user: &str, distro: &distro::Distro) {
    crate::plog!("agentlinux provision: detection report");
    crate::plog!("  install-user: {user}");
    crate::plog!(
        "  distro: version={} family={:?}",
        distro.version,
        distro.family
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
        crate::plog!(
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
    fn adoption_child_env_has_resolvable_path_and_home() {
        // OBS-01 regression: the adoption dispatch must supply a child PATH that
        // includes the agent's `~/.npm-global/bin` (where `agentlinux` is
        // symlinked) and a HOME. Empty env was the ENOENT root cause.
        let env = adoption_child_env("/home/agent");
        let path = env
            .iter()
            .find(|(k, _)| k == "PATH")
            .map(|(_, v)| v.as_str())
            .expect("PATH present");
        assert!(
            path.contains("/home/agent/.npm-global/bin"),
            "PATH must include the npm-global bin dir, got {path}"
        );
        assert!(env.iter().any(|(k, v)| k == "HOME" && v == "/home/agent"));
    }

    #[test]
    fn adoption_child_env_forwards_agentlinux_seams() {
        // The bats harness sets AGENTLINUX_* seams; the non-login child must
        // inherit them (the login shell would have sourced /etc/agentlinux.env).
        let _g = crate::test_support::env_guard();
        std::env::set_var("AGENTLINUX_STATE_DIR", "/tmp/fixture-state");
        let env = adoption_child_env("/home/agent");
        std::env::remove_var("AGENTLINUX_STATE_DIR");
        assert!(env
            .iter()
            .any(|(k, v)| k == "AGENTLINUX_STATE_DIR" && v == "/tmp/fixture-state"));
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
