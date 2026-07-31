//! provision/remediate.rs — the CORE-COMPONENT brownfield DECIDE + consent/bail
//! gate for the two core components the provisioner remediates: the npm-global prefix (REMEDIATE-01) and the sudoers
//! drop-in (REMEDIATE-03). Per-agent (REMEDIATE-04) + user (REUSE-01) decisions
//! live in the `from_decide` agent loop / `agent_user` step.
//!
//! DECIDE-THEN-ACT: `decide_core` probes host state and writes
//! `Resolution` tokens with ZERO mutation; a state-overwriting Remediate WITHOUT
//! consent registers a `Bail`. `flush_or_exit` then prints every `[BAIL]` line and
//! `exit 65` (EX_DATAERR) BEFORE the step loop — so a refused host is left
//! byte-identical (the NO-MUTATION-SNAPSHOT contract).
//!
//! Consent policy (remediate.sh `remediate_action_overwrites_state`): additive
//! actions (a missing-file install) run unconditionally; state-OVERWRITING actions
//! (npm-prefix chown/rebase, sudoers drift overwrite) need `--yes`, else — on a
//! TTY — the interactive prompt, else a bail. The real curl-installer path passes
//! `--yes` and is greenfield, so it never bails and never prompts.

use crate::provision::probe::{self, NpmPrefixState, SudoersState};
use crate::provision::{Resolution, Resolutions};
use std::io::IsTerminal;

/// An aggregated incompatible-host-state record. `flush_or_exit` renders each as
/// `[BAIL] component=<component> reason=<reason> hint=<hint>`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Bail {
    pub component: &'static str,
    pub reason: &'static str,
    pub hint: &'static str,
}

/// The consent outcome for a state-overwriting remediation. PURE — the caller
/// supplies `yes` (--yes) + `is_tty` so this stays unit-testable.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Consent {
    /// Proceed with the overwrite (--yes granted, or additive action).
    Proceed,
    /// Defer to the interactive `[Y/n]` prompt (TTY, no --yes).
    Prompt,
    /// Refused (non-TTY, no --yes) — register a bail, do not mutate.
    Bail,
}

/// Consent for a remediation that OVERWRITES existing host state. PURE.
///
/// `--yes` proceeds, a TTY asks the operator, and a non-interactive run with no
/// `--yes` refuses. Additive remediations never call this — they simply proceed,
/// which is why there is no action parameter: the caller already knows which kind
/// it is holding. (This used to take an action string checked against a
/// three-entry allowlist; both call sites passed a literal that always matched,
/// and the third entry was never passed by anything.)
#[must_use]
pub fn consent_for_overwrite(yes: bool, is_tty: bool) -> Consent {
    if yes {
        Consent::Proceed
    } else if is_tty {
        Consent::Prompt
    } else {
        Consent::Bail
    }
}

/// What a pure core-component decider concluded.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CoreOutcome {
    /// Settled without asking anyone.
    Settled(Resolution),
    /// A state-overwriting remediation on a TTY — the CALLER must prompt.
    ///
    /// This variant is why `decide_core` no longer re-derives `!yes && is_tty`
    /// after calling these deciders: the decider says whether a prompt is owed,
    /// and the answer cannot disagree with the decision it came from.
    NeedsPrompt,
}

/// The `sudoers` outcome from its probed state + consent. Returns the outcome
/// and, when a drift overwrite is refused non-interactively, the bail to
/// aggregate. PURE (state + flags in, decision out).
#[must_use]
pub fn decide_sudoers(state: SudoersState, yes: bool, is_tty: bool) -> (CoreOutcome, Option<Bail>) {
    match state {
        SudoersState::Absent => (CoreOutcome::Settled(Resolution::Create), None),
        SudoersState::Canonical => (CoreOutcome::Settled(Resolution::Reuse), None),
        SudoersState::Drifted => match consent_for_overwrite(yes, is_tty) {
            Consent::Proceed => (CoreOutcome::Settled(Resolution::Remediate), None),
            Consent::Prompt => (CoreOutcome::NeedsPrompt, None),
            Consent::Bail => (
                CoreOutcome::Settled(Resolution::Bail),
                Some(Bail {
                    component: "sudoers",
                    reason: "drift",
                    hint: "run with --yes to overwrite with the canonical ADR-012 line",
                }),
            ),
        },
    }
}

/// The `npm-prefix` outcome from its probed state + consent. PURE.
#[must_use]
pub fn decide_npm_prefix(
    state: NpmPrefixState,
    yes: bool,
    is_tty: bool,
) -> (CoreOutcome, Option<Bail>) {
    match state {
        NpmPrefixState::Absent => (CoreOutcome::Settled(Resolution::Create), None),
        NpmPrefixState::OwnedByUser => (CoreOutcome::Settled(Resolution::Reuse), None),
        NpmPrefixState::WrongOwner => match consent_for_overwrite(yes, is_tty) {
            Consent::Proceed => (CoreOutcome::Settled(Resolution::Remediate), None),
            Consent::Prompt => (CoreOutcome::NeedsPrompt, None),
            Consent::Bail => (
                CoreOutcome::Settled(Resolution::Bail),
                Some(Bail {
                    component: "npm-prefix",
                    reason: "wrong-owner",
                    hint: "run with --yes to chown or rebase",
                }),
            ),
        },
    }
}

/// DECIDE-THEN-ACT core-component step (the I/O shell over the pure deciders):
/// probe sudoers + npm-prefix host state, overwrite the two seeded `Create` tokens
/// in `res` with the real resolution, and push any bail. On a TTY the `Prompt`
/// outcome is resolved here via the interactive confirm (declined → `ReuseWithWarning`,
/// leaving the drifted state untouched). Makes NO mutation itself.
pub fn decide_core(
    user: &str,
    home: &str,
    yes: bool,
    res: &mut Resolutions,
    bails: &mut Vec<Bail>,
) {
    let is_tty = std::io::stdin().is_terminal();

    // User (REUSE-01): absent → Create; bash-shell existing → Reuse (re-attach
    // path wiring, [REMEDIATE-02]); wrong-shell → irreconcilable BAIL with the
    // dedicated hint (--yes cannot fix a wrong shell).
    match probe::user_state(user) {
        probe::UserState::Absent => res.user = Resolution::Create,
        probe::UserState::Conforming => res.user = Resolution::Reuse,
        probe::UserState::WrongShell => {
            eprintln!("agentlinux: existing user \"{user}\" is incompatible (wrong-shell).");
            eprintln!(
                "Re-run with --user=NAME using a compatible user, or fix the shell of the \
                 existing user."
            );
            res.user = Resolution::Bail;
            bails.push(Bail {
                component: "user",
                reason: "wrong-shell",
                hint: "use --user=NAME with a compatible user",
            });
        }
    }

    // Component prompt order: npm-prefix BEFORE sudoers. This is load-bearing —
    // the tests feed answers positionally (e.g. `n\nY\n` = decline npm-prefix,
    // accept sudoers), and so does an operator answering two prompts in a row.
    let (npm_outcome, npm_bail) =
        decide_npm_prefix(probe::npm_prefix_state(user, home), yes, is_tty);
    res.npm_prefix = match npm_outcome {
        CoreOutcome::Settled(r) => r,
        CoreOutcome::NeedsPrompt => prompt_component(
            "npm-prefix",
            "REMEDIATE-01",
            &format!("chown ~{user}/.npm-global to {user}:{user}"),
        ),
    };
    if let Some(b) = npm_bail {
        bails.push(b);
    }

    let (sudoers_outcome, sudoers_bail) = decide_sudoers(probe::sudoers_state(user), yes, is_tty);
    res.sudoers = match sudoers_outcome {
        CoreOutcome::Settled(r) => r,
        CoreOutcome::NeedsPrompt => prompt_component(
            "sudoers",
            "REMEDIATE-03",
            "overwrite /etc/sudoers.d/agentlinux with canonical ADR-012 line",
        ),
    };
    if let Some(b) = sudoers_bail {
        bails.push(b);
    }
}

/// Interactive consent for one state-overwriting remediation (TTY path only —
/// `provision --yes` and non-TTY never reach here). Delegates the `[Y/n]` prompt
/// to `wizard::confirm_remediate`; accept → `Remediate`, decline → the grep-stable
/// `[REMEDIATE-NN] DECLINED by user …` marker + `ReuseWithWarning` (the step layer
/// renders `[REUSE-WARN]` and leaves the drifted state untouched).
fn prompt_component(component: &str, marker: &str, description: &str) -> Resolution {
    if crate::provision::wizard::confirm_remediate(component, description) {
        Resolution::Remediate
    } else {
        eprintln!(
            "[{marker}] DECLINED by user — skipping {component}; install continues \
             (state will be marked reused-with-warning)"
        );
        Resolution::ReuseWithWarning
    }
}

/// `flush_bails_or_continue`: if any bail was aggregated,
/// print every `[BAIL]` line + the exit-code footer and `exit 65` (EX_DATAERR)
/// — SHORT-CIRCUITING before the step loop so a refused host is never mutated.
/// Returns normally (continue) when there are no bails.
pub fn flush_or_exit(bails: &[Bail]) {
    if bails.is_empty() {
        return;
    }
    for b in bails {
        eprintln!(
            "[BAIL] component={} reason={} hint={}",
            b.component, b.reason, b.hint
        );
    }
    eprintln!(
        "Exit code 65 (EX_DATAERR — incompatible host state). Re-run with --yes to remediate, \
         or see agentlinux provision --help."
    );
    std::process::exit(65);
}

#[cfg(test)]
mod remediate_tests {
    use super::*;

    /// The full consent matrix for a state-overwriting remediation.
    #[test]
    fn overwrite_consent_matrix() {
        // --yes always proceeds, TTY or not.
        assert_eq!(consent_for_overwrite(true, false), Consent::Proceed);
        assert_eq!(consent_for_overwrite(true, true), Consent::Proceed);
        // No --yes: a TTY asks, a non-TTY refuses.
        assert_eq!(consent_for_overwrite(false, true), Consent::Prompt);
        assert_eq!(consent_for_overwrite(false, false), Consent::Bail);
    }

    #[test]
    fn sudoers_decide_matrix() {
        let settled = |o| match o {
            CoreOutcome::Settled(r) => r,
            CoreOutcome::NeedsPrompt => panic!("expected a settled outcome"),
        };
        assert_eq!(
            settled(decide_sudoers(SudoersState::Absent, false, false).0),
            Resolution::Create
        );
        assert_eq!(
            settled(decide_sudoers(SudoersState::Canonical, false, false).0),
            Resolution::Reuse
        );
        // drifted + --yes → overwrite; no bail.
        let (o, b) = decide_sudoers(SudoersState::Drifted, true, false);
        assert_eq!(settled(o), Resolution::Remediate);
        assert!(b.is_none());
        // drifted + TTY, no --yes → the caller owes a prompt; no bail.
        let (o, b) = decide_sudoers(SudoersState::Drifted, false, true);
        assert_eq!(o, CoreOutcome::NeedsPrompt);
        assert!(b.is_none());
        // drifted + non-TTY no --yes → Bail with the exact component/reason.
        let (o, b) = decide_sudoers(SudoersState::Drifted, false, false);
        assert_eq!(settled(o), Resolution::Bail);
        let b = b.unwrap();
        assert_eq!(b.component, "sudoers");
        assert_eq!(b.reason, "drift");
    }

    #[test]
    fn npm_prefix_decide_matrix() {
        let settled = |o| match o {
            CoreOutcome::Settled(r) => r,
            CoreOutcome::NeedsPrompt => panic!("expected a settled outcome"),
        };
        assert_eq!(
            settled(decide_npm_prefix(NpmPrefixState::Absent, false, false).0),
            Resolution::Create
        );
        assert_eq!(
            settled(decide_npm_prefix(NpmPrefixState::OwnedByUser, false, false).0),
            Resolution::Reuse
        );
        let (o, b) = decide_npm_prefix(NpmPrefixState::WrongOwner, true, false);
        assert_eq!(settled(o), Resolution::Remediate);
        assert!(b.is_none());
        let (o, b) = decide_npm_prefix(NpmPrefixState::WrongOwner, false, true);
        assert_eq!(o, CoreOutcome::NeedsPrompt);
        assert!(b.is_none());
        let (o, b) = decide_npm_prefix(NpmPrefixState::WrongOwner, false, false);
        assert_eq!(settled(o), Resolution::Bail);
        assert_eq!(b.unwrap().component, "npm-prefix");
    }
}
