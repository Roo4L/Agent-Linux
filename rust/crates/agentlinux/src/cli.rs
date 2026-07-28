//! cli.rs — the clap derive tree mirroring the Commander surface (VERB-01).
//!
//! Byte-for-byte port of `plugin/cli/src/index.ts:20-108`: the six subcommands
//! (`list`, `install`, `adopt`, `remove`, `upgrade`, `pin`), their flags and
//! positionals, the program-level `-V, --version`, and the `install --version
//! <semver>` shadow (CLI-03) that Commander achieves via
//! `enablePositionalOptions()`.
//!
//! The like-for-like invariant: the parsed flag NAMES + positional shapes must
//! match Commander exactly (a bats `agentlinux <verb> ...` invocation parses
//! identically). clap kebab-cases the field name by default so e.g.
//! `reset_all_curated` → `--reset-all-curated`; the `cli_parse` test corpus
//! below asserts every row so a drift is a test failure, not a silent skew.
//!
//! Open Q1 (RESOLVED at plan time): no bats asserts an exact `--help` body —
//! only `--version` prints the version number (CLI-01) — so clap's default help
//! rendering is safe and we do NOT hand-roll the help text.

use clap::{Parser, Subcommand};

/// `agentlinux <verb> [flags]` — the registry CLI root.
///
/// The program-level `version` attribute wires `-V, --version` to
/// `CARGO_PKG_VERSION` (now `0.3.6`, synced to package.json → CLI-01). The
/// hidden `reuse-decision` provisioner subcommand is dispatched BEFORE this
/// parser runs (a pre-clap short-circuit in `main.rs`) so it is intentionally
/// absent from this enum — keeping the Phase-53 reuse path (13-reuse.bats)
/// byte-stable while clap owns the six user-facing verbs.
#[derive(Debug, Parser)]
#[command(
    name = "agentlinux",
    version,
    about = "AgentLinux registry CLI — install, upgrade, remove catalog agents"
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

/// The six catalog verbs. Each variant carries EXACTLY the flags/positionals
/// declared in `index.ts:38-105` — no more, no fewer.
#[derive(Debug, Subcommand)]
pub enum Command {
    /// List catalog agents and their install status.
    List(ListArgs),
    /// Install a catalog agent at its pinned_version.
    Install(InstallArgs),
    /// Adopt pre-existing reuse-eligible agents into managed sentinels (no install).
    Adopt(AdoptArgs),
    /// Uninstall a catalog agent.
    Remove(RemoveArgs),
    /// Reconcile installed versions against the curated catalog.
    Upgrade(UpgradeArgs),
    /// Set sticky override: <name>=curated|latest|x.y.z.
    Pin(PinArgs),
}

/// `list` — index.ts:38-47. Four boolean `--long` flags, no positional.
#[derive(Debug, Parser)]
pub struct ListArgs {
    /// include test-only entries (hidden by default)
    #[arg(long)]
    pub include_test: bool,
    /// group entries by category (coding-agent, mcp, devops, …)
    #[arg(long)]
    pub by_category: bool,
    /// show the DESCRIPTION column (hidden by default; always in --json)
    #[arg(long)]
    pub descriptions: bool,
    /// machine-readable JSON array output
    #[arg(long)]
    pub json: bool,
}

/// `install <name>` — index.ts:49-65. Required positional `name` plus the
/// `--version <semver>` shadow (CLI-03): `disable_version_flag` frees `--version`
/// locally so it binds this Option<String> arg, while the ROOT `Cli` keeps the
/// global `-V, --version`. Mirrors Commander's `enablePositionalOptions()`.
#[derive(Debug, Parser)]
#[command(disable_version_flag = true)]
pub struct InstallArgs {
    /// the catalog agent id to install
    pub name: String,
    /// re-run install.sh even if sentinel matches
    #[arg(long)]
    pub force: bool,
    /// override catalog pin with a specific version
    #[arg(long)]
    pub version: Option<String>,
    /// allow installing test-only entries (hidden by default)
    #[arg(long)]
    pub include_test: bool,
    /// approve state-overwriting REMEDIATE-04 (uninstall + reinstall) in non-TTY mode
    #[arg(long)]
    pub yes: bool,
    /// preview the install decision (reuse|remediate|create) without dispatching; exits 0
    #[arg(long)]
    pub dry_run: bool,
}

/// `adopt [name]` — index.ts:67-78. OPTIONAL positional `name` + `--all`,
/// `--include-test`, `--json`.
#[derive(Debug, Parser)]
pub struct AdoptArgs {
    /// optional catalog agent id; omit + --all to sweep the catalog
    pub name: Option<String>,
    /// adopt every reuse-eligible catalog agent
    #[arg(long)]
    pub all: bool,
    /// include test-only entries (hidden by default)
    #[arg(long)]
    pub include_test: bool,
    /// machine-readable JSON array output
    #[arg(long)]
    pub json: bool,
}

/// `remove <name>` — index.ts:80-86. Required positional `name` + `--force`.
#[derive(Debug, Parser)]
pub struct RemoveArgs {
    /// the catalog agent id to uninstall
    pub name: String,
    /// succeed even if agent is not installed (idempotent no-op)
    #[arg(long)]
    pub force: bool,
}

/// `upgrade` — index.ts:88-98. Five boolean `--long` flags, no positional.
#[derive(Debug, Parser)]
pub struct UpgradeArgs {
    /// accept curated versions for all agents; clear overrides
    #[arg(long)]
    pub reset_all_curated: bool,
    /// install curated only for non-overridden agents
    #[arg(long)]
    pub respect_overrides: bool,
    /// install npm latest for all (implies --check-upstream)
    #[arg(long)]
    pub all_latest: bool,
    /// query `npm view <pkg> version` for upstream latest (network)
    #[arg(long)]
    pub check_upstream: bool,
    /// machine-readable JSON array output
    #[arg(long)]
    pub json: bool,
}

/// `pin <spec>` — index.ts:100-105. Single required positional `spec`.
#[derive(Debug, Parser)]
pub struct PinArgs {
    /// <name>=curated|latest|x.y.z
    pub spec: String,
}

#[cfg(test)]
mod cli_parse {
    use super::*;

    /// Parse a full argv (program name first) and return the `Command`, panicking
    /// with clap's rendered error on failure so a broken row shows the reason.
    fn parse(args: &[&str]) -> Command {
        Cli::try_parse_from(args)
            .unwrap_or_else(|e| panic!("parse failed for {args:?}: {e}"))
            .command
    }

    #[test]
    fn list_all_flags() {
        let cmd = parse(&[
            "agentlinux",
            "list",
            "--include-test",
            "--by-category",
            "--descriptions",
            "--json",
        ]);
        match cmd {
            Command::List(a) => {
                assert!(a.include_test && a.by_category && a.descriptions && a.json);
            }
            other => panic!("expected List, got {other:?}"),
        }
    }

    #[test]
    fn install_version_shadow_binds_the_subcommand_arg() {
        // CLI-03 keystone: `--version 9.9.9` here is the install ARG, not the
        // program version flag — it must parse the value, not print + exit.
        let cmd = parse(&[
            "agentlinux",
            "install",
            "test-dummy",
            "--force",
            "--version",
            "9.9.9",
            "--include-test",
            "--yes",
            "--dry-run",
        ]);
        match cmd {
            Command::Install(a) => {
                assert_eq!(a.name, "test-dummy");
                assert!(a.force);
                assert_eq!(a.version.as_deref(), Some("9.9.9"));
                assert!(a.include_test);
                assert!(a.yes);
                assert!(a.dry_run);
            }
            other => panic!("expected Install, got {other:?}"),
        }
    }

    #[test]
    fn install_version_shadow_position_independent() {
        // The bats CLI-03 line places flags BEFORE the positional:
        // `install --include-test --version 9.9.9 test-dummy`. Assert that order
        // parses the same way (name last, version bound to 9.9.9).
        let cmd = parse(&[
            "agentlinux",
            "install",
            "--include-test",
            "--version",
            "9.9.9",
            "test-dummy",
        ]);
        match cmd {
            Command::Install(a) => {
                assert_eq!(a.name, "test-dummy");
                assert_eq!(a.version.as_deref(), Some("9.9.9"));
                assert!(a.include_test);
            }
            other => panic!("expected Install, got {other:?}"),
        }
    }

    #[test]
    fn adopt_optional_positional() {
        match parse(&["agentlinux", "adopt"]) {
            Command::Adopt(a) => {
                assert_eq!(a.name, None);
                assert!(!a.all);
            }
            other => panic!("expected Adopt, got {other:?}"),
        }
        match parse(&["agentlinux", "adopt", "foo", "--all"]) {
            Command::Adopt(a) => {
                assert_eq!(a.name.as_deref(), Some("foo"));
                assert!(a.all);
            }
            other => panic!("expected Adopt, got {other:?}"),
        }
    }

    #[test]
    fn remove_name_and_force() {
        match parse(&["agentlinux", "remove", "test-dummy", "--force"]) {
            Command::Remove(a) => {
                assert_eq!(a.name, "test-dummy");
                assert!(a.force);
            }
            other => panic!("expected Remove, got {other:?}"),
        }
    }

    #[test]
    fn upgrade_all_flags() {
        let cmd = parse(&[
            "agentlinux",
            "upgrade",
            "--reset-all-curated",
            "--respect-overrides",
            "--all-latest",
            "--check-upstream",
            "--json",
        ]);
        match cmd {
            Command::Upgrade(a) => {
                assert!(
                    a.reset_all_curated
                        && a.respect_overrides
                        && a.all_latest
                        && a.check_upstream
                        && a.json
                );
            }
            other => panic!("expected Upgrade, got {other:?}"),
        }
    }

    #[test]
    fn pin_spec_positional() {
        match parse(&["agentlinux", "pin", "test-dummy=latest"]) {
            Command::Pin(a) => assert_eq!(a.spec, "test-dummy=latest"),
            other => panic!("expected Pin, got {other:?}"),
        }
    }

    #[test]
    fn program_version_flag_prints_and_exits() {
        // The ROOT `--version` (no subcommand) is a clap DisplayVersion "error"
        // that main.rs maps to exit 0. try_parse_from returns Err with that kind.
        let err = Cli::try_parse_from(["agentlinux", "--version"]).unwrap_err();
        assert_eq!(err.kind(), clap::error::ErrorKind::DisplayVersion);
        // And the rendered string carries the crate version (0.3.6, per CLI-01).
        assert!(err.to_string().contains(env!("CARGO_PKG_VERSION")));
    }

    #[test]
    fn unknown_verb_is_err() {
        assert!(Cli::try_parse_from(["agentlinux", "frobnicate"]).is_err());
    }
}
