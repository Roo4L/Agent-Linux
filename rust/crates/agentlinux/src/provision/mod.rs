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
pub mod log;
pub mod nodejs;
pub mod path_wiring;
pub mod probe;
pub mod registry_cli;
pub mod remediate;
pub mod remediate_npm_prefix;
pub mod sudoers;
pub mod wizard;

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
/// consumed `user`; Wave 5 populates the whole map from the real detect→decide
/// wiring (`cmd/provision.rs` → the pure `agentlinux-core` gates). `agents`
/// carries the per-agent `RESOLUTIONS[agents.<id>]` tokens, keyed by catalog id,
/// built by iterating the Rust `canonical_path` map IN-PROCESS (PROV-02: the Rust
/// map is the single authoritative per-agent enumerator).
#[derive(Debug, Clone)]
pub struct Resolutions {
    /// `RESOLUTIONS[user]` — consumed by `agent_user::run`.
    pub user: Resolution,
    /// `RESOLUTIONS[sudoers]`.
    pub sudoers: Resolution,
    /// `RESOLUTIONS[node]`.
    pub node: Resolution,
    /// `RESOLUTIONS[npm-prefix]`.
    pub npm_prefix: Resolution,
    /// `RESOLUTIONS[agents.<id>]` — per-agent tokens, keyed by catalog id. Built
    /// by iterating the Rust `canonical_path` ids (PROV-02 single source).
    pub agents: std::collections::BTreeMap<String, Resolution>,
}

impl Resolutions {
    /// A fresh CREATE for every core component with NO per-agent entries. Retained
    /// for the unit tests + as the clean-host baseline; the orchestrator's real
    /// path uses [`Resolutions::from_decide`] (the detect→decide computation).
    pub fn seed_create() -> Self {
        Self {
            user: Resolution::Create,
            sudoers: Resolution::Create,
            node: Resolution::Create,
            npm_prefix: Resolution::Create,
            agents: std::collections::BTreeMap::new(),
        }
    }

    /// The real DECIDE phase (PROV-02, 57-06): probe the host + iterate the Rust
    /// `canonical_path` map IN-PROCESS, calling the ALREADY-PORTED pure gate
    /// (`agentlinux_core::reuse::agent_decision`) per id to build
    /// `RESOLUTIONS[agents.<id>]`. NO Bash map read, NO `reuse-decision` shell-out.
    ///
    /// The core-component tokens (user/sudoers/node/npm-prefix) resolve to CREATE
    /// on a clean host — the provisioner's steps are idempotent CREATE/REUSE, and
    /// the Bash entrypoint's brownfield remediation gating (npm-prefix chown,
    /// sudoers overwrite) is the `--yes`-gated path; a `--yes` provision run (the
    /// harness invocation) never bails. The per-agent tokens are the substantive
    /// PROV-02 win: they come from the Rust map + the pure gate, not a Bash
    /// iterator.
    ///
    /// `canonical_ids` + `canonical_of` + `gsd_system_path` are injected so this
    /// stays free of `main.rs`'s map (the pure/adapter split); the orchestrator
    /// passes `main::CANONICAL_IDS` / `main::canonical_path` / `main::GSD_SYSTEM_PATH`.
    pub fn from_decide<F>(canonical_ids: &[&str], canonical_of: F, gsd_system_path: &str) -> Self
    where
        F: Fn(&str) -> Option<&'static str>,
    {
        let mut agents = std::collections::BTreeMap::new();
        for &id in canonical_ids {
            let probe = crate::provision::probe::probe_agent(id);
            // The pure gate — identical decision surface the Bash
            // `reuse::agent_decision` shim wraps, called DIRECTLY in-process.
            let decision = agentlinux_core::reuse::agent_decision(
                id,
                &probe.status,
                if probe.path.is_empty() {
                    None
                } else {
                    Some(probe.path.as_str())
                },
                canonical_of(id),
                gsd_system_path,
            );
            agents.insert(id.to_string(), Resolution::from_decision(decision));
        }
        Self {
            user: Resolution::Create,
            sudoers: Resolution::Create,
            node: Resolution::Create,
            npm_prefix: Resolution::Create,
            agents,
        }
    }
}

impl Resolution {
    /// Map the pure `agentlinux_core::reuse::Decision` token to the provisioner
    /// `Resolution` (the two enums are the same 3-way surface plus the
    /// `ReuseWithWarning`/`Bail` states only the TTY-consent path produces).
    fn from_decision(d: agentlinux_core::reuse::Decision) -> Self {
        match d {
            agentlinux_core::reuse::Decision::Reuse => Resolution::Reuse,
            agentlinux_core::reuse::Decision::Remediate => Resolution::Remediate,
            agentlinux_core::reuse::Decision::Create => Resolution::Create,
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
