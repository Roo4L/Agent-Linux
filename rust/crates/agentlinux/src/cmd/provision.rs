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

/// The `--user` flag check: POSIX charset AND not a reserved/system account.
/// PURE — the runtime UID<1000 adoption gate (`user_adoptable`) is a separate
/// check, see `check_user_adoptable`.
///
/// Composed from the two `recipe_env` predicates rather than re-implementing
/// them. Both used to be spelled out a second time here, with the agreement
/// resting on a comment that read "MUST mirror `validate_user_name`" — the kind
/// of invariant that holds until someone edits one copy.
fn validate_user_name(name: &str) -> bool {
    crate::recipe_env::is_valid_install_user(name)
        && !crate::recipe_env::is_reserved_user_name(name)
}

/// Resolve the install user with `--user` precedence: an explicit `--user` (when
/// valid) wins over `default_user`; otherwise `default_user` is taken as-is.
/// Returns `Err` (→ EX_USAGE) on an invalid name on EITHER path, matching the
/// Bash parse-time `validate_user_name` reject.
///
/// `default_user` is a PARAMETER, not a `resolve_install_user()` call. That
/// function reads `$AGENTLINUX_USER` and then the real, root-owned
/// `/etc/agentlinux.env`, so calling it here made this decision — and every
/// orchestrator test that reaches it — a function of the host the suite runs on.
/// On a host provisioned under a name this denylist rejects, or under any
/// harness that exports `AGENTLINUX_USER` (the bats suite does, routinely), the
/// wizard-ordering tests turned red for a reason unrelated to their fixture, and
/// `a_wizard_answer_that_is_not_a_legal_user_is_refused` went VACUOUS — it still
/// got EX_USAGE with the re-validation it exists to prove deleted. ADR-019 §3.
fn resolve_provision_user(user_flag: Option<&str>, default_user: &str) -> Result<String, ExitCode> {
    let name = match user_flag {
        Some(name) => name.to_string(),
        // M-1: the default/env-resolved user ($AGENTLINUX_USER > env-file > agent)
        // must pass the SAME reserved-name denylist the explicit --user path uses,
        // so both agree on what may become the install user.
        None => default_user.to_string(),
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

/// UX-04 wrong-shell alt-user gate (`prompt::alt_user_or_bail`). Returns the user
/// to provision under: the same name when it is absent or shell-conforming; the
/// operator-chosen alternate on a TTY; else an `Err(exit)` — 65 for a non-TTY
/// bail-with-hint or an EOF decline, 64 for 3 invalid names. On a TTY the accepted
/// alternate is a fresh user provisioned via the normal Create path.
fn resolve_wrong_shell(user: &str) -> Result<String, ExitCode> {
    resolve_wrong_shell_with(
        user,
        provision::probe::user_state(user),
        provision::wizard::find_alt_user_name().as_deref(),
        provision::wizard::stdin_is_tty(),
        &mut |s| provision::wizard::alt_user_prompt(s, &validate_user_name),
    )
}

/// [`resolve_wrong_shell`] over stated host facts and an injected prompt.
///
/// Every input this decision rests on — whether the user's shell is wrong, what
/// alternate name is free, whether there is a terminal, what the operator
/// answered — arrives as a parameter, following the shape
/// `wizard::should_prompt_from` already uses in this tree.
///
/// The outer function being a `ProvisionDeps` field made the ORCHESTRATOR
/// testable; it left this decision itself unreachable. It has five outcomes and
/// two distinct exit codes — UX-04 specifies 65 (EX_DATAERR) when the operator
/// declines or there is no terminal, and 64 (EX_USAGE) after three invalid
/// answers — and nothing asserted the difference at any level. Swapping those
/// two codes, or dropping the `--user=<suggested>` hint from the non-TTY
/// branch, would have surfaced no earlier than a QEMU run.
fn resolve_wrong_shell_with(
    user: &str,
    state: provision::probe::UserState,
    suggested: Option<&str>,
    is_tty: bool,
    prompt: &mut dyn FnMut(Option<&str>) -> provision::wizard::AltUser,
) -> Result<String, ExitCode> {
    if state != provision::probe::UserState::WrongShell {
        return Ok(user.to_string());
    }

    if !is_tty {
        eprintln!("agentlinux: existing user \"{user}\" is incompatible (wrong-shell).");
        match suggested {
            Some(s) => eprintln!("Re-run with --user={s} or fix the existing user manually."),
            None => eprintln!(
                "Re-run with --user=NAME (no auto-suggested name available — agent2..agent99 \
                 all taken) or fix the existing user manually."
            ),
        }
        return Err(ExitCode::from(EX_DATAERR));
    }

    eprintln!(
        "pre-flight: existing user \"{user}\" has a wrong shell (DET-01 requires bash + a \
         writable home)."
    );
    eprintln!("AgentLinux can create a new install user instead.");
    match suggested {
        Some(s) => eprintln!("Suggested alternate name: {s}"),
        None => eprintln!("No auto-suggested name available (agent2..agent99 all taken)."),
    }

    match prompt(suggested) {
        provision::wizard::AltUser::Chosen(name) => {
            eprintln!("[ALT-USER] accepted: {name}");
            Ok(name)
        }
        provision::wizard::AltUser::DeclinedEof => {
            eprintln!("[ALT-USER] declined — exiting 65 (EOF on prompt)");
            Err(ExitCode::from(EX_DATAERR))
        }
        provision::wizard::AltUser::Exhausted => {
            eprintln!("[ALT-USER] 3 invalid responses — exiting 64 EX_USAGE");
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
    eprintln!(
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
    ];
    for (k, v) in std::env::vars() {
        if k.starts_with("AGENTLINUX_") {
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
/// The host-touching phases `provision` composes, injected.
///
/// Same shape as `cmd/upgrade.rs`'s `UpgradeDeps`, and here for the same reason
/// one layer up: the properties that matter most in this function are ORDERINGS,
/// and none of them could fail a test while every dependency was reached
/// statically. `--purge` must run before distro detection; `--report-only` and
/// `--dry-run` must return before DECIDE mutates nothing and before the step
/// loop; the bail flush must precede `log::init` and every step; the detect
/// re-scan must follow the steps and precede adoption. Reorder any of those and
/// the suite stayed green — including the NO-MUTATION-SNAPSHOT contract, whose
/// whole content is "nothing ran before the flush".
#[derive(Clone, Copy)]
pub struct ProvisionDeps {
    pub is_tty: fn() -> bool,
    pub should_prompt_user: fn(&str, &str) -> bool,
    /// The install-user wizard (AL-50). A dep because the branch it guards reads
    /// real stdin, so a test that reached it would block on the operator's
    /// terminal rather than fail.
    pub choose_user: fn(&str) -> String,
    /// The UID<1000 adoption gate. A dep because its POSITION is the contract —
    /// it runs before `--purge` so `userdel -r` can never reach a system account
    /// — and because it reads the real passwd DB, which made the ordering tests
    /// a function of the runner's `/etc/passwd` rather than of the fixture.
    pub check_adoptable: fn(&str) -> Result<(), ExitCode>,
    /// The wrong-shell recovery path, which probes the passwd DB and can prompt.
    pub resolve_wrong_shell: fn(&str) -> Result<String, ExitCode>,
    /// The consent surface. Built here rather than inside `provision_with`,
    /// which seeded it from the ambient `stdin().is_terminal()` — so the bail
    /// ordering test prompted on a developer's real terminal and `cargo test`
    /// hung forever under a TTY while passing on CI's non-TTY runner. A verdict
    /// that depends on whether a terminal is attached is the same defect class
    /// as one that depends on the uid.
    pub make_prompter: fn() -> Box<dyn provision::wizard::Prompter>,
    pub detect_distro: fn() -> Result<distro::Distro, distro::DistroError>,
    pub probe_facts: fn(&str, &str) -> provision::remediate::HostFacts,
    pub purge: fn(&str, &str, bool) -> ExitCode,
    pub report_only: fn(&str, &str, &distro::Distro, Option<&str>) -> ExitCode,
    pub dry_run_report: fn(&str, &str, &distro::Distro) -> ExitCode,
    pub log_init: fn() -> std::path::PathBuf,
    /// Whether the transcript is actually open. A dep alongside `log_init`
    /// because it reads the same process-global `OnceLock` the fake `log_init`
    /// never sets — so which completion banner ran was a function of whether
    /// some EARLIER test in the binary had called `log::init`, making the
    /// "transcript unavailable" arm unreachable by fixture and any assertion on
    /// the banner order-dependent.
    pub log_active: fn() -> bool,
    /// The install user to fall back on when `--user` is absent, and the name
    /// the wizard offers as its default. A dep because the production
    /// implementation reads `$AGENTLINUX_USER` and the root-owned
    /// `/etc/agentlinux.env`: leaving it ambient made the host's own
    /// provisioning decide the verdict of the orchestrator's tests. See
    /// `resolve_provision_user`.
    pub default_user: fn() -> String,
    pub run_steps: fn(&ProvisionCtx) -> Result<(), ExitCode>,
    pub scan_and_write: fn(&str, &str),
    pub adopt: fn(&str, &str),
}

impl Default for ProvisionDeps {
    fn default() -> Self {
        Self {
            is_tty: provision::wizard::stdin_is_tty,
            should_prompt_user: provision::wizard::should_prompt_install_user,
            choose_user: real_choose_user,
            check_adoptable: check_user_adoptable,
            resolve_wrong_shell,
            make_prompter: || Box::new(provision::wizard::Stdio::new()),
            detect_distro: distro::detect_distro_from_env,
            probe_facts: provision::remediate::HostFacts::probe,
            purge: run_purge,
            report_only,
            dry_run_report,
            log_init: log::init,
            log_active: log::is_active,
            default_user: resolve_install_user,
            run_steps,
            scan_and_write: crate::detect::scan_and_write,
            adopt: run_agent_adoption,
        }
    }
}

/// M-3: the closing line of a successful provision. Names the transcript only
/// when it was actually persisted — if `log::init` could not open the file, a
/// banner pointing at that path sends an operator to a file that does not exist.
///
/// A pure function of the two inputs because the `false` arm was previously
/// unreachable by fixture: `log_active` reads a process-global `OnceLock` that a
/// fake `log_init` never sets, so which banner ran was a function of whether some
/// EARLIER test in the binary had called `log::init`. Splitting it this way makes
/// the seam's CONSULTATION observable in the orchestrator (the recording dep) and
/// the ARM it selects observable from literals here.
fn completion_banner(log_active: bool, log_path: &std::path::Path) -> String {
    if log_active {
        format!(
            "agentlinux-install complete (transcript: {})",
            log_path.display()
        )
    } else {
        "agentlinux-install complete (stderr-only; transcript unavailable)".to_string()
    }
}

/// The production install-user wizard, as a plain fn pointer.
///
/// Not mutation-tested — ADR-019 §5, "production wiring adapters", same as
/// `cmd/install::real_is_tty`. `choose_install_user` reads real stdin, so no
/// test drives THIS function; every test injects its own `choose_user`, which
/// means a mutant returning `String::new()` here is unobservable in-process.
///
/// The caller re-validating the answer (see `provision_with`) does NOT kill
/// these mutants — it closes a trust gap, which is worth doing on its own
/// merits, but the adapter stays unkillable. Recording that plainly rather than
/// claiming otherwise: the behaviour a wrong return would cause IS asserted, by
/// `a_wizard_answer_that_is_not_a_legal_user_is_refused`, which drives "",
/// "root" and "Bad User!" through the seam.
#[cfg_attr(test, mutants::skip)]
fn real_choose_user(default_user: &str) -> String {
    provision::wizard::choose_install_user(default_user, &validate_user_name)
}

pub fn provision(args: &ProvisionArgs) -> ExitCode {
    provision_with(args, &ProvisionDeps::default())
}

/// [`provision`] over injected phases — see [`ProvisionDeps`].
#[must_use]
pub fn provision_with(args: &ProvisionArgs, deps: &ProvisionDeps) -> ExitCode {
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
    //  (or is non-TTY), so it never prompts. A bare Enter / EOF / 3 invalid
    //  tries fall back to the default.
    let default_user = (deps.default_user)();
    let default_home = format!("/home/{default_user}");
    let install_user = if args.user.is_none()
        && !args.dry_run
        && (deps.is_tty)()
        && (deps.should_prompt_user)(&default_user, &default_home)
    {
        // Re-validate on THIS side of the seam. The production wizard validates
        // internally, but making it a dep moved that guarantee outside the
        // function: `--user` is charset- and denylist-checked here, while the
        // wizard's answer previously flowed straight into `check_adoptable`,
        // `ProvisionCtx::new` and `useradd`. An empty or reserved name would
        // reach `useradd ""` / `/home/`. Trusting a seam to uphold an invariant
        // the caller depends on is how the two username validators drifted.
        let chosen = (deps.choose_user)(&default_user);
        match resolve_provision_user(Some(&chosen), &default_user) {
            Ok(u) => u,
            Err(code) => return code,
        }
    } else {
        match resolve_provision_user(args.user.as_deref(), &default_user) {
            Ok(u) => u,
            Err(code) => return code,
        }
    };
    let install_home = format!("/home/{install_user}");

    // 2b. Adoption-safety gate, BEFORE the purge path and the install path alike.
    if let Err(exit) = (deps.check_adoptable)(&install_user) {
        return exit;
    }

    // 3. --purge (Q3). Ordered 7-step teardown — runs BEFORE the log-file tee (the
    //  Bash purge removes the log LAST) and before distro detect (it seeds the
    //  family itself, like run_purge:375). Always exits 0. require_root is the
    //  caller's contract (main::dispatch); a non-root purge fails on the mutating
    //  syscalls, which is the correct surface.
    if args.purge {
        return (deps.purge)(&install_user, &install_home, args.remove_nodejs);
    }

    // 4. Distro detect (the apt↔dnf fork point every later step branches on). Also
    //  needed by --report-only/--dry-run so the report reflects the real family.
    let distro = match (deps.detect_distro)() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("agentlinux provision: {e}");
            return ExitCode::from(EX_SOFTWARE);
        }
    };

    // 5. --report-only (Q3): emit the detection report + exit 0, ZERO mutation.
    //  Short-circuits before the DECIDE phase's per-agent gate iteration is
    //  even needed for a report — the report is the detected host state.
    if args.report_only {
        return (deps.report_only)(
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
        match (deps.resolve_wrong_shell)(&install_user) {
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
    if let Err(exit) = (deps.check_adoptable)(&install_user) {
        return exit;
    }

    // 6. DECIDE phase: probe the host for the core components (REMEDIATE-01
    //  npm-prefix chown/rebase + REMEDIATE-03 sudoers drift), overwriting the
    //  default `Create` tokens with the real verdict and aggregating a bail when
    //  a state-overwriting remediation is refused (non-TTY, no --yes). ZERO
    //  mutation here — `flush_or_exit` below short-circuits (exit 65) BEFORE the
    //  step loop, so a refused host stays byte-identical.
    let mut resolutions = Resolutions::default();
    let mut bails: Vec<provision::remediate::Bail> = Vec::new();
    let facts = (deps.probe_facts)(&install_user, &install_home);
    let mut prompter = (deps.make_prompter)();
    provision::remediate::decide_core_with(
        &install_user,
        facts,
        args.yes,
        &mut resolutions,
        &mut bails,
        prompter.as_mut(),
    );

    // 7. --dry-run: print the pre-flight report, exit 0, ZERO mutation. After the
    //  DECIDE phase so the report reflects every decision the real install would
    //  make. The per-agent decisions are computed by `emit_report` — the one
    //  place that probe+gate loop runs.
    if args.dry_run {
        return (deps.dry_run_report)(&install_user, &install_home, &distro);
    }

    // 7b. Flush aggregated bails: if any core component resolved to an
    //  unconsented state-overwrite, print the [BAIL] lines + exit 65 (EX_DATAERR)
    //  NOW — before log-init / the step loop mutates anything.
    if let Err(code) = provision::remediate::flush_bails(&bails) {
        return code;
    }

    // Past the flush, no token can still be `Bail`; narrowing here is what lets
    // every step dispatch over four cases instead of five.
    let resolutions = match resolutions.into_step() {
        Ok(r) => r,
        Err(component) => {
            eprintln!(
                "agentlinux provision: internal error — RESOLUTIONS[{component}] is still \
                 'bail' after the bail flush; refusing to mutate the host"
            );
            return ExitCode::from(EX_SOFTWARE);
        }
    };

    let ctx = ProvisionCtx::new(install_user, install_home, distro.family, resolutions);

    // 8. Open the install transcript (INST-01) — mirrors the Bash entrypoint's
    //  `install -m 0644 /dev/null "$LOG_FILE"` + tee. Best-effort: a create
    //  failure degrades to stderr-only (like the Bash pre-tee path).
    let log_path = (deps.log_init)();
    log::line(&format!(
        "agentlinux-install v{} starting",
        crate::provision::registry_cli::agentlinux_version()
    ));

    // 9. Run the fixed ordered step vec. On success emit the `agentlinux-install
    //  complete` banner (INST-01) + run best-effort agent adoption.
    match (deps.run_steps)(&ctx) {
        Ok(()) => {
            // DETECT-phase cache write (detect/agents.sh): scan the host for every
            // catalog agent + persist `/run/agentlinux-detect.json`. Runs AFTER the
            // steps (PATH wiring + Node are in place, so the login-shell probe
            // resolves agent-owned bins) and BEFORE adoption, so a subsequent
            // `agentlinux install <id>` / `adopt --all` reads real host state and
            // REUSE-03 / REMEDIATE-04 can fire. Best-effort (logs on failure).
            (deps.scan_and_write)(&ctx.install_user, &ctx.install_home);
            (deps.adopt)(&ctx.install_user, &ctx.install_home);
            log::line(&completion_banner((deps.log_active)(), &log_path));
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
/// (a tampered sentinel cannot pick scripts to run as agent). Always
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
    let state_dir = crate::sentinel::installed_dir();
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
                    let r = crate::dispatcher::as_user(
                        user,
                        &argv,
                        &env,
                        crate::dispatcher::Capture::Buffered,
                        None,
                    );
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
    eprintln!("agentlinux provision: [DRY-RUN] pre-flight report (no host mutation):");
    // Refresh the detect cache (tmpfs, not host state) so the pre-flight report
    // reflects current host state. See report_only for the NO-MUTATION rationale.
    crate::detect::scan_and_write(user, home);
    emit_report(user, distro);
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
        assert_eq!(
            resolve_provision_user(Some("claude"), "agent").unwrap(),
            "claude"
        );
    }

    #[test]
    fn explicit_user_flag_invalid_is_ex_usage() {
        assert_eq!(
            resolve_provision_user(Some("root"), "agent").unwrap_err(),
            ExitCode::from(EX_USAGE)
        );
    }

    #[test]
    fn default_path_reserved_name_is_ex_usage() {
        // M-1: the default/env-resolved user must go through the SAME denylist.
        // The default arrives as an ARGUMENT now, so this states the rule from a
        // literal. It used to set $AGENTLINUX_USER and let the function read it
        // back, which meant the test could only ever exercise the one precedence
        // rung the env var occupies — and it left the decision partly in the
        // hands of the host's /etc/agentlinux.env. `resolve_install_user`'s own
        // precedence is tested where it lives, in recipe_env.
        assert_eq!(
            resolve_provision_user(None, "root").unwrap_err(),
            ExitCode::from(EX_USAGE)
        );
        assert_eq!(
            resolve_provision_user(None, "systemd-network").unwrap_err(),
            ExitCode::from(EX_USAGE)
        );
        assert_eq!(resolve_provision_user(None, "agent").unwrap(), "agent");
    }

    #[test]
    fn adoption_gate_refuses_an_existing_system_account() {
        // H-1: an EXISTING system account (UID < 1000) is refused with EX_USAGE,
        // so `userdel -r` can never reach it and it is never granted NOPASSWD
        // sudo. `root` and `daemon` exist on every Linux host.
        assert_eq!(check_user_adoptable("root"), Err(ExitCode::from(EX_USAGE)));
        assert_eq!(
            check_user_adoptable("daemon"),
            Err(ExitCode::from(EX_USAGE))
        );
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
        let mut env_scope = crate::test_support::EnvScope::new();
        env_scope.set("AGENTLINUX_STATE_DIR", "/tmp/fixture-state");
        let env = adoption_child_env("/home/agent");
        env_scope.unset("AGENTLINUX_STATE_DIR");
        assert!(env
            .iter()
            .any(|(k, v)| k == "AGENTLINUX_STATE_DIR" && v == "/tmp/fixture-state"));
    }

    #[test]
    fn adoption_gate_allows_a_free_name() {
        // A name nobody holds is created fresh, so it passes. (The
        // regular-login-passes case is asserted from a literal in
        // provision::probe — it used to be guarded by `if self_uid >= 1000`,
        // which deleted it on the root CI runners this suite mostly runs on.)
        assert_eq!(check_user_adoptable("nonexistent-user-xyz-9042"), Ok(()));
    }

    // --- phase ordering, via the ProvisionDeps seam ---
    //
    // These are the assertions the review found missing: every phase was reached
    // statically, so `provision` could be reordered freely and 480 tests stayed
    // green. Each double records its own name; the test asserts the SEQUENCE.

    use std::sync::{Mutex, OnceLock};

    /// The recorded phase sequence.
    ///
    /// Process-global because `ProvisionDeps` holds `fn` pointers, which cannot
    /// capture (ADR-019 §1's accepted cost). That makes the `EnvScope` each of
    /// these tests binds to `_lock` LOAD-BEARING CONCURRENCY CONTROL, not just
    /// env hygiene: it is what stops two ordering tests interleaving into this
    /// one vector. Deleting the seemingly-unused binding makes them race.
    fn phase_log() -> &'static Mutex<Vec<&'static str>> {
        static LOG: OnceLock<Mutex<Vec<&'static str>>> = OnceLock::new();
        LOG.get_or_init(|| Mutex::new(Vec::new()))
    }

    fn record(phase: &'static str) {
        phase_log()
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push(phase);
    }

    fn taken() -> Vec<&'static str> {
        let mut g = phase_log().lock().unwrap_or_else(|e| e.into_inner());
        std::mem::take(&mut *g)
    }

    fn base_args() -> ProvisionArgs {
        ProvisionArgs {
            user: Some("agent".into()),
            yes: true,
            no_yes: false,
            dry_run: false,
            report_only: false,
            purge: false,
            remove_nodejs: false,
            report_format: None,
            verbose: false,
        }
    }

    fn fake_distro() -> distro::Distro {
        distro::Distro {
            family: crate::distro::Family::Debian,
            version: "24.04".into(),
        }
    }

    /// Deps whose every phase records its name and does nothing else.
    fn recording_deps() -> ProvisionDeps {
        fn is_tty() -> bool {
            record("is_tty");
            false
        }
        fn should_prompt(_u: &str, _h: &str) -> bool {
            record("should_prompt");
            false
        }
        fn detect() -> Result<distro::Distro, distro::DistroError> {
            record("detect_distro");
            Ok(fake_distro())
        }
        fn probe(_u: &str, _h: &str) -> provision::remediate::HostFacts {
            record("probe_facts");
            provision::remediate::HostFacts {
                user: provision::probe::UserState::Absent,
                npm_prefix: provision::probe::NpmPrefixState::Absent,
                sudoers: provision::probe::SudoersState::Absent,
            }
        }
        fn purge(_u: &str, _h: &str, _n: bool) -> ExitCode {
            record("purge");
            ExitCode::SUCCESS
        }
        fn report(_u: &str, _h: &str, _d: &distro::Distro, _f: Option<&str>) -> ExitCode {
            record("report_only");
            ExitCode::SUCCESS
        }
        fn dry(_u: &str, _h: &str, _d: &distro::Distro) -> ExitCode {
            record("dry_run");
            ExitCode::SUCCESS
        }
        fn log_init() -> std::path::PathBuf {
            record("log_init");
            std::path::PathBuf::from("/dev/null")
        }
        fn log_active() -> bool {
            record("log_active");
            true
        }
        fn default_user() -> String {
            record("default_user");
            "agent".to_string()
        }
        fn steps(_c: &ProvisionCtx) -> Result<(), ExitCode> {
            record("run_steps");
            Ok(())
        }
        fn scan(_u: &str, _h: &str) {
            record("scan_and_write");
        }
        fn adopt(_u: &str, _h: &str) {
            record("adopt");
        }
        fn choose_user(d: &str) -> String {
            record("choose_user");
            d.to_string()
        }
        fn adoptable(_u: &str) -> Result<(), ExitCode> {
            record("check_adoptable");
            Ok(())
        }
        fn wrong_shell(u: &str) -> Result<String, ExitCode> {
            record("resolve_wrong_shell");
            Ok(u.to_string())
        }
        /// A prompter that is NOT a terminal and would panic if consulted — so a
        /// test can never block on the operator's stdin, and a phase that starts
        /// prompting when it should not fails loudly instead of hanging.
        struct NeverPrompts;
        impl provision::wizard::Prompter for NeverPrompts {
            fn is_tty(&self) -> bool {
                false
            }
            fn confirm(&mut self, component: &str, _d: &str) -> bool {
                panic!("no prompt is owed here, but {component} asked for one");
            }
        }
        ProvisionDeps {
            is_tty,
            should_prompt_user: should_prompt,
            choose_user,
            check_adoptable: adoptable,
            resolve_wrong_shell: wrong_shell,
            make_prompter: || Box::new(NeverPrompts),
            detect_distro: detect,
            probe_facts: probe,
            purge,
            report_only: report,
            dry_run_report: dry,
            log_init,
            log_active,
            default_user,
            run_steps: steps,
            scan_and_write: scan,
            adopt,
        }
    }

    #[test]
    fn the_install_path_runs_its_phases_in_order() {
        let _lock = crate::test_support::EnvScope::new();
        let _ = taken();
        let code = provision_with(&base_args(), &recording_deps());
        assert_eq!(code, ExitCode::SUCCESS);
        assert_eq!(
            taken(),
            vec![
                "default_user",
                "check_adoptable",
                "detect_distro",
                "resolve_wrong_shell",
                "check_adoptable",
                "probe_facts",
                "log_init",
                "run_steps",
                "scan_and_write",
                "adopt",
                // The banner CONSULTS the transcript seam rather than assuming
                // it opened; which line it then prints is `completion_banner`.
                "log_active",
            ],
            "the transcript must open AFTER the bail flush, the re-scan must \
             follow the steps, and adoption must follow the re-scan"
        );
    }

    #[test]
    fn a_failing_step_stops_the_run_and_surfaces_its_exit_code() {
        // Replacing the Err arm of the step loop with SUCCESS left the whole
        // suite green: nothing asserted that a failed provisioner step is fatal,
        // or that the detect re-scan and adoption do NOT run after one.
        let _lock = crate::test_support::EnvScope::new();
        let _ = taken();
        fn failing(_c: &ProvisionCtx) -> Result<(), ExitCode> {
            record("run_steps");
            Err(ExitCode::from(70))
        }
        let mut deps = recording_deps();
        deps.run_steps = failing;

        let code = provision_with(&base_args(), &deps);

        assert_eq!(
            code,
            ExitCode::from(70),
            "the step's exit code must survive"
        );
        assert_eq!(
            taken(),
            vec![
                "default_user",
                "check_adoptable",
                "detect_distro",
                "resolve_wrong_shell",
                "check_adoptable",
                "probe_facts",
                "log_init",
                "run_steps",
            ],
            "no re-scan and no adoption may follow a failed step"
        );
    }

    #[test]
    fn the_install_user_wizard_runs_only_when_no_user_was_given_on_a_tty() {
        // The AL-50 branch: deleting the whole prompt condition left 351 tests
        // green, because every ordering fixture passed --user. `choose_user` is
        // a dep precisely so this can be asserted without real stdin.
        let _lock = crate::test_support::EnvScope::new();

        fn yes_tty() -> bool {
            record("is_tty");
            true
        }
        fn wants_prompt(_u: &str, _h: &str) -> bool {
            record("should_prompt");
            true
        }

        // --user given: the wizard must NOT run.
        let _ = taken();
        assert_eq!(
            provision_with(&base_args(), &recording_deps()),
            ExitCode::SUCCESS
        );
        assert!(!taken().contains(&"choose_user"));

        // No --user, a TTY, and a host that warrants prompting: it must.
        let _ = taken();
        let mut deps = recording_deps();
        deps.is_tty = yes_tty;
        deps.should_prompt_user = wants_prompt;
        let mut args = base_args();
        args.user = None;
        assert_eq!(provision_with(&args, &deps), ExitCode::SUCCESS);
        let seq = taken();
        assert!(seq.contains(&"choose_user"), "seq={seq:?}");
        assert!(
            seq.iter().position(|p| *p == "choose_user")
                < seq.iter().position(|p| *p == "detect_distro"),
            "the user must be settled before anything else, seq={seq:?}"
        );
    }

    #[test]
    fn a_wizard_answer_that_is_not_a_legal_user_is_refused() {
        // The seam moved the wizard's internal validation outside this function,
        // so the caller re-checks. Without that, an empty or reserved name flows
        // into check_adoptable, ProvisionCtx and `useradd ""`.
        let _lock = crate::test_support::EnvScope::new();
        for bad in ["", "root", "Bad User!"] {
            let _ = taken();
            fn empty(_d: &str) -> String {
                record("choose_user");
                String::new()
            }
            fn reserved(_d: &str) -> String {
                record("choose_user");
                "root".to_string()
            }
            fn malformed(_d: &str) -> String {
                record("choose_user");
                "Bad User!".to_string()
            }
            fn yes_tty() -> bool {
                true
            }
            fn wants_prompt(_u: &str, _h: &str) -> bool {
                true
            }
            let mut deps = recording_deps();
            deps.is_tty = yes_tty;
            deps.should_prompt_user = wants_prompt;
            deps.choose_user = match bad {
                "" => empty,
                "root" => reserved,
                _ => malformed,
            };
            let mut args = base_args();
            args.user = None;

            let code = provision_with(&args, &deps);

            assert_eq!(
                code,
                ExitCode::from(EX_USAGE),
                "wizard answered {bad:?}; it must be refused, not provisioned"
            );
            let seq = taken();
            assert!(
                !seq.contains(&"detect_distro"),
                "nothing may proceed on an illegal user, seq={seq:?}"
            );
        }
    }

    #[test]
    fn the_completion_banner_names_the_transcript_only_when_it_exists() {
        // M-3. The `false` arm shipped unexecuted: `log_active` reads a
        // process-global OnceLock that the fixture's fake `log_init` never sets,
        // so this line's behaviour was a function of test ORDER. As a pure
        // function of the two inputs it is decidable, and the orchestrator's
        // phase log proves the seam is consulted at all.
        let p = std::path::Path::new("/var/log/agentlinux-install.log");
        assert_eq!(
            completion_banner(true, p),
            "agentlinux-install complete (transcript: /var/log/agentlinux-install.log)"
        );
        let degraded = completion_banner(false, p);
        assert_eq!(
            degraded,
            "agentlinux-install complete (stderr-only; transcript unavailable)"
        );
        // The point of the arm: an operator must not be sent to a file that was
        // never written.
        assert!(
            !degraded.contains("agentlinux-install.log"),
            "the degraded banner must not name a path that does not exist"
        );
    }

    #[test]
    fn purge_returns_before_anything_else_is_touched() {
        // --purge is a teardown: it must not detect the distro, probe, open a
        // transcript or run a step.
        let _lock = crate::test_support::EnvScope::new();
        let _ = taken();
        let mut args = base_args();
        args.purge = true;
        assert_eq!(provision_with(&args, &recording_deps()), ExitCode::SUCCESS);
        // The adoption gate MUST precede the teardown: `userdel -r` on a system
        // account is the loss it exists to prevent, and the denylist alone does
        // not cover every system user (syslog and dhcpcd pass it).
        assert_eq!(taken(), vec!["default_user", "check_adoptable", "purge"]);
    }

    #[test]
    fn report_only_returns_before_deciding_or_mutating() {
        let _lock = crate::test_support::EnvScope::new();
        let _ = taken();
        let mut args = base_args();
        args.report_only = true;
        assert_eq!(provision_with(&args, &recording_deps()), ExitCode::SUCCESS);
        assert_eq!(
            taken(),
            vec![
                "default_user",
                "check_adoptable",
                "detect_distro",
                "report_only"
            ]
        );
    }

    #[test]
    fn dry_run_decides_but_never_opens_a_transcript_or_runs_a_step() {
        // UX-01: --dry-run reports every decision the real run would make, so it
        // MUST reach the DECIDE phase — and must stop there.
        let _lock = crate::test_support::EnvScope::new();
        let _ = taken();
        let mut args = base_args();
        args.dry_run = true;
        args.yes = false;
        assert_eq!(provision_with(&args, &recording_deps()), ExitCode::SUCCESS);
        assert_eq!(
            taken(),
            vec![
                "default_user",
                "check_adoptable",
                "detect_distro",
                // --dry-run skips the wrong-shell RECOVERY (it would prompt) but
                // still re-gates adoption on the resolved user.
                "check_adoptable",
                "probe_facts",
                "dry_run"
            ]
        );
    }

    #[test]
    fn a_bail_stops_before_the_transcript_and_before_any_step() {
        // The NO-MUTATION-SNAPSHOT contract, asserted as an ordering rather than
        // in isolation: an unconsented state-overwrite must exit 65 with NOTHING
        // after the probe having run.
        let _lock = crate::test_support::EnvScope::new();
        let _ = taken();
        fn drifted(_u: &str, _h: &str) -> provision::remediate::HostFacts {
            record("probe_facts");
            provision::remediate::HostFacts {
                user: provision::probe::UserState::Absent,
                npm_prefix: provision::probe::NpmPrefixState::Absent,
                // Drifted + no consent + no TTY = bail.
                sudoers: provision::probe::SudoersState::Drifted,
            }
        }
        let mut deps = recording_deps();
        deps.probe_facts = drifted;
        let mut args = base_args();
        args.yes = false;

        let code = provision_with(&args, &deps);

        assert_eq!(
            code,
            ExitCode::from(65),
            "an unconsented overwrite exits 65"
        );
        assert_eq!(
            taken(),
            vec![
                "default_user",
                "check_adoptable",
                "detect_distro",
                "resolve_wrong_shell",
                "check_adoptable",
                "probe_facts"
            ],
            "no transcript, no step, no scan may run after a bail"
        );
    }

    // --- resolve_wrong_shell: five outcomes, two exit codes, all from literals.

    use provision::probe::UserState;
    use provision::wizard::AltUser;

    fn never_prompts(_s: Option<&str>) -> AltUser {
        panic!("no prompt is owed when the shell is fine or there is no terminal");
    }

    #[test]
    fn a_conforming_user_is_returned_untouched_and_never_prompts() {
        for state in [
            UserState::Absent,
            UserState::Conforming,
            UserState::HomeNotWritable,
        ] {
            let got = resolve_wrong_shell_with("agent", state, Some("agent2"), true, &mut |s| {
                never_prompts(s)
            });
            assert_eq!(got.unwrap(), "agent", "state={state:?}");
        }
    }

    #[test]
    fn a_wrong_shell_without_a_terminal_exits_65_and_never_prompts() {
        // UX-04: no TTY means no way to ask, so it must bail — and bail with
        // EX_DATAERR (incompatible host state), NOT EX_USAGE.
        let got = resolve_wrong_shell_with(
            "agent",
            UserState::WrongShell,
            Some("agent2"),
            false,
            &mut |s| never_prompts(s),
        );
        assert_eq!(got.unwrap_err(), ExitCode::from(EX_DATAERR));

        // …and the same with no suggestion available.
        let got = resolve_wrong_shell_with("agent", UserState::WrongShell, None, false, &mut |s| {
            never_prompts(s)
        });
        assert_eq!(got.unwrap_err(), ExitCode::from(EX_DATAERR));
    }

    #[test]
    fn an_accepted_alternate_name_becomes_the_install_user() {
        let got = resolve_wrong_shell_with(
            "agent",
            UserState::WrongShell,
            Some("agent2"),
            true,
            &mut |suggested| {
                // The prompt is offered the suggestion the caller computed.
                assert_eq!(suggested, Some("agent2"));
                AltUser::Chosen("agent2".to_string())
            },
        );
        assert_eq!(got.unwrap(), "agent2");
    }

    #[test]
    fn declining_exits_65_but_three_invalid_answers_exit_64() {
        // The distinction UX-04 specifies, and the one nothing asserted: EOF is
        // "incompatible host state" (65); an operator who cannot type a legal
        // name three times is a usage error (64). Swapping them would have gone
        // unnoticed until a QEMU run.
        let declined = resolve_wrong_shell_with(
            "agent",
            UserState::WrongShell,
            Some("agent2"),
            true,
            &mut |_| AltUser::DeclinedEof,
        );
        assert_eq!(declined.unwrap_err(), ExitCode::from(EX_DATAERR));

        let exhausted = resolve_wrong_shell_with(
            "agent",
            UserState::WrongShell,
            Some("agent2"),
            true,
            &mut |_| AltUser::Exhausted,
        );
        assert_eq!(exhausted.unwrap_err(), ExitCode::from(EX_USAGE));

        assert_ne!(
            ExitCode::from(EX_DATAERR),
            ExitCode::from(EX_USAGE),
            "the two codes must differ, or the assertions above are vacuous"
        );
    }
}
