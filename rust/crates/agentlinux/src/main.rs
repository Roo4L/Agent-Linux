//! AgentLinux CLI binary — a thin adapter over `agentlinux-core`.
//!
//! This phase (53-01) only needs the binary to compile and exit 0 on no args so
//! the static-musl build gate (RUST-01) can prove a fully-static link. Real
//! subcommand dispatch (`reuse-decision`, and the hidden `classify`/`divergence`
//! test subcommands) lands in Plan 02; `clap` is deferred to Phase 56 per
//! RESEARCH §Alternatives — a plain `match` on argv suffices for the spike.

use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        None => ExitCode::SUCCESS,
        Some(other) => {
            eprintln!("agentlinux: unknown subcommand '{other}'");
            ExitCode::from(2)
        }
    }
}
