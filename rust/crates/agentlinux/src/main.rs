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

fn main() -> ExitCode {
    // Everything else parses via clap. `--version`/`--help` are DisplayVersion/
    // DisplayHelp "errors" that clap prints to stdout and we exit 0 on; a genuine
    // usage error prints to stderr and exits EX_USAGE (64), mirroring Commander.
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(e) => {
            let clean_exit = matches!(
                e.kind(),
                clap::error::ErrorKind::DisplayVersion | clap::error::ErrorKind::DisplayHelp
            );
            // clap writes version/help to stdout, usage errors to stderr.
            let _ = e.print();
            return if clean_exit {
                ExitCode::SUCCESS
            } else {
                ExitCode::from(EX_USAGE)
            };
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

/// Route a parsed verb to its handler.
///
/// CLI-05: the guard runs BEFORE any verb — including the
/// read-only `list` — so a non-install-user invoker fails fast (exit 64) before
/// any command body runs. `guard_agent_user` returns `SUCCESS` on a match; on a
/// mismatch it prints the diagnostic and returns `ExitCode::from(64)`, which we
/// propagate immediately.
///
/// All seven verbs are wired. `provision` takes the root-guarded arm below;
/// the other six run behind the CLI-05 invoker guard.
/// `EX_TEMPFAIL` — "try again later", the sysexits code for a contended lock.
/// Distinct from the usage/data/software codes so a wrapper script can retry on
/// this one alone.
const EX_TEMPFAIL: u8 = 75;

/// Take the host state lock for a mutating verb, or `None` after printing why.
///
/// `list` is deliberately absent: it only reads, so serializing it would block
/// the one command an operator runs to find out what the busy run is doing.
fn hold_state_lock(command: &Command) -> Option<Option<statelock::HostLock>> {
    let (needs_lock, wait) = match command {
        Command::List(_) => (false, false),
        Command::Provision(a) => (true, a.wait_lock),
        Command::Adopt(a) => (true, a.wait_lock),
        Command::Pin(a) => (true, a.wait_lock),
        Command::Install(a) => (true, a.wait_lock),
        Command::Remove(a) => (true, a.wait_lock),
        Command::Upgrade(a) => (true, a.wait_lock),
    };
    if !needs_lock {
        return Some(None);
    }
    let on_contention = if wait {
        statelock::OnContention::Wait
    } else {
        statelock::OnContention::Fail
    };
    match statelock::acquire(verb_name(command), on_contention) {
        Ok(lock) => Some(Some(lock)),
        Err(e) => {
            crate::plog!("agentlinux: {e}");
            None
        }
    }
}

fn dispatch(command: Command) -> ExitCode {
    // `provision` is the PRE-Node provisioner entrypoint: it runs privileged
    // systems I/O BEFORE any agent user exists, so it dispatches through
    // `require_root` (EUID==0), NOT the CLI-05 `guard_agent_user` (which resolves
    // the invoker's passwd entry and REJECTS root — the provisioner's REQUIRED
    // invoker). Routing it through the wrong guard would make
    // every real `sudo agentlinux provision` exit 64. Handled BEFORE the blanket
    // guard so the six user-facing verbs keep their CLI-05 guard.
    if let Command::Provision(args) = &command {
        let guard = guard::require_root(None);
        if guard != ExitCode::SUCCESS {
            return guard;
        }
        let Some(_lock) = hold_state_lock(&command) else {
            return ExitCode::from(EX_TEMPFAIL);
        };
        return cmd::provision::provision(args);
    }

    // The CLI-05 guard runs for every OTHER verb. Production passes `None` →
    // resolve the real EUID username.
    let guard = guard::guard_agent_user(verb_name(&command), None);
    if guard != ExitCode::SUCCESS {
        return guard;
    }

    // Serialize the mutating verbs against each other (see `statelock`). Held for
    // the whole verb: binding it to `_lock` rather than `_` matters, because `_`
    // drops immediately and would release the lock before the work starts.
    let Some(_lock) = hold_state_lock(&command) else {
        return ExitCode::from(EX_TEMPFAIL);
    };

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

#[cfg(test)]
pub(crate) mod test_support {
    use std::sync::{Mutex, MutexGuard};
    /// Single process-wide lock serializing every test that mutates the
    /// global AGENTLINUX_* env vars. A per-module lock cannot serialize
    /// cross-module tests (they share one process), causing env races.
    /// Poison-tolerant: a panic in one env test must not cascade-poison
    /// the lock for the rest.
    pub static ENV_LOCK: Mutex<()> = Mutex::new(());
    pub fn env_guard() -> MutexGuard<'static, ()> {
        ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner())
    }
}
