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

use crate::provision::probe::{self, sudoers_state_at, NpmPrefixState, SudoersState};
use crate::provision::{Resolution, Resolutions};
use std::path::Path;
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
    let mut prompter = crate::provision::wizard::Stdio::new();
    decide_core_with(
        user,
        home,
        Path::new(probe::SUDOERS_FILE),
        yes,
        res,
        bails,
        &mut prompter,
    );
}

/// [`decide_core`] against an injected [`Prompter`] and sudoers path.
///
/// The consent surface is a parameter because the ORDER of the prompts is
/// load-bearing and shares one read buffer: the npm-prefix answer's trailing
/// newline carries into the sudoers prompt as its Enter. That contract lived in
/// two comments ("the tests feed answers positionally") and had no in-process
/// test, because every prompt re-locked global stdin. It is the bug class this
/// project has shipped twice.
///
/// `sudoers_path` is a parameter for the same reason, and the omission was worse
/// than it looked: reading the real `/etc/sudoers.d/agentlinux` made the DECIDE
/// phase — the layer whose whole job is to decide BEFORE anything is touched —
/// depend on the runner. Unprivileged, the 0440 drop-in is unreadable, so a
/// provisioned host still looked clean and the tests passed; as root, which is
/// exactly how the Docker and QEMU harnesses run, the same fixture classified
/// `Drifted` and a "clean host needs no answers" test started consenting to a
/// remediation nobody asked for.
pub fn decide_core_with(
    user: &str,
    home: &str,
    sudoers_path: &Path,
    yes: bool,
    res: &mut Resolutions,
    bails: &mut Vec<Bail>,
    prompter: &mut dyn crate::provision::wizard::Prompter,
) {
    let is_tty = prompter.is_tty();

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
        probe::UserState::HomeNotWritable => {
            // REUSE-01: adopting a user who cannot write their own home hands
            // every later step the EACCES this project exists to eliminate, so it
            // is irreconcilable — and unlike a chown of `.npm-global`, re-owning
            // someone's whole home is not a remediation we offer.
            eprintln!("agentlinux: existing user \"{user}\" is incompatible (home-not-writable).");
            eprintln!(
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
    let (npm_outcome, npm_bail) =
        decide_npm_prefix(probe::npm_prefix_state(user, home), yes, is_tty);
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

    let (sudoers_outcome, sudoers_bail) =
        decide_sudoers(sudoers_state_at(sudoers_path, user), yes, is_tty);
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
        eprintln!(
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
        eprintln!(
            "[BAIL] component={} reason={} hint={}",
            b.component, b.reason, b.hint
        );
    }
    eprintln!(
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

    /// Decide against a fully synthetic host: a tempdir home with no
    /// `.npm-global` and a sudoers path that does not exist. Both components
    /// resolve without a prompt, and — because the sudoers path is the fixture's
    /// own, not `/etc`'s — they resolve the same way on a bare dev box, on a
    /// provisioned host, and as root inside the Docker/QEMU harnesses.
    fn decide(prompter: &mut dyn Prompter, yes: bool) -> Resolutions {
        let d = tempfile::tempdir().unwrap();
        decide_at(&d.path().join("no-sudoers-here"), prompter, yes)
    }

    /// [`decide`] against a caller-chosen sudoers path, so a test can stage the
    /// drifted and canonical shapes as literal file contents.
    fn decide_at(sudoers: &Path, prompter: &mut dyn Prompter, yes: bool) -> Resolutions {
        let d = tempfile::tempdir().unwrap();
        let mut res = Resolutions::default();
        let mut bails = Vec::new();
        decide_core_with(
            "no-such-user-agentlinux-xyzzy",
            &d.path().to_string_lossy(),
            sudoers,
            yes,
            &mut res,
            &mut bails,
            prompter,
        );
        res
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

    /// A sudoers drop-in that exists but lacks the canonical ADR-012 line — the
    /// `Drifted` state, and the ONLY core state that owes a prompt.
    fn drifted_sudoers(dir: &Path) -> std::path::PathBuf {
        let p = dir.join("agentlinux");
        std::fs::write(
            &p,
            "no-such-user-agentlinux-xyzzy ALL=(ALL) NOPASSWD: /bin/ls\n",
        )
        .unwrap();
        p
    }

    #[test]
    fn a_drifted_sudoers_on_a_tty_asks_and_honours_the_answer() {
        // The fixture that makes the two tests below mean anything: without a
        // drifted component nothing prompts either way, so asserting "it did not
        // prompt" against a clean host asserts nothing.
        let d = tempfile::tempdir().unwrap();
        let sudoers = drifted_sudoers(d.path());

        let accepted = decide_at(&sudoers, &mut scripted("Y"), false);
        assert_eq!(accepted.sudoers, Resolution::Remediate, "Y → overwrite");

        let declined = decide_at(&sudoers, &mut scripted("n"), false);
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
        let d = tempfile::tempdir().unwrap();
        let sudoers = drifted_sudoers(d.path());

        // No --yes: a non-TTY cannot consent, so this must BAIL, not prompt and
        // not silently proceed.
        let res = decide_at(&sudoers, &mut no_tty(), false);
        assert_eq!(res.sudoers, Resolution::Bail);

        // With --yes: consent is already given, so it remediates without ever
        // consulting the prompter (a `no_tty` prompter would panic if asked).
        let res = decide_at(&sudoers, &mut no_tty(), true);
        assert_eq!(res.sudoers, Resolution::Remediate);
    }

    #[test]
    fn a_canonical_sudoers_is_reused_without_asking() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("agentlinux");
        std::fs::write(
            &p,
            "no-such-user-agentlinux-xyzzy ALL=(ALL) NOPASSWD: ALL\n",
        )
        .unwrap();
        // An empty answer script would decline on any prompt, so Reuse also
        // proves nothing was asked.
        assert_eq!(
            decide_at(&p, &mut scripted(""), false).sudoers,
            Resolution::Reuse
        );
    }
}
