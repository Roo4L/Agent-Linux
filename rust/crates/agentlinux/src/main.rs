//! AgentLinux CLI binary — a thin adapter over `agentlinux-core`.
//!
//! Argument parsing lives in `cli.rs` (clap derive), the recipe env contract in
//! `recipe_env.rs`, and the subprocess dispatcher in `dispatcher.rs`. This file
//! is the routing layer: parse, guard, dispatch to a `cmd::*` verb.
//!
//! The pure/adapter split: env-var reads and the canonical-path map live HERE,
//! at the I/O boundary; the decisions they feed live in `agentlinux_core`, which
//! stays free of `std::env`, `std::fs` and `std::process`.

mod cache;
mod catalog;
mod cli;
mod cmd;
mod detect;
mod dispatcher;
mod distro;
mod guard;
mod npm;
mod pkg;
mod probe;
mod provision;
mod recipe_env;
mod rewire;
mod sentinel;
mod statelock;
mod sysio;

use clap::Parser;
use cli::{Cli, Command};
use std::process::ExitCode;

/// GSD's deployed-system VERSION path — a second valid canonical presence for
/// `gsd` (npx form).
pub(crate) const GSD_SYSTEM_PATH: &str = "/home/agent/.claude/gsd-core/VERSION";

/// The catalog ids that HAVE a canonical-path entry — the authoritative
/// per-agent enumerator (PROV-02). The provisioner's detection report iterates
/// this list in-process.
///
/// MUST stay in sync with [`canonical_path`]'s match arms: this list answers
/// "which ids have one", that function answers "what is it". A mismatch means an
/// agent is either enumerated with no path or has a path nobody probes.
pub(crate) const CANONICAL_IDS: &[&str] = &["claude-code", "gsd", "playwright-cli"];

/// Canonical binary path for a catalog id, or `None` for an unknown id.
///
/// This map is the single authoritative source: nothing outside this file
/// defines where a managed agent's binary belongs. Keep the arms in sync with
/// [`CANONICAL_IDS`].
pub(crate) fn canonical_path(id: &str) -> Option<&'static str> {
    match id {
        "claude-code" => Some("/home/agent/.local/bin/claude"),
        "gsd" => Some("/home/agent/.npm-global/bin/gsd-core"),
        "playwright-cli" => Some("/home/agent/.npm-global/bin/playwright-cli"),
        _ => None,
    }
}

/// Bundle the three host paths the pure detect gates decide against.
///
/// The one place `GSD_SYSTEM_PATH` is threaded into a gate call, so a verb never
/// has to name it — and, because `HostPaths` has named fields, a verb cannot
/// accidentally pass the agent home where the gsd path belongs.
pub(crate) fn host_paths<'a>(
    canonical: Option<&'a str>,
    agent_home: &'a str,
) -> agentlinux_core::detect_gates::HostPaths<'a> {
    agentlinux_core::detect_gates::HostPaths {
        canonical,
        gsd_system_path: GSD_SYSTEM_PATH,
        agent_home,
    }
}

/// EX_USAGE (sysexits.h) — the exit code a clap parse failure maps to.
const EX_USAGE: u8 = 64;

/// The exit code a clap parse outcome deserves.
///
/// `--version`/`--help` arrive as DisplayVersion/DisplayHelp "errors" that clap
/// prints to stdout; those exit 0. A genuine usage error prints to stderr and
/// exits EX_USAGE (64), mirroring Commander.
///
/// Extracted from `main` because it is the only decision `main` makes, and
/// inside `main` it was unreachable from a unit test: `Cli::try_parse()` reads
/// the real process argv. `replace main -> ExitCode with Default::default()`
/// survived, which is `agentlinux --nonsense` exiting 0.
fn parse_error_exit(kind: clap::error::ErrorKind) -> ExitCode {
    use clap::error::ErrorKind;
    match kind {
        ErrorKind::DisplayVersion | ErrorKind::DisplayHelp => ExitCode::SUCCESS,
        _ => ExitCode::from(EX_USAGE),
    }
}

/// Not mutation-tested: the process entrypoint (ADR-019 §5). It reads the real
/// argv and writes the real streams; its one decision is
/// [`parse_error_exit`] and its routing is [`dispatch_with`], both asserted
/// directly.
#[cfg_attr(test, mutants::skip)]
fn main() -> ExitCode {
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(e) => {
            let code = parse_error_exit(e.kind());
            // clap writes version/help to stdout, usage errors to stderr.
            let _ = e.print();
            return code;
        }
    };

    dispatch(cli.command)
}

/// Agent home for the presence/managed-dir heuristics — `$AGENTLINUX_AGENT_HOME`
/// else `/home/agent` (mirrors `agentHome()`, detect.ts:42-44). The env read is
/// the I/O boundary; the pure gates receive the resolved string.
///
/// Consumed by the verb adapters (`cmd/list.rs` here; `cmd/{pin,adopt}.rs`
/// in Task 3).
pub(crate) fn agent_home() -> String {
    std::env::var("AGENTLINUX_AGENT_HOME").unwrap_or_else(|_| "/home/agent".to_string())
}

/// The name clap gives each verb — used for the CLI-05 guard diagnostic
/// (`actionCommand.name()`, index.ts:35).
fn verb_name(command: &Command) -> &'static str {
    match command {
        Command::List(_) => "list",
        Command::Install(_) => "install",
        Command::Adopt(_) => "adopt",
        Command::Remove(_) => "remove",
        Command::Upgrade(_) => "upgrade",
        Command::Pin(_) => "pin",
        // `provision` never reaches the CLI-05 `guard_agent_user` (it is routed
        // through `require_root` instead); a name is provided for
        // completeness/exhaustiveness.
        Command::Provision(_) => "provision",
    }
}

/// Route a parsed verb to its handler, against the real guards and verb bodies.
///
/// Not mutation-tested: a production wiring adapter (ADR-019 §5). The routing it
/// hands to — which guard each verb sits behind, and that a refusing guard stops
/// the verb — is asserted through [`dispatch_with`].
#[cfg_attr(test, mutants::skip)]
fn dispatch(command: Command) -> ExitCode {
    dispatch_with(command, DispatchDeps::default())
}

/// The four things [`dispatch_with`] does that are not routing: the two guards,
/// and running the verb behind each of them.
///
/// A seam because the routing contract is a SECURITY contract — which guard each
/// verb sits behind, and that a refusing guard stops the verb running — and none
/// of it was assertable. Both guards read the real EUID and passwd DB, and every
/// verb body performs real I/O, so a test of `dispatch` was a test of the
/// machine it ran on. `replace != with ==` survived on both guard checks: inverted,
/// a refusing guard runs the verb anyway and a passing one returns early. That is
/// `sudo agentlinux provision` accepted from a non-root invoker, and the CLI-05
/// invoker guard bypassed for all six user-facing verbs, with the suite green.
#[derive(Clone, Copy)]
struct DispatchDeps {
    require_root: fn() -> ExitCode,
    guard_agent_user: fn(&str) -> ExitCode,
    run_provision: fn(&cli::ProvisionArgs) -> ExitCode,
    run_verb: fn(Command) -> ExitCode,
}

impl Default for DispatchDeps {
    fn default() -> Self {
        Self {
            // Production passes `None` → resolve the real EUID / passwd entry.
            require_root: || guard::require_root(None),
            guard_agent_user: |verb| guard::guard_agent_user(verb, None),
            run_provision: cmd::provision::provision,
            run_verb: run_guarded_verb,
        }
    }
}

/// Route a parsed verb to its handler.
///
/// CLI-05: the guard runs BEFORE any verb — including the read-only `list` — so
/// a non-install-user invoker fails fast (exit 64) before any command body runs.
/// `guard_agent_user` returns `SUCCESS` on a match; on a mismatch it prints the
/// diagnostic and returns `ExitCode::from(64)`, which we propagate immediately.
///
/// All seven verbs are wired. `provision` takes the root-guarded arm below; the
/// other six run behind the CLI-05 invoker guard.
fn dispatch_with(command: Command, deps: DispatchDeps) -> ExitCode {
    // `provision` is the PRE-Node provisioner entrypoint: it runs privileged
    // systems I/O BEFORE any agent user exists, so it dispatches through
    // `require_root` (EUID==0), NOT the CLI-05 `guard_agent_user` (which resolves
    // the invoker's passwd entry and REJECTS root — the provisioner's REQUIRED
    // invoker). Routing it through the wrong guard would make
    // every real `sudo agentlinux provision` exit 64. Handled BEFORE the blanket
    // guard so the six user-facing verbs keep their CLI-05 guard.
    if let Command::Provision(args) = &command {
        let guard = (deps.require_root)();
        if guard != ExitCode::SUCCESS {
            return guard;
        }
        let Some(_lock) = hold_state_lock(&command) else {
            return ExitCode::from(EX_TEMPFAIL);
        };
        return (deps.run_provision)(args);
    }

    // The CLI-05 guard runs for every OTHER verb.
    let guard = (deps.guard_agent_user)(verb_name(&command));
    if guard != ExitCode::SUCCESS {
        return guard;
    }

    // Serialize the mutating verbs against each other (see `statelock`). Held for
    // the whole verb: binding it to `_lock` rather than `_` matters, because `_`
    // drops immediately and would release the lock before the work starts.
    let Some(_lock) = hold_state_lock(&command) else {
        return ExitCode::from(EX_TEMPFAIL);
    };

    (deps.run_verb)(command)
}

/// The six user-facing verb bodies, reached only once the CLI-05 guard passed.
/// Not mutation-tested: a production wiring adapter (ADR-019 §5) — every arm is
/// one call into a `cmd::*` module that owns its own tests, and the routing
/// decision that precedes it is asserted through [`dispatch_with`].
#[cfg_attr(test, mutants::skip)]
fn run_guarded_verb(command: Command) -> ExitCode {
    match command {
        Command::List(args) => cmd::list::list(&args),
        Command::Adopt(args) => cmd::adopt::adopt(args.name.as_deref(), &args),
        Command::Pin(args) => cmd::pin::pin(&args.spec),
        Command::Install(args) => cmd::install::install(&args.name.clone(), &args),
        Command::Remove(args) => cmd::remove::remove(&args.name.clone(), &args),
        Command::Upgrade(args) => cmd::upgrade::upgrade(&args),
        // Provision is handled above (require_root arm); unreachable here.
        Command::Provision(_) => unreachable!("provision handled via require_root arm"),
    }
}

/// `EX_TEMPFAIL` — "try again later", the sysexits code for a contended lock.
/// Distinct from the usage/data/software codes so a wrapper script can retry on
/// this one alone.
pub(crate) const EX_TEMPFAIL: u8 = 75;

/// Take the host state lock for a mutating verb, or `None` after printing why.
///
/// Three kinds of invocation are deliberately exempt:
///  - `list` only reads, so serializing it would block the one command an
///    operator runs to find out what the busy run is doing.
///  - `--dry-run` / `--report-only` promise to leave the host byte-identical.
///    Creating the lock file is a write, so taking it would break the very
///    contract those modes exist to offer — and a preview refused while an
///    install runs is the same operability problem as a blocked `list`.
///  - `install --dry-run`, likewise.
fn hold_state_lock(command: &Command) -> Option<statelock::HostLock> {
    let needs_lock = match command {
        Command::List(_) => false,
        Command::Provision(a) => !a.dry_run && !a.report_only,
        Command::Install(a) => !a.dry_run,
        // Bare `upgrade` is a report; only the flags below install anything.
        Command::Upgrade(a) => a.reset_all_curated || a.respect_overrides || a.all_latest,
        Command::Adopt(_) | Command::Pin(_) | Command::Remove(_) => true,
    };
    if !needs_lock {
        return Some(statelock::HostLock::NotRequired);
    }
    match statelock::acquire(verb_name(command)) {
        Ok(lock) => Some(lock),
        Err(e) => {
            crate::plog!("agentlinux: {e}");
            None
        }
    }
}

#[cfg(test)]
pub(crate) mod test_support {
    use std::ffi::OsStr;
    use std::sync::{Mutex, MutexGuard};
    /// Single process-wide lock serializing every test that mutates the
    /// global AGENTLINUX_* env vars. A per-module lock cannot serialize
    /// cross-module tests (they share one process), causing env races.
    /// Poison-tolerant: a panic in one env test must not cascade-poison
    /// the lock for the rest.
    pub static ENV_LOCK: Mutex<()> = Mutex::new(());

    /// Take the env lock and restore, on drop, every variable this scope
    /// touched.
    ///
    /// Env vars are process-global, so a test that sets one and clears it AFTER
    /// its assertions leaks that variable into whatever runs next the moment an
    /// assertion fails — turning one red test into a cascade whose cause is two
    /// modules away. `EnvScope` is the only sanctioned way to mutate the
    /// environment in a test: it releases the lock and puts every variable back
    /// (including "back to unset") on the unwind path too.
    #[must_use]
    pub struct EnvScope {
        _lock: MutexGuard<'static, ()>,
        saved: Vec<(String, Option<String>)>,
    }

    impl EnvScope {
        pub fn new() -> Self {
            Self {
                _lock: ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner()),
                saved: Vec::new(),
            }
        }

        /// Set `key` for the lifetime of this scope.
        pub fn set(&mut self, key: &str, value: impl AsRef<OsStr>) -> &mut Self {
            self.remember(key);
            std::env::set_var(key, value);
            self
        }

        /// Unset `key` for the lifetime of this scope.
        pub fn unset(&mut self, key: &str) -> &mut Self {
            self.remember(key);
            std::env::remove_var(key);
            self
        }

        fn remember(&mut self, key: &str) {
            if !self.saved.iter().any(|(k, _)| k == key) {
                self.saved.push((key.to_string(), std::env::var(key).ok()));
            }
        }
    }

    impl Drop for EnvScope {
        fn drop(&mut self) {
            for (key, prior) in self.saved.drain(..) {
                match prior {
                    Some(v) => std::env::set_var(&key, v),
                    None => std::env::remove_var(&key),
                }
            }
        }
    }
}

#[cfg(test)]
mod canonical_map_tests {
    use super::*;

    // main.rs carried ZERO tests while owning the map the whole DECIDE phase
    // enumerates (PROV-02: "the Rust map is the single authoritative per-agent
    // enumerator"). The bats file that claimed to cover it grepped for a string
    // across three files and would have passed on a comment.

    #[test]
    fn canonical_path_map_pins_each_id() {
        assert_eq!(
            canonical_path("claude-code"),
            Some("/home/agent/.local/bin/claude")
        );
        assert_eq!(
            canonical_path("gsd"),
            Some("/home/agent/.npm-global/bin/gsd-core")
        );
        assert_eq!(
            canonical_path("playwright-cli"),
            Some("/home/agent/.npm-global/bin/playwright-cli")
        );
    }

    #[test]
    fn an_unknown_id_has_no_canonical_path() {
        // Not a panic and not a guess: a future catalog id with no map entry
        // falls through to Create rather than mis-REUSEing something.
        assert_eq!(canonical_path("some-future-agent"), None);
        assert_eq!(canonical_path(""), None);
    }

    #[test]
    fn every_canonical_id_has_a_map_entry() {
        // CANONICAL_IDS is what the provisioner iterates; an id listed there
        // with no path would silently decide Create for an agent that IS
        // installed.
        for id in CANONICAL_IDS {
            assert!(
                canonical_path(id).is_some(),
                "CANONICAL_IDS lists {id} with no canonical_path entry"
            );
        }
    }

    #[test]
    fn verb_names_match_the_cli_subcommands() {
        // The name reaches the user inside the CLI-05 diagnostic ("try: sudo -u
        // agent -H agentlinux <verb>"), so a wrong one prints an uncopyable hint.
        // Parsed through clap so the name is the one the CLI actually accepts.
        for (argv, expected) in [
            (vec!["agentlinux", "list"], "list"),
            (vec!["agentlinux", "install", "gsd"], "install"),
            (vec!["agentlinux", "remove", "gsd"], "remove"),
            (vec!["agentlinux", "upgrade"], "upgrade"),
            (vec!["agentlinux", "adopt"], "adopt"),
            (vec!["agentlinux", "pin", "gsd=latest"], "pin"),
            (vec!["agentlinux", "provision"], "provision"),
        ] {
            let cli = Cli::try_parse_from(&argv).expect("argv parses");
            assert_eq!(verb_name(&cli.command), expected, "argv={argv:?}");
        }
    }
}

#[cfg(test)]
mod dispatch_tests {
    use super::*;
    use std::cell::RefCell;

    // Which seam ran, in order. A thread_local rather than a static: cargo runs
    // each test on its own thread, so the log is per-test without a lock, and a
    // fn pointer cannot capture a local.
    thread_local! {
        static CALLS: RefCell<Vec<&'static str>> = const { RefCell::new(Vec::new()) };
    }

    fn note(what: &'static str) {
        CALLS.with(|c| c.borrow_mut().push(what));
    }
    fn calls() -> Vec<&'static str> {
        CALLS.with(|c| c.borrow().clone())
    }

    const REFUSED: u8 = 64;

    fn root_ok() -> ExitCode {
        note("require_root");
        ExitCode::SUCCESS
    }
    fn root_refuses() -> ExitCode {
        note("require_root");
        ExitCode::from(REFUSED)
    }
    fn user_ok(verb: &str) -> ExitCode {
        note("guard_agent_user");
        // The verb name the guard is given reaches its diagnostic; assert it is
        // the real one, not a placeholder.
        assert_eq!(verb, "list", "guard must receive the parsed verb name");
        ExitCode::SUCCESS
    }
    fn user_refuses(_verb: &str) -> ExitCode {
        note("guard_agent_user");
        ExitCode::from(REFUSED)
    }
    fn provision_ran(_args: &cli::ProvisionArgs) -> ExitCode {
        note("provision");
        ExitCode::SUCCESS
    }
    fn verb_ran(_command: Command) -> ExitCode {
        note("verb");
        ExitCode::SUCCESS
    }

    fn parse(argv: &[&str]) -> Command {
        Cli::try_parse_from(argv).expect("argv parses").command
    }

    fn deps() -> DispatchDeps {
        DispatchDeps {
            require_root: root_ok,
            guard_agent_user: user_ok,
            run_provision: provision_ran,
            run_verb: verb_ran,
        }
    }

    /// `provision` is routed through the ROOT guard and never through CLI-05.
    /// Routing it through `guard_agent_user` — which rejects root — would make
    /// every real `sudo agentlinux provision` exit 64.
    #[test]
    fn provision_goes_through_the_root_guard_only() {
        let code = dispatch_with(parse(&["agentlinux", "provision"]), deps());
        assert_eq!(
            format!("{code:?}"),
            format!("{:?}", ExitCode::SUCCESS),
            "a passing root guard must run provision"
        );
        assert_eq!(calls(), vec!["require_root", "provision"]);
    }

    /// The mutation this exists for: `replace != with ==` on the root guard
    /// check. Inverted, a REFUSING guard falls through and provision runs
    /// anyway — an unprivileged invoker driving the privileged provisioner.
    #[test]
    fn a_refusing_root_guard_stops_provision_running() {
        let mut d = deps();
        d.require_root = root_refuses;
        let code = dispatch_with(parse(&["agentlinux", "provision"]), d);
        assert_eq!(
            format!("{code:?}"),
            format!("{:?}", ExitCode::from(REFUSED)),
            "the guard's refusal must be the exit code"
        );
        assert_eq!(
            calls(),
            vec!["require_root"],
            "provision must NOT run behind a refused guard"
        );
    }

    /// Every other verb sits behind the CLI-05 invoker guard, and never touches
    /// the root guard.
    #[test]
    fn a_user_verb_goes_through_the_cli05_guard_only() {
        let code = dispatch_with(parse(&["agentlinux", "list"]), deps());
        assert_eq!(format!("{code:?}"), format!("{:?}", ExitCode::SUCCESS));
        assert_eq!(calls(), vec!["guard_agent_user", "verb"]);
    }

    /// The same mutation on the CLI-05 check. Inverted, a non-install-user
    /// invoker runs the verb body — the guard CLI-05 exists to enforce, gone.
    #[test]
    fn a_refusing_cli05_guard_stops_the_verb_running() {
        let mut d = deps();
        d.guard_agent_user = user_refuses;
        let code = dispatch_with(parse(&["agentlinux", "list"]), d);
        assert_eq!(
            format!("{code:?}"),
            format!("{:?}", ExitCode::from(REFUSED)),
            "the guard's refusal must be the exit code"
        );
        assert_eq!(
            calls(),
            vec!["guard_agent_user"],
            "the verb must NOT run behind a refused guard"
        );
    }
}

#[cfg(test)]
mod parse_error_tests {
    use super::*;
    use clap::error::ErrorKind;

    /// `--version` and `--help` are successes wearing an error's clothes; every
    /// other parse failure is EX_USAGE. Driven through the REAL parser rather
    /// than by naming the enum variants, so a clap upgrade that reclassifies
    /// either one fails here instead of silently changing `agentlinux --help`'s
    /// exit code.
    #[test]
    fn version_and_help_exit_zero_and_a_usage_error_exits_64() {
        let cases: &[(&[&str], ExitCode, &str)] = &[
            (&["agentlinux", "--version"], ExitCode::SUCCESS, "--version"),
            (&["agentlinux", "--help"], ExitCode::SUCCESS, "--help"),
            (
                &["agentlinux", "--nonsense"],
                ExitCode::from(EX_USAGE),
                "unknown flag",
            ),
            (
                &["agentlinux", "nosuchverb"],
                ExitCode::from(EX_USAGE),
                "unknown subcommand",
            ),
        ];
        for (argv, want, what) in cases {
            let err = Cli::try_parse_from(*argv).expect_err("must not parse to a command");
            assert_eq!(
                format!("{:?}", parse_error_exit(err.kind())),
                format!("{want:?}"),
                "{what} ({argv:?}) mapped to the wrong exit code; clap kind={:?}",
                err.kind()
            );
        }
    }

    /// The EX_USAGE constant is the sysexits value the bats contract greps for.
    /// Pinned so a stray edit to it is a test failure rather than a silent
    /// change to every usage error the CLI emits.
    #[test]
    fn usage_errors_use_the_sysexits_value() {
        assert_eq!(EX_USAGE, 64);
        assert_eq!(
            format!("{:?}", parse_error_exit(ErrorKind::InvalidValue)),
            format!("{:?}", ExitCode::from(64u8))
        );
    }
}
