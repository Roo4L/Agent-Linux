//! provision — the pre-Node provisioner steps, one module per numbered stage.
//!
//! The orchestrator lives in `cmd/provision.rs` and owns the order; this module
//! holds the five steps (`agent_user`, `sudoers`, `nodejs`, `path_wiring`,
//! `registry_cli`) plus the shared `Resolutions`/`ProvisionCtx` types they
//! consume.
//!
//! DECIDE-THEN-ACT: the per-component decision tokens (`Resolutions`) are
//! computed UP FRONT — the pure gates own that decision — and the steps only do
//! I/O, dispatching on their token. A step never re-derives a decision.
//!
//! The decision vocabulary narrows between the two phases. DECIDE produces a
//! [`Resolution`], which includes `Bail`; the orchestrator then exits 65 on every
//! bail before any step runs, and hands the steps a [`StepResolution`], which has
//! no `Bail` variant to handle.

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

/// A resolution as the STEP layer sees it — the same tokens minus `Bail`.
///
/// By the time the step loop runs, `remediate::flush_or_exit` has already exited
/// 65 on every bail, so no step can encounter one. Saying that in the type rather
/// than in a comment deletes a `Bail => Err("unreachable…")` arm from each of the
/// four dispatching steps — arms reachable only by a bug, whose tests asserted
/// nothing beyond the struct literal they had just written.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StepResolution {
    Create,
    Reuse,
    Remediate,
    ReuseWithWarning,
}

/// The per-component tokens the DECIDE phase produces.
///
/// The core components (user/sudoers/node/npm-prefix) start at `Create` — the
/// steps are idempotent CREATE/REUSE on a clean host — and
/// `remediate::decide_core` overwrites them with the real host verdict.
#[derive(Debug, Clone)]
pub struct Resolutions {
    pub user: Resolution,
    pub sudoers: Resolution,
    pub node: Resolution,
    pub npm_prefix: Resolution,
}

impl Default for Resolutions {
    fn default() -> Self {
        Self {
            user: Resolution::Create,
            sudoers: Resolution::Create,
            node: Resolution::Create,
            npm_prefix: Resolution::Create,
        }
    }
}

impl Resolutions {
    /// Narrow every token to a [`StepResolution`], or return the component name
    /// of the first that is still `Bail`.
    ///
    /// The `Err` arm is the one place the "flush_or_exit ran first" invariant is
    /// checked, replacing four per-step defensive arms.
    pub fn into_step(self) -> Result<StepResolutions, &'static str> {
        Ok(StepResolutions {
            user: narrow(self.user).ok_or("user")?,
            sudoers: narrow(self.sudoers).ok_or("sudoers")?,
            node: narrow(self.node).ok_or("node")?,
            npm_prefix: narrow(self.npm_prefix).ok_or("npm-prefix")?,
        })
    }
}

/// `Resolutions` after the bail flush — what every step dispatches on.
#[derive(Debug, Clone, Copy)]
pub struct StepResolutions {
    pub user: StepResolution,
    pub sudoers: StepResolution,
    pub node: StepResolution,
    pub npm_prefix: StepResolution,
}

/// `Resolution` → `StepResolution`, `None` for `Bail`.
fn narrow(r: Resolution) -> Option<StepResolution> {
    match r {
        Resolution::Create => Some(StepResolution::Create),
        Resolution::Reuse => Some(StepResolution::Reuse),
        Resolution::Remediate => Some(StepResolution::Remediate),
        Resolution::ReuseWithWarning => Some(StepResolution::ReuseWithWarning),
        Resolution::Bail => None,
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
    /// The per-component DECIDE-phase tokens, already narrowed past `Bail`.
    ///
    /// `--yes` is deliberately NOT carried here: consent is resolved once, during
    /// DECIDE, and the answer is already baked into these tokens. A step that
    /// re-read a `yes` flag could reach a different conclusion than the one the
    /// operator was shown.
    pub resolutions: StepResolutions,
}
