//! AgentLinux CLI binary — a thin adapter over `agentlinux-core`.
//!
//! This phase (53) needs the binary to compile, exit 0 on no args (the
//! static-musl build gate RUST-01), and expose the `reuse-decision` subcommand
//! (RUST-03 provisioner) that `plugin/lib/reuse/agents.sh` shells into. Real
//! subcommand dispatch beyond that (`classify`/`divergence` wiring) and `clap`
//! land later per RESEARCH §Alternatives — a plain `match` on argv suffices for
//! the spike.
//!
//! The pure/adapter split: the env-var reads and the canonical-path map live
//! HERE (the I/O boundary); the decision itself lives in
//! `agentlinux_core::reuse`. `agentlinux-core` stays free of `std::env`.

use std::process::ExitCode;

/// GSD's deployed-system VERSION path — a second valid canonical presence for
/// `gsd` (npx form). MUST stay byte-identical to `REUSE_GSD_SYSTEM_PATH` in
/// `plugin/lib/reuse/agents.sh` and `GSD_SYSTEM_PATH` in `detect.ts`.
const GSD_SYSTEM_PATH: &str = "/home/agent/.claude/gsd-core/VERSION";

/// Canonical binary path for a catalog id, or `None` for an unknown id.
///
/// Mirrors `REUSE_AGENT_CANONICAL_PATHS` in `plugin/lib/reuse/agents.sh` (and
/// `CANONICAL_PATHS` in `detect.ts`). The bash map is deliberately kept (it is
/// iterated by `remediate.sh:288`); this is its Rust twin for the decision path.
fn canonical_path(id: &str) -> Option<&'static str> {
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

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        None => ExitCode::SUCCESS,
        Some("reuse-decision") => match args.get(1) {
            Some(id) => cmd_reuse_decision(id),
            // No id → decide over the empty id (bash empty-id branch → create).
            None => cmd_reuse_decision(""),
        },
        Some(other) => {
            eprintln!("agentlinux: unknown subcommand '{other}'");
            ExitCode::from(2)
        }
    }
}
