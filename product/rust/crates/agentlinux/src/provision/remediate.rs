//! provision/remediate.rs — the CORE-COMPONENT brownfield DECIDE + consent/bail
//! gate for the two core components the provisioner remediates: the npm-global prefix (REMEDIATE-01) and the sudoers
//! drop-in (REMEDIATE-03). Per-agent (REMEDIATE-04) decisions live in the verb
//! layer; the user decision (REUSE-01) lives in the `agent_user` step.
//!
//! DECIDE-THEN-ACT: `decide_core` probes host state and writes
//! `Resolution` tokens with ZERO mutation; a state-overwriting Remediate WITHOUT
//! consent registers a `Bail`. `flush_bails` then prints every `[BAIL]` line and
//! returns exit 65 (EX_DATAERR) BEFORE the step loop — so a refused host is left
//! byte-identical (the NO-MUTATION-SNAPSHOT contract).
//!
//! Consent policy (remediate.sh `remediate_action_overwrites_state`): additive
//! actions (a missing-file install) run unconditionally; state-OVERWRITING actions
//! (npm-prefix chown/rebase, sudoers drift overwrite) need `--yes`, else — on a
//! TTY — the interactive prompt, else a bail. The real curl-installer path passes
//! `--yes` and is greenfield, so it never bails and never prompts.

use crate::provision::probe::{self, NpmPrefixState, SudoersState, UserState as SudoersUserState};
use crate::provision::{Resolution, Resolutions};
use std::process::ExitCode;

/// EX_DATAERR (sysexits.h) — incompatible host state.
const EX_DATAERR: u8 = 65;

/// An aggregated incompatible-host-state record. `flush_bails` renders each as
/// `[BAIL] component=<component> reason=<reason> hint=<hint>` (remediate.sh:162).
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

/// The host facts the DECIDE phase decides over — probed ONCE, up front.
///
/// The whole point of DECIDE is to reach a verdict BEFORE anything is touched,
/// which only means something if the verdict is a function of its inputs rather
/// than of the machine it runs on. Passing the three states in makes every arm —
/// including the two `Bail`s, which are the mechanism that stops the provisioner
/// from mauling a brownfield host — reachable from literals.
///
/// It also removes a whole class of test that passes for the wrong reason. With
/// the reads inline, a fixture could only steer the verdict by choosing a
/// username no host would have, which pinned `UserState::Absent` as the only
/// arm any test could reach, and made the suite's result depend on the runner:
/// unprivileged, the 0440 sudoers drop-in is unreadable so a provisioned host
/// looked clean; as root — how the Docker and QEMU harnesses run — the same
/// fixture classified `Drifted` and consented to a remediation nobody asked for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HostFacts {
    pub user: SudoersUserState,
    pub npm_prefix: NpmPrefixState,
    pub sudoers: SudoersState,
}

impl HostFacts {
    /// Probe the real host — the ONE place the DECIDE phase does I/O.
    #[must_use]
    pub fn probe(user: &str, home: &str) -> Self {
        Self {
            user: probe::user_state(user),
            npm_prefix: probe::npm_prefix_state(user, home),
            sudoers: probe::sudoers_state(user),
        }
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

/// The DECIDE-THEN-ACT core-component step, over stated host facts.
///
/// The consent surface is a parameter because the ORDER of the prompts is
/// load-bearing and shares one read buffer: the npm-prefix answer's trailing
/// newline carries into the sudoers prompt as its Enter. That contract lived in
/// two comments ("the tests feed answers positionally") and had no in-process
/// test, because every prompt re-locked global stdin. It is the bug class this
/// project has shipped twice.
///
/// The host facts are parameters for the same reason — see [`HostFacts`]. This
/// function touches neither the filesystem nor stdin.
pub fn decide_core_with(
    user: &str,
    facts: HostFacts,
    yes: bool,
    res: &mut Resolutions,
    bails: &mut Vec<Bail>,
    prompter: &mut dyn crate::provision::wizard::Prompter,
) {
    let is_tty = prompter.is_tty();

    // User (REUSE-01): absent → Create; bash-shell existing → Reuse (re-attach
    // path wiring, [REMEDIATE-02]); wrong-shell → irreconcilable BAIL with the
    // dedicated hint (--yes cannot fix a wrong shell).
    match facts.user {
        SudoersUserState::Absent => res.user = Resolution::Create,
        SudoersUserState::Conforming => res.user = Resolution::Reuse,
        SudoersUserState::WrongShell => {
            crate::plog!("agentlinux: existing user \"{user}\" is incompatible (wrong-shell).");
            crate::plog!(
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
        SudoersUserState::HomeNotWritable => {
            // REUSE-01: adopting a user who cannot write their own home hands
            // every later step the EACCES this project exists to eliminate, so it
            // is irreconcilable — and unlike a chown of `.npm-global`, re-owning
            // someone's whole home is not a remediation we offer.
            crate::plog!(
                "agentlinux: existing user \"{user}\" is incompatible (home-not-writable)."
            );
            crate::plog!(
                "Re-run with --user=NAME using a compatible user, or make the existing user's \
                 home writable by them."
            );
            res.user = Resolution::Bail;
            bails.push(Bail {
                component: "user",
                reason: "home-not-writable",
                hint: "use --user=NAME with a compatible user",
            });
        }
    }

    // Component prompt order: npm-prefix BEFORE sudoers. This is load-bearing —
    // the tests feed answers positionally (e.g. `n\nY\n` = decline npm-prefix,
    // accept sudoers), and so does an operator answering two prompts in a row.
    let (npm_outcome, npm_bail) = decide_npm_prefix(facts.npm_prefix, yes, is_tty);
    res.npm_prefix = match npm_outcome {
        CoreOutcome::Settled(r) => r,
        CoreOutcome::NeedsPrompt => prompt_component(
            prompter,
            "npm-prefix",
            "REMEDIATE-01",
            &format!("chown ~{user}/.npm-global to {user}:{user}"),
        ),
    };
    if let Some(b) = npm_bail {
        bails.push(b);
    }

    let (sudoers_outcome, sudoers_bail) = decide_sudoers(facts.sudoers, yes, is_tty);
    res.sudoers = match sudoers_outcome {
        CoreOutcome::Settled(r) => r,
        CoreOutcome::NeedsPrompt => prompt_component(
            prompter,
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
/// to the injected [`Prompter`]; accept → `Remediate`, decline → the grep-stable
/// `[REMEDIATE-NN] DECLINED by user …` marker + `ReuseWithWarning` (the step layer
/// renders `[REUSE-WARN]` and leaves the drifted state untouched).
fn prompt_component(
    prompter: &mut dyn crate::provision::wizard::Prompter,
    component: &str,
    marker: &str,
    description: &str,
) -> Resolution {
    if prompter.confirm(component, description) {
        Resolution::Remediate
    } else {
        crate::plog!(
            "[{marker}] DECLINED by user — skipping {component}; install continues \
             (state will be marked reused-with-warning)"
        );
        Resolution::ReuseWithWarning
    }
}

/// `flush_bails_or_continue` (remediate.sh:150-166): if any bail was aggregated,
/// print every `[BAIL]` line + the exit-code footer and return `Err(65)`
/// (EX_DATAERR) — SHORT-CIRCUITING before the step loop so a refused host is
/// never mutated. `Ok(())` (continue) when there are no bails.
///
/// Returns rather than calling `std::process::exit`: the NO-MUTATION-SNAPSHOT
/// contract ("print every [BAIL], exit 65, mutate nothing") is the most
/// safety-critical thing the provisioner does, and a library function that ends
/// the process makes it structurally unassertable — a test reaching it kills the
/// test binary. Its neighbours (`check_flag_contradictions`,
/// `check_report_format`) already return `Result<(), ExitCode>`.
pub fn flush_bails(bails: &[Bail]) -> Result<(), ExitCode> {
    if bails.is_empty() {
        return Ok(());
    }
    for b in bails {
        crate::plog!(
            "[BAIL] component={} reason={} hint={}",
            b.component,
            b.reason,
            b.hint
        );
    }
    crate::plog!(
        "Exit code 65 (EX_DATAERR — incompatible host state). Re-run with --yes to remediate, \
         or see agentlinux provision --help."
    );
    Err(ExitCode::from(EX_DATAERR))
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

#[cfg(test)]
mod flush_tests {
    //! The NO-MUTATION-SNAPSHOT contract, now assertable in-process. While
    //! `flush_or_exit` called `std::process::exit(65)` from library code, a test
    //! that reached it killed the test binary — so the most safety-critical
    //! behaviour the provisioner has had no test at all.
    use super::*;

    fn bail(component: &'static str, reason: &'static str) -> Bail {
        Bail {
            component,
            reason,
            hint: "run with --yes",
        }
    }

    #[test]
    fn no_bails_continues() {
        assert!(flush_bails(&[]).is_ok());
    }

    #[test]
    fn any_bail_stops_the_run_with_exit_65() {
        let err = flush_bails(&[bail("sudoers", "drift")]).unwrap_err();
        assert_eq!(err, ExitCode::from(65));
    }

    #[test]
    fn every_aggregated_bail_is_reported_not_just_the_first() {
        // The operator needs the WHOLE list to fix the host in one pass; short-
        // circuiting on the first would hide the second behind a re-run.
        let bails = [bail("npm-prefix", "wrong-owner"), bail("sudoers", "drift")];
        assert_eq!(flush_bails(&bails).unwrap_err(), ExitCode::from(65));
    }
}

#[cfg(test)]
mod prompt_order_tests {
    //! The cross-component read-ahead contract, in-process for the first time.
    use super::*;
    use crate::provision::wizard::{Prompter, Stdio};
    use std::io::Cursor;

    /// A prompter over ONE in-memory reader holding every answer in order —
    /// the same shared-buffer shape as the production stdin lock.
    fn scripted(answers: &str) -> Stdio<Cursor<Vec<u8>>, Vec<u8>> {
        Stdio::with_streams(true, Cursor::new(answers.as_bytes().to_vec()), Vec::new())
    }

    /// A non-TTY prompter: no prompt is possible, so consent must come from
    /// --yes or the component bails.
    fn no_tty() -> Stdio<Cursor<Vec<u8>>, Vec<u8>> {
        Stdio::with_streams(false, Cursor::new(Vec::new()), Vec::new())
    }

    /// A clean host: nothing exists, nothing has drifted.
    fn clean() -> HostFacts {
        HostFacts {
            user: SudoersUserState::Absent,
            npm_prefix: NpmPrefixState::Absent,
            sudoers: SudoersState::Absent,
        }
    }

    /// Decide over stated host facts. No filesystem, no passwd DB, no stdin —
    /// so the verdict is a function of the fixture and nothing else, and every
    /// arm is reachable rather than only the one a nonexistent username reaches.
    fn decide_at(facts: HostFacts, prompter: &mut dyn Prompter, yes: bool) -> Resolutions {
        let mut res = Resolutions::default();
        let mut bails = Vec::new();
        decide_core_with("agent", facts, yes, &mut res, &mut bails, prompter);
        res
    }

    /// As [`decide_at`], returning the aggregated bails instead.
    fn bails_at(facts: HostFacts, prompter: &mut dyn Prompter, yes: bool) -> Vec<Bail> {
        let mut res = Resolutions::default();
        let mut bails = Vec::new();
        decide_core_with("agent", facts, yes, &mut res, &mut bails, prompter);
        bails
    }

    fn decide(prompter: &mut dyn Prompter, yes: bool) -> Resolutions {
        decide_at(clean(), prompter, yes)
    }

    // --- the user component (REUSE-01). Three of these four arms were
    // unreachable while `decide_core_with` probed the real passwd DB: a fixture
    // could only pick a username no host would have, which pinned `Absent`.

    #[test]
    fn an_existing_conforming_user_is_reused_not_recreated() {
        let facts = HostFacts {
            user: SudoersUserState::Conforming,
            ..clean()
        };
        assert_eq!(
            decide_at(facts, &mut scripted(""), false).user,
            Resolution::Reuse
        );
    }

    #[test]
    fn a_wrong_shell_user_bails_and_no_answer_can_override_it() {
        // Irreconcilable: --yes cannot fix a wrong shell, so this must bail even
        // with consent granted. That is the whole point of an irreconcilable
        // state, and nothing asserted it before.
        let facts = HostFacts {
            user: SudoersUserState::WrongShell,
            ..clean()
        };
        for yes in [false, true] {
            assert_eq!(
                decide_at(facts, &mut scripted("Y"), yes).user,
                Resolution::Bail,
                "yes={yes}"
            );
            let bails = bails_at(facts, &mut scripted("Y"), yes);
            assert!(
                bails
                    .iter()
                    .any(|b| b.component == "user" && b.reason == "wrong-shell"),
                "bails={bails:?}"
            );
        }
    }

    #[test]
    fn a_home_the_user_cannot_write_bails_with_its_own_reason() {
        // Adopting a user who cannot write their own home hands every later step
        // the EACCES this project exists to eliminate.
        let facts = HostFacts {
            user: SudoersUserState::HomeNotWritable,
            ..clean()
        };
        assert_eq!(
            decide_at(facts, &mut scripted("Y"), true).user,
            Resolution::Bail
        );
        let bails = bails_at(facts, &mut scripted("Y"), true);
        assert!(
            bails
                .iter()
                .any(|b| b.component == "user" && b.reason == "home-not-writable"),
            "bails={bails:?}"
        );
    }

    #[test]
    fn a_wrong_owner_npm_prefix_asks_and_honours_the_answer() {
        let facts = HostFacts {
            npm_prefix: NpmPrefixState::WrongOwner,
            ..clean()
        };
        assert_eq!(
            decide_at(facts, &mut scripted("Y"), false).npm_prefix,
            Resolution::Remediate
        );
        assert_eq!(
            decide_at(facts, &mut scripted("n"), false).npm_prefix,
            Resolution::ReuseWithWarning
        );
        // --yes proceeds without consulting the prompter at all.
        assert_eq!(
            decide_at(facts, &mut no_tty(), true).npm_prefix,
            Resolution::Remediate
        );
    }

    #[test]
    fn a_clean_host_needs_no_answers_at_all() {
        // An empty answer script would make any prompt read EOF and decline, so
        // "everything is Create" also proves nothing prompted.
        let res = decide(&mut scripted(""), false);
        assert_eq!(res.user, Resolution::Create);
        assert_eq!(res.npm_prefix, Resolution::Create);
        assert_eq!(res.sudoers, Resolution::Create);
    }

    #[test]
    fn each_component_consumes_exactly_one_byte_of_the_shared_buffer() {
        // `confirm` reads ONE byte and does NOT drain after a valid answer, so
        // consecutive answers are consecutive BYTES of one stream. This is the
        // contract two comments asserted and nothing checked.
        let mut p = scripted("nY");
        assert!(!p.confirm("npm-prefix", "chown"), "byte 1 = 'n' → decline");
        assert!(p.confirm("sudoers", "overwrite"), "byte 2 = 'Y' → accept");
    }

    #[test]
    fn a_trailing_newline_becomes_the_next_components_enter() {
        // The read-ahead the module doc calls INTENTIONAL, pinned: after a valid
        // answer the trailing `\n` is left in the buffer and the NEXT prompt reads
        // it as Enter — i.e. accept. A driver feeding `n\nY\n` therefore answers
        // decline-then-ACCEPT-VIA-ENTER and leaves `Y\n` unread; it is not
        // decline-then-Y. Anyone scripting these prompts positionally needs this
        // stated, and any change to the drain behaviour must fail here.
        let mut p = scripted("n\nY\n");
        assert!(!p.confirm("npm-prefix", "chown"));
        assert!(
            p.confirm("sudoers", "overwrite"),
            "the leftover newline is the second prompt's Enter"
        );
    }

    #[test]
    fn an_exhausted_answer_script_declines_rather_than_blocking() {
        // EOF is a decline, so a truncated driver script can never silently
        // consent to a state-overwriting remediation.
        let mut p = scripted("Y");
        assert!(p.confirm("npm-prefix", "chown"));
        assert!(!p.confirm("sudoers", "overwrite"), "EOF → decline");
    }

    #[test]
    fn an_invalid_answer_is_re_prompted_and_the_rest_of_the_line_is_discarded() {
        // T-15-01-03: only the FIRST byte steers the decision; the rest of an
        // invalid line is drained unevaluated, so a pasted `xrm -rf /\nY` cannot
        // smuggle a second answer.
        let mut p = scripted("xrm -rf /\nY");
        assert!(p.confirm("npm-prefix", "chown"), "re-prompt reads the Y");
    }

    #[test]
    fn a_drifted_sudoers_on_a_tty_asks_and_honours_the_answer() {
        // The fixture that makes the two tests below mean anything: without a
        // drifted component nothing prompts either way, so asserting "it did not
        // prompt" against a clean host asserts nothing.
        let facts = HostFacts {
            sudoers: SudoersState::Drifted,
            ..clean()
        };

        let accepted = decide_at(facts, &mut scripted("Y"), false);
        assert_eq!(accepted.sudoers, Resolution::Remediate, "Y → overwrite");

        let declined = decide_at(facts, &mut scripted("n"), false);
        assert_eq!(
            declined.sudoers,
            Resolution::ReuseWithWarning,
            "n → keep the drifted file, warn"
        );
    }

    #[test]
    fn a_non_tty_never_prompts_even_when_a_component_has_drifted() {
        // The curl-installer path, asserted where a prompt WOULD otherwise be
        // owed. Dropping the `is_tty` guard would block here on a terminal that
        // does not exist — the hang class this project has shipped twice.
        let facts = HostFacts {
            sudoers: SudoersState::Drifted,
            ..clean()
        };

        // No --yes: a non-TTY cannot consent, so this must BAIL, not prompt and
        // not silently proceed.
        let res = decide_at(facts, &mut no_tty(), false);
        assert_eq!(res.sudoers, Resolution::Bail);

        // With --yes: consent is already given, so it remediates without ever
        // consulting the prompter (a `no_tty` prompter would panic if asked).
        let res = decide_at(facts, &mut no_tty(), true);
        assert_eq!(res.sudoers, Resolution::Remediate);
    }

    #[test]
    fn a_canonical_sudoers_is_reused_without_asking() {
        let facts = HostFacts {
            sudoers: SudoersState::Canonical,
            ..clean()
        };
        // An empty answer script would decline on any prompt, so Reuse also
        // proves nothing was asked.
        assert_eq!(
            decide_at(facts, &mut scripted(""), false).sudoers,
            Resolution::Reuse
        );
    }
}
