//! provision — the pre-Node provisioner steps (Phase 57), each a byte-faithful
//! port of a `plugin/provisioner/NN-*.sh` script.
//!
//! The orchestrator shell lives in `cmd/provision.rs`; this module holds the
//! per-step ports plus the shared `Resolutions`/`ProvisionCtx` types every step
//! consumes. Wave 1 lands `agent_user` (10-agent-user.sh) + the scaffold; Waves
//! 2-5 add `sudoers`/`nodejs`/`path_wiring`/`registry_cli`.
//!
//! DECIDE-THEN-ACT: the per-component decision tokens (`Resolutions`) are
//! computed UP FRONT (the already-ported pure gates own that decision) and the
//! steps only do I/O, dispatching on their token. Wave 1 seeds
//! `Resolutions::user = create` directly; Wave 5 swaps the seed for the real
//! detect→decide wiring WITHOUT restructuring the step loop.
//!
//! `dead_code` allowed at module scope for this wave: the non-`user` resolution
//! tokens + the not-yet-consumed ctx fields are wired by Waves 2-5; the Wave-1
//! step + the `#[cfg(test)]` module exercise the live surface now.
#![allow(dead_code)]

pub mod agent_user;
pub mod sudoers;

use crate::distro::Family;

/// The per-component decision token — the DECIDE phase's output for one
/// provisioner component. Mirrors the Bash `RESOLUTIONS[<component>]` values
/// (`create`/`reuse`/`remediate`/`reuse-with-warning`/`bail`) that
/// `remediate::collect_all_decisions` populates. A step dispatches on its own
/// token and does ONLY I/O — it never re-derives the decision.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Resolution {
    /// Fresh provision — run the CREATE path (useradd/locale/…).
    Create,
    /// Compatible existing state — skip the identity-mutating CREATE steps.
    Reuse,
    /// Compatible except for a fixable drift owned by a LATER component's step
    /// (acts identically to `Reuse` on THIS component's identity).
    Remediate,
    /// Operator declined a state-overwriting remediation — keep existing state,
    /// emit a `[REUSE-WARN]` marker, skip the CREATE steps.
    ReuseWithWarning,
    /// Incompatible host state — unreachable inside the step loop (a bail exits
    /// 65 before run_provisioners); a step treats it as a defensive error.
    Bail,
}

/// The per-component resolution tokens the DECIDE phase produces. Wave 1 only
/// consumes `user`; the later fields are populated as Waves 2-5 wire their steps
/// (kept here so the struct grows without churning every call site).
#[derive(Debug, Clone)]
pub struct Resolutions {
    /// `RESOLUTIONS[user]` — consumed by `agent_user::run` (Wave 1).
    pub user: Resolution,
    /// `RESOLUTIONS[sudoers]` — Wave 2.
    pub sudoers: Resolution,
    /// `RESOLUTIONS[node]` — Wave 3.
    pub node: Resolution,
    /// `RESOLUTIONS[npm-prefix]` — Wave 3/4.
    pub npm_prefix: Resolution,
}

impl Resolutions {
    /// Wave-1 seed: a fresh CREATE for every component. Wave 5 replaces this
    /// constructor's call site with the real detect→decide computation; the
    /// steps do not change.
    pub fn seed_create() -> Self {
        Self {
            user: Resolution::Create,
            sudoers: Resolution::Create,
            node: Resolution::Create,
            npm_prefix: Resolution::Create,
        }
    }
}

/// The context every provisioner step receives — the settled install identity,
/// the distro family, the resolution tokens, and the mutation-gate flags. A step
/// reads what it needs and does I/O; it never re-resolves the user or re-detects
/// the distro (both are settled once in the orchestrator).
#[derive(Debug, Clone)]
pub struct ProvisionCtx {
    /// The resolved install user (`--user` > `$AGENTLINUX_USER` > `agent`,
    /// charset+reserved-validated upstream).
    pub install_user: String,
    /// `/home/<install_user>` — derived alongside the user.
    pub install_home: String,
    /// The detected package-manager family (apt↔dnf fork point).
    pub family: Family,
    /// The per-component DECIDE-phase tokens.
    pub resolutions: Resolutions,
    /// `--yes` — non-TTY consent for state-overwriting remediations.
    pub yes: bool,
    /// `--dry-run` — no host mutation (Wave 5 lands the full report/dry-run
    /// parity; Wave 1 short-circuits before the step loop).
    pub dry_run: bool,
}
