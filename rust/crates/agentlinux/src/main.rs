//! AgentLinux CLI binary — a thin adapter over `agentlinux-core`.
//!
//! Phase 56 (Wave 0) grows the binary from the Phase-53 argv spike into the
//! clap-parsed CLI shell (`cli.rs`), the typed recipe-env source
//! (`recipe_env.rs`), and the subprocess dispatcher (`dispatcher.rs`). The six
//! user-facing verbs parse via clap.
//!
//! The pure/adapter split: the env-var reads and the canonical-path map live
//! HERE (the I/O boundary); the decision itself lives in
//! `agentlinux_core::reuse`. `agentlinux-core` stays free of `std::env`,
//! `std::fs`, and `std::process` — all new I/O in this phase lives in the bin.

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
mod sysio;

use clap::Parser;
use cli::{Cli, Command};
use std::process::ExitCode;

/// GSD's deployed-system VERSION path — a second valid canonical presence for
/// `gsd` (npx form).
pub(crate) const GSD_SYSTEM_PATH: &str = "/home/agent/.claude/gsd-core/VERSION";

/// The catalog ids WITH a canonical-path entry — the AUTHORITATIVE per-agent
/// enumerator (PROV-02, 57-06). `cmd/provision.rs` iterates THIS list in-process
/// to build `RESOLUTIONS[agents.<id>]` in-process. MUST stay in sync with the `canonical_path` match arms and
/// byte-identical to the KEYS of `REUSE_AGENT_CANONICAL_PATHS` in
/// `plugin/lib/reuse/agents.sh` — the retained Bash shim's map (kept only as the
/// 13-reuse spec contract + GATE-05 rollback fallback, NOT a second live source).
pub(crate) const CANONICAL_IDS: &[&str] = &["claude-code", "gsd", "playwright-cli"];

/// Canonical binary path for a catalog id, or `None` for an unknown id.
///
/// Mirrors `REUSE_AGENT_CANONICAL_PATHS` in `plugin/lib/reuse/agents.sh` (and
/// `CANONICAL_PATHS` in `detect.ts`). Post-57-06 the Rust map is the SINGLE
/// authoritative source the provisioner iterates in-process; the retained Bash
/// map is only the 13-reuse spec shim + GATE-05 fallback (plan-check B-1).
pub(crate) fn canonical_path(id: &str) -> Option<&'static str> {
    match id {
        "claude-code" => Some("/home/agent/.local/bin/claude"),
        "gsd" => Some("/home/agent/.npm-global/bin/gsd-core"),
        "playwright-cli" => Some("/home/agent/.npm-global/bin/playwright-cli"),
        _ => None,
    }
}

/// EX_USAGE (sysexits.h) — the exit code Commander uses for a parse error, and
/// the code clap-parse failures map to for like-for-like parity.
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
/// Consumed by the Wave-1 verb adapters (`cmd/list.rs` here; `cmd/{pin,adopt}.rs`
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
        // through `require_root` instead — Pitfall 7); a name is provided for
        // completeness/exhaustiveness.
        Command::Provision(_) => "provision",
    }
}

/// Route a parsed verb to its handler.
///
/// CLI-05 (index.ts:34-36): the guard runs BEFORE any verb — including the
/// read-only `list` — so a non-install-user invoker fails fast (exit 64) before
/// any command body runs. `guard_agent_user` returns `SUCCESS` on a match; on a
/// mismatch it prints the diagnostic and returns `ExitCode::from(64)`, which we
/// propagate immediately.
///
/// Wave-1 (this plan) wires `list`/`adopt`/`pin`; `install`/`remove`/`upgrade`
/// remain loud EX_SOFTWARE(70) not-implemented stubs until Plan 03.
fn dispatch(command: Command) -> ExitCode {
    // `provision` is the PRE-Node provisioner entrypoint: it runs privileged
    // systems I/O BEFORE any agent user exists, so it dispatches through
    // `require_root` (EUID==0), NOT the CLI-05 `guard_agent_user` (which resolves
    // the invoker's passwd entry and REJECTS root — the provisioner's REQUIRED
    // invoker). Pitfall 7 / T-57-04: routing it through the wrong guard would make
    // every real `sudo agentlinux provision` exit 64. Handled BEFORE the blanket
    // guard so the six user-facing verbs keep their CLI-05 guard.
    if let Command::Provision(args) = &command {
        let guard = guard::require_root(None);
        if guard != ExitCode::SUCCESS {
            return guard;
        }
        return cmd::provision::provision(args);
    }

    // The CLI-05 guard runs for every OTHER verb. Production passes `None` →
    // resolve the real EUID username.
    let guard = guard::guard_agent_user(verb_name(&command), None);
    if guard != ExitCode::SUCCESS {
        return guard;
    }

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
