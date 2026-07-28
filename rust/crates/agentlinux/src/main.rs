//! AgentLinux CLI binary — a thin adapter over `agentlinux-core`.
//!
//! Phase 56 (Wave 0) grows the binary from the Phase-53 argv spike into the
//! clap-parsed CLI shell (`cli.rs`), the typed recipe-env source
//! (`recipe_env.rs`), and the subprocess dispatcher (`dispatcher.rs`). The six
//! user-facing verbs parse via clap; their bodies are Wave-1/2 stubs. The
//! Phase-53 `reuse-decision` provisioner subcommand is PRESERVED as a pre-clap
//! short-circuit (13-reuse.bats must stay green) — it is dispatched before
//! `Cli::parse()` so clap never sees it.
//!
//! The pure/adapter split: the env-var reads and the canonical-path map live
//! HERE (the I/O boundary); the decision itself lives in
//! `agentlinux_core::reuse`. `agentlinux-core` stays free of `std::env`,
//! `std::fs`, and `std::process` — all new I/O in this phase lives in the bin.

mod cache;
mod catalog;
mod cli;
mod cmd;
mod dispatcher;
mod guard;
mod npm;
mod probe;
mod recipe_env;
mod rewire;
mod sentinel;

use clap::Parser;
use cli::{Cli, Command};
use std::process::ExitCode;

/// GSD's deployed-system VERSION path — a second valid canonical presence for
/// `gsd` (npx form). MUST stay byte-identical to `REUSE_GSD_SYSTEM_PATH` in
/// `plugin/lib/reuse/agents.sh` and `GSD_SYSTEM_PATH` in `detect.ts`.
pub(crate) const GSD_SYSTEM_PATH: &str = "/home/agent/.claude/gsd-core/VERSION";

/// Canonical binary path for a catalog id, or `None` for an unknown id.
///
/// Mirrors `REUSE_AGENT_CANONICAL_PATHS` in `plugin/lib/reuse/agents.sh` (and
/// `CANONICAL_PATHS` in `detect.ts`). The bash map is deliberately kept (it is
/// iterated by `remediate.sh:288`); this is its Rust twin for the decision path.
pub(crate) fn canonical_path(id: &str) -> Option<&'static str> {
    match id {
        "claude-code" => Some("/home/agent/.local/bin/claude"),
        "gsd" => Some("/home/agent/.npm-global/bin/gsd-core"),
        "playwright-cli" => Some("/home/agent/.npm-global/bin/playwright-cli"),
        _ => None,
    }
}

/// Uppercase + hyphens→underscores, matching bash `${id^^//-/_}`
/// (`claude-code` → `CLAUDE_CODE`).
fn env_key(id: &str) -> String {
    id.to_ascii_uppercase().replace('-', "_")
}

/// `agentlinux reuse-decision <id>`
///
/// Reads `DETECT_AGENT_<UPPER>_STATUS` / `_PATH` from the environment (the
/// contract `detect/agents.sh` exports and `13-reuse.bats` sets), resolves the
/// canonical path, calls `agentlinux_core::reuse::agent_decision`, and prints
/// exactly one lowercase token with NO trailing newline (bats asserts
/// `$output == token`; `run` strips a single trailing newline, but emitting
/// none is strictly safe and matches the bash `printf '%s'`).
fn cmd_reuse_decision(id: &str) -> ExitCode {
    let key = env_key(id);
    // Unset status defaults to "absent" (bash `${!var:-absent}` in
    // detect::agent_status).
    let status = std::env::var(format!("DETECT_AGENT_{key}_STATUS"))
        .unwrap_or_else(|_| "absent".to_string());
    // Unset path is compared as "" (bash `${!path_var:-}`).
    let detected_path = std::env::var(format!("DETECT_AGENT_{key}_PATH")).ok();

    let decision = agentlinux_core::reuse::agent_decision(
        id,
        &status,
        detected_path.as_deref(),
        canonical_path(id),
        GSD_SYSTEM_PATH,
    );

    print!("{}", decision.as_str());
    ExitCode::SUCCESS
}

/// EX_USAGE (sysexits.h) — the exit code Commander uses for a parse error, and
/// the code clap-parse failures map to for like-for-like parity.
const EX_USAGE: u8 = 64;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();

    // Pre-clap short-circuit for the Phase-53 provisioner subcommand. It is
    // NOT a clap variant (kept out of `cli.rs` so the six-verb surface stays
    // byte-stable); `plugin/lib/reuse/agents.sh` shells into it and 13-reuse.bats
    // asserts a single lowercase token with no trailing newline. Handling it
    // here — before `Cli::parse()` — keeps that contract exactly as Phase 53
    // shipped it, immune to any clap help/version interception.
    if args.first().map(String::as_str) == Some("reuse-decision") {
        // `agentlinux reuse-decision` with no id decides over the empty id
        // (bash empty-id branch → create), matching the Phase-53 behavior.
        let id = args.get(1).map(String::as_str).unwrap_or("");
        return cmd_reuse_decision(id);
    }

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
    // The guard runs for every verb (CLI-05). Production passes `None` → resolve
    // the real EUID username.
    let guard = guard::guard_agent_user(verb_name(&command), None);
    if guard != ExitCode::SUCCESS {
        return guard;
    }

    match command {
        Command::List(args) => cmd::list::list(&args),
        Command::Adopt(args) => cmd::adopt::adopt(args.name.as_deref(), &args),
        Command::Pin(args) => cmd::pin::pin(&args.spec),
        // install/remove/upgrade are Plan 03 (Wave 2). Until wired, a loud
        // EX_SOFTWARE(70) stub — a premature invocation is a clean line, not a
        // SIGABRT.
        Command::Install(_) | Command::Remove(_) | Command::Upgrade(_) => {
            let verb = verb_name(&command);
            eprintln!("agentlinux: '{verb}' is not implemented yet (Wave 2)");
            ExitCode::from(70)
        }
    }
}
