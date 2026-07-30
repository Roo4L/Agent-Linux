//! provision/remediate.rs — the CORE-COMPONENT brownfield DECIDE + consent/bail
//! gate. Port of `plugin/lib/remediate.sh`'s `collect_all_decisions` /
//! `gate_or_bail` / `flush_bails_or_continue` for the two core components the Rust
//! provisioner remediates: the npm-global prefix (REMEDIATE-01) and the sudoers
//! drop-in (REMEDIATE-03). Per-agent (REMEDIATE-04) + user (REUSE-01) decisions
//! live in the `from_decide` agent loop / `agent_user` step.
//!
//! DECIDE-THEN-ACT (remediate.sh:6-13): `decide_core` probes host state and writes
//! `Resolution` tokens with ZERO mutation; a state-overwriting Remediate WITHOUT
//! consent registers a `Bail`. `flush_or_exit` then prints every `[BAIL]` line and
//! exit 65 (EX_DATAERR) BEFORE the step loop — so a refused host is left
//! byte-identical (the NO-MUTATION-SNAPSHOT contract).
//!
//! Consent policy (remediate.sh `remediate_action_overwrites_state`): additive
//! actions (a missing-file install) run unconditionally; state-OVERWRITING actions
//! (npm-prefix chown/rebase, sudoers drift overwrite) need `--yes`, else — on a
//! TTY — the interactive prompt, else a bail. The real curl-installer path passes
//! `--yes` and is greenfield, so it never bails and never prompts.

use crate::provision::probe::{self, NpmPrefixState, SudoersState};
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

/// `remediate_action_overwrites_state` (remediate.sh:174-189): the two core
/// state-overwriting actions require consent; anything else is additive.
#[must_use]
pub fn action_overwrites_state(action: &str) -> bool {
    matches!(
        action,
        "npm-prefix-chown" | "npm-prefix-rebase" | "sudoers-drift-overwrite"
    )
}

/// `remediate::gate_or_bail` policy (remediate.sh:194-227), PURE. Additive → Proceed;
/// state-overwriting → Proceed on `--yes`, Prompt on a TTY, else Bail.
#[must_use]
pub fn gate(action: &str, yes: bool, is_tty: bool) -> Consent {
    if !action_overwrites_state(action) {
        return Consent::Proceed;
    }
    if yes {
        return Consent::Proceed;
    }
    if is_tty {
        return Consent::Prompt;
    }
    Consent::Bail
}

/// The `sudoers` token from its probed state + consent. Returns the resolution and,
/// when a drift overwrite is refused non-interactively, the bail to aggregate.
/// PURE (state + flags in, decision out).
#[must_use]
pub fn decide_sudoers(state: SudoersState, yes: bool, is_tty: bool) -> (Resolution, Option<Bail>) {
    match state {
        SudoersState::Absent => (Resolution::Create, None),
        SudoersState::Canonical => (Resolution::Reuse, None),
        SudoersState::Drifted => match gate("sudoers-drift-overwrite", yes, is_tty) {
            Consent::Proceed => (Resolution::Remediate, None),
            Consent::Prompt => (Resolution::Remediate, None), // caller prompts; default proceed
            Consent::Bail => (
                Resolution::Bail,
                Some(Bail {
                    component: "sudoers",
                    reason: "drift",
                    hint: "run with --yes to overwrite with the canonical ADR-012 line",
                }),
            ),
        },
    }
}

/// The `npm-prefix` token from its probed state + consent. PURE.
#[must_use]
pub fn decide_npm_prefix(
    state: NpmPrefixState,
    yes: bool,
    is_tty: bool,
) -> (Resolution, Option<Bail>) {
    match state {
        NpmPrefixState::Absent => (Resolution::Create, None),
        NpmPrefixState::OwnedByUser => (Resolution::Reuse, None),
        NpmPrefixState::WrongOwner => match gate("npm-prefix-chown", yes, is_tty) {
            Consent::Proceed => (Resolution::Remediate, None),
            Consent::Prompt => (Resolution::Remediate, None),
            Consent::Bail => (
                Resolution::Bail,
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
    decide_core_with(user, home, yes, res, bails, &mut prompter);
}

/// [`decide_core`] against an injected [`Prompter`].
///
/// The consent surface is a parameter because the ORDER of the prompts is
/// load-bearing and shares one read buffer: the npm-prefix answer's trailing
/// newline carries into the sudoers prompt as its Enter. That contract lived in
/// two comments ("the tests feed answers positionally") and had no in-process
/// test, because every prompt re-locked global stdin. It is the bug class this
/// project has shipped twice.
pub fn decide_core_with(
    user: &str,
    home: &str,
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

    // Component prompt order (prompt::run_all): npm-prefix BEFORE sudoers. This is
    // load-bearing — the tests feed answers positionally (e.g. `n\nY\n` = decline
    // npm-prefix, accept sudoers).
    let npm_state = probe::npm_prefix_state(user, home);
    let (mut npm_res, npm_bail) = decide_npm_prefix(npm_state, yes, is_tty);
    if npm_state == NpmPrefixState::WrongOwner && !yes && is_tty {
        npm_res = prompt_component(
            prompter,
            "npm-prefix",
            "REMEDIATE-01",
            &format!("chown ~{user}/.npm-global to {user}:{user}"),
        );
    }
    res.npm_prefix = npm_res;
    if let Some(b) = npm_bail {
        bails.push(b);
    }

    let sudoers_state = probe::sudoers_state(user);
    let (mut sudoers_res, sudoers_bail) = decide_sudoers(sudoers_state, yes, is_tty);
    if sudoers_state == SudoersState::Drifted && !yes && is_tty {
        sudoers_res = prompt_component(
            prompter,
            "sudoers",
            "REMEDIATE-03",
            "overwrite /etc/sudoers.d/agentlinux with canonical ADR-012 line",
        );
    }
    res.sudoers = sudoers_res;
    if let Some(b) = sudoers_bail {
        bails.push(b);
    }
}

/// Interactive consent for one state-overwriting remediation (TTY path only —
/// `provision --yes` and non-TTY never reach here). Delegates the `[Y/n]` prompt
/// to `wizard::confirm_remediate`; accept → `Remediate`, decline → the grep-stable
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

    #[test]
    fn additive_action_never_needs_consent() {
        assert!(!action_overwrites_state("sudoers-missing-install"));
        assert!(!action_overwrites_state("path-wiring"));
        assert_eq!(
            gate("sudoers-missing-install", false, false),
            Consent::Proceed
        );
    }

    #[test]
    fn overwriting_action_gate_matrix() {
        // --yes always proceeds; TTY prompts; non-TTY-no-yes bails.
        assert_eq!(
            gate("sudoers-drift-overwrite", true, false),
            Consent::Proceed
        );
        assert_eq!(
            gate("sudoers-drift-overwrite", true, true),
            Consent::Proceed
        );
        assert_eq!(gate("npm-prefix-chown", false, true), Consent::Prompt);
        assert_eq!(gate("npm-prefix-chown", false, false), Consent::Bail);
    }

    #[test]
    fn sudoers_decide_matrix() {
        assert_eq!(
            decide_sudoers(SudoersState::Absent, false, false).0,
            Resolution::Create
        );
        assert_eq!(
            decide_sudoers(SudoersState::Canonical, false, false).0,
            Resolution::Reuse
        );
        // drifted + --yes → overwrite; no bail.
        let (r, b) = decide_sudoers(SudoersState::Drifted, true, false);
        assert_eq!(r, Resolution::Remediate);
        assert!(b.is_none());
        // drifted + non-TTY no --yes → Bail with the exact component/reason.
        let (r, b) = decide_sudoers(SudoersState::Drifted, false, false);
        assert_eq!(r, Resolution::Bail);
        let b = b.unwrap();
        assert_eq!(b.component, "sudoers");
        assert_eq!(b.reason, "drift");
    }

    #[test]
    fn npm_prefix_decide_matrix() {
        assert_eq!(
            decide_npm_prefix(NpmPrefixState::Absent, false, false).0,
            Resolution::Create
        );
        assert_eq!(
            decide_npm_prefix(NpmPrefixState::OwnedByUser, false, false).0,
            Resolution::Reuse
        );
        let (r, b) = decide_npm_prefix(NpmPrefixState::WrongOwner, true, false);
        assert_eq!(r, Resolution::Remediate);
        assert!(b.is_none());
        let (r, b) = decide_npm_prefix(NpmPrefixState::WrongOwner, false, false);
        assert_eq!(r, Resolution::Bail);
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

    fn decide(prompter: &mut dyn Prompter, yes: bool) -> Resolutions {
        // A tempdir home with no .npm-global and no sudoers drop-in is the
        // clean-host shape: both components resolve without a prompt.
        let d = tempfile::tempdir().unwrap();
        let mut res = Resolutions::seed_create();
        let mut bails = Vec::new();
        decide_core_with(
            "no-such-user-agentlinux-xyzzy",
            &d.path().to_string_lossy(),
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

    #[test]
    fn a_non_tty_never_prompts() {
        // The curl-installer path. With --yes absent this is where the bails come
        // from; with --yes it proceeds without consulting the prompter at all.
        let res = decide(&mut no_tty(), false);
        assert_eq!(res.sudoers, Resolution::Create);
        let res = decide(&mut no_tty(), true);
        assert_eq!(res.sudoers, Resolution::Create);
    }
}
