//! provision/wizard.rs — interactive TTY prompts ported from the deleted Bash
//! The provisioner is flag-driven by default; these
//! prompts fire ONLY on an interactive terminal when the corresponding flag is
//! absent, so the curl-installer path (`provision --user agent --yes`, non-TTY)
//! stays fully non-interactive.
//!
//! AL-50 AC3: `choose_install_user` is the general install-time prompt fired on
//! a greenfield host when no `--user` was given. It prints a short context block
//! then renders `Install AgentLinux under which user? [default: <name>]` and
//! reads a line. The `Install AgentLinux under which user?` substring is the
//! `tests/bats/helpers/tty-driver.py` PROMPT_SENTINELS gate — keep it verbatim.

use crate::provision::probe;
use std::io::{BufRead, IsTerminal, Write};

/// True when stdin is an interactive terminal (the wizard's guard). The
/// curl-installer pipes the installer over stdin → not a TTY → no prompt.
#[must_use]
/// Not mutation-tested: it asks the real process stdin whether it is a terminal
/// (ADR-019 §5). Every caller takes it as an injected `is_tty` dep precisely so
/// the branches behind it are reachable without one.
#[cfg_attr(test, mutants::skip)]
pub fn stdin_is_tty() -> bool {
    std::io::stdin().is_terminal()
}

/// Whether to fire the AL-50 "which user?" prompt: only on a host that has no
/// prior provision (no env-file) AND no brownfield flow of its own. A wrong-shell
/// user is handled by the alt-user gate; a drifted-sudoers / wrong-owner-npm host
/// is a REMEDIATE-consent flow — firing the user prompt first would swallow those
/// `[Y/n]` answers and desync the loop. On a clean host a fresh name is created
/// (or, if the default user already exists and is compatible, adopted after the
/// operator confirms/renames). Keying on the env-file ALONE mis-fired here: the
/// brownfield fixtures purge `/etc/agentlinux.env` but keep a pre-existing agent
/// user in a REMEDIATE/wrong-shell state, so the extra state checks are load-bearing.
#[must_use]
/// Not mutation-tested: a production wiring adapter (ADR-019 §5) — it reads the
/// real env-file path and the three live host probes. The decision it hands them
/// to is [`should_prompt_from`], which is pure and asserted directly.
#[cfg_attr(test, mutants::skip)]
pub fn should_prompt_install_user(user: &str, home: &str) -> bool {
    use crate::provision::probe::{npm_prefix_state, sudoers_state, user_state};
    should_prompt_from(
        std::path::Path::new(&crate::recipe_env::env_file_path()).exists(),
        user_state(user),
        sudoers_state(user),
        npm_prefix_state(user, home),
    )
}

/// The pure predicate behind [`should_prompt_install_user`] — the four host facts
/// in, the decision out. The mis-fire this replaced (keying on the env-file alone)
/// is a one-line test here instead of a fixture that has to manufacture a
/// brownfield host.
#[must_use]
pub fn should_prompt_from(
    env_file_exists: bool,
    user: crate::provision::probe::UserState,
    sudoers: crate::provision::probe::SudoersState,
    npm_prefix: crate::provision::probe::NpmPrefixState,
) -> bool {
    use crate::provision::probe::{NpmPrefixState, SudoersState, UserState};
    !env_file_exists
        // Both irreconcilable user states have their own flow (the alt-user gate
        // / the home-not-writable bail); prompting first would swallow their
        // answers.
        && matches!(user, UserState::Absent | UserState::Conforming)
        && sudoers != SudoersState::Drifted
        && npm_prefix != NpmPrefixState::WrongOwner
}

/// Testable core of the install-user prompt: render the context + prompt to
/// `err`, read a line from `input`. Empty (bare Enter), EOF, or a read error →
/// the default. A typed name is accepted only when `validate` passes; on invalid
/// input re-prompt up to 3 times then fall back to the default (never wedge).
/// Returns a name that has already passed `validate` (or the default).
pub fn choose_install_user_io<R: BufRead, W: Write>(
    default_user: &str,
    validate: &dyn Fn(&str) -> bool,
    mut input: R,
    mut err: W,
) -> String {
    let _ = writeln!(
        err,
        "This account runs your coding agents and is granted passwordless sudo."
    );
    let _ = writeln!(
        err,
        "A name that does not exist yet is created; an existing compatible user is adopted."
    );
    let _ = writeln!(
        err,
        "Details: https://github.com/Roo4L/Agent-Linux/blob/master/docs/install-user.md"
    );
    let mut tries = 0;
    while tries < 3 {
        // Keep "Install AgentLinux under which user?" verbatim — it is the
        // tty-driver.py prompt sentinel.
        let _ = write!(
            err,
            "Install AgentLinux under which user? [default: {default_user}] "
        );
        let _ = err.flush();
        let mut line = String::new();
        match input.read_line(&mut line) {
            Ok(0) | Err(_) => {
                // EOF / closed stdin → use the default rather than loop forever.
                let _ = writeln!(err);
                return default_user.to_string();
            }
            Ok(_) => {}
        }
        let response = line.trim_end_matches(['\n', '\r']);
        if response.is_empty() {
            return default_user.to_string();
        }
        if validate(response) {
            return response.to_string();
        }
        tries += 1;
        let _ = writeln!(
            err,
            "invalid name: {response:?} — must match ^[a-z][a-z0-9_-]*$ and not be root/a reserved account"
        );
    }
    default_user.to_string()
}

/// Prompt on stderr / read from stdin (stdout is reserved), returning the chosen
/// install user. Callers gate this behind `stdin_is_tty()` + `is_greenfield()` +
/// an absent `--user`.
/// Not mutation-tested: binds the real stdin/stderr (ADR-019 §5). The prompt
/// loop is [`choose_install_user_io`].
#[cfg_attr(test, mutants::skip)]
pub fn choose_install_user(default_user: &str, validate: &dyn Fn(&str) -> bool) -> String {
    let stdin = std::io::stdin();
    choose_install_user_io(default_user, validate, stdin.lock(), std::io::stderr())
}

// --- UX-02: per-component REMEDIATE consent prompt ---

/// Testable core of the remediation consent prompt. Renders
/// `Proceed with this remediation? [Y/n] (<component> — <description>) ` (the
/// leading substring is the tty-driver sentinel — keep it verbatim) and reads a
/// SINGLE byte: Enter(`\n`/`\r`)/`Y`/`y` → accept; `N`/`n` → decline; any other
/// char → drain the rest of that line and re-prompt (max 3 → decline); EOF →
/// decline. Single-byte-then-line-drain is the injection mitigation:
/// only the first char steers the decision, the rest of the line is discarded
/// unevaluated. NO drain after a valid answer — a trailing `\n` intentionally
/// falls through to the next component's prompt as its Enter/accept.
pub fn confirm_remediate_io<R: BufRead, W: Write>(
    component: &str,
    description: &str,
    mut input: R,
    mut err: W,
) -> bool {
    let mut tries = 0;
    while tries < 3 {
        let _ = write!(
            err,
            "Proceed with this remediation? [Y/n] ({component} — {description}) "
        );
        let _ = err.flush();
        let mut b = [0u8; 1];
        match input.read(&mut b) {
            Ok(0) | Err(_) => {
                let _ = writeln!(err);
                return false; // EOF / read error → default-decline
            }
            Ok(_) => {}
        }
        let _ = writeln!(err); // terminate the prompt line
        match b[0] {
            b'\n' | b'\r' | b'Y' | b'y' => return true,
            b'N' | b'n' => return false,
            other => {
                let _ = writeln!(
                    err,
                    "invalid response: {:?} — please answer Y or n",
                    other as char
                );
                // Discard the rest of the line (never eval'd). A `Ok(0)` here means
                // EOF arrived mid-drain — treat it as terminal (decline) rather than
                // looping to another read that would block forever on a half-closed
                // TTY (the driver only ever sends one EOF).
                let mut junk = Vec::new();
                match input.read_until(b'\n', &mut junk) {
                    Ok(0) => {
                        let _ = writeln!(err);
                        return false;
                    }
                    _ => tries += 1,
                }
            }
        }
    }
    false
}

/// The consent surface the DECIDE phase talks to: is this a terminal, and does
/// the operator accept this remediation?
///
/// A trait rather than two free functions because the invariant between the
/// prompts is a SHARED READ BUFFER. Each prompt reads a line; the answer to the
/// first carries its trailing newline through the same buffer into the second,
/// which is why the npm-prefix-before-sudoers order is load-bearing. With
/// `std::io::stdin()` re-locked per call that invariant was documented in two
/// comments and enforced by nothing — and a desync test (feed `n\nY\n`, expect
/// decline-then-accept) could not be written at all. The production `Stdio`
/// holds ONE reader for its lifetime, so the invariant is structural.
pub trait Prompter {
    /// Whether stdin is a terminal (no prompt is possible when it is not).
    fn is_tty(&self) -> bool;
    /// `[Y/n]` for one state-overwriting remediation.
    fn confirm(&mut self, component: &str, description: &str) -> bool;
}

/// The production prompter: one stdin reader, held for the whole DECIDE phase.
pub struct Stdio<R: BufRead, W: Write> {
    tty: bool,
    input: R,
    err: W,
}

impl Stdio<std::io::StdinLock<'static>, std::io::Stderr> {
    #[must_use]
    pub fn new() -> Self {
        Self {
            tty: stdin_is_tty(),
            input: std::io::stdin().lock(),
            err: std::io::stderr(),
        }
    }
}

impl<R: BufRead, W: Write> Stdio<R, W> {
    /// A prompter over supplied streams — the seam a test drives with an
    /// in-memory cursor holding EVERY answer, in order.
    #[cfg(test)]
    pub fn with_streams(tty: bool, input: R, err: W) -> Self {
        Self { tty, input, err }
    }
}

impl<R: BufRead, W: Write> Prompter for Stdio<R, W> {
    fn is_tty(&self) -> bool {
        self.tty
    }

    fn confirm(&mut self, component: &str, description: &str) -> bool {
        confirm_remediate_io(component, description, &mut self.input, &mut self.err)
    }
}

// --- UX-04: wrong-shell alt-user prompt (prompt::alt_user_or_bail) ---

/// First free `agent2..agent99` (remediate::find_alt_user_name), or `None` when
/// all are taken.
#[must_use]
/// Not mutation-tested: it probes the live passwd DB for every candidate
/// (ADR-019 §5), so its answer is a property of the host the tests run on. The
/// caller re-validates whatever it returns before use — see the
/// defence-in-depth note in [`alt_user_prompt_io`].
#[cfg_attr(test, mutants::skip)]
pub fn find_alt_user_name() -> Option<String> {
    (2..=99)
        .map(|n| format!("agent{n}"))
        .find(|name| !probe::user_exists(name))
}

/// The outcome of the alt-user prompt loop (pure — the caller maps it to a
/// process exit / a chosen name).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AltUser {
    /// Operator accepted the suggestion or typed a valid name.
    Chosen(String),
    /// EOF on the prompt → decline + exit 65.
    DeclinedEof,
    /// 3 invalid names → exit 64 (EX_USAGE).
    Exhausted,
}

/// Testable core of the alt-user prompt. With a `suggested` name, Enter accepts
/// it; a typed name is accepted iff `validate` passes; 3 invalid → `Exhausted`;
/// EOF → `DeclinedEof`. `Type a name for the new install user:` /
/// `or type another name:` are tty-driver sentinels — keep them verbatim.
pub fn alt_user_prompt_io<R: BufRead, W: Write>(
    suggested: Option<&str>,
    validate: &dyn Fn(&str) -> bool,
    mut input: R,
    mut err: W,
) -> AltUser {
    let mut tries = 0;
    while tries < 3 {
        match suggested {
            Some(s) => {
                let _ = write!(err, "Press Enter to use \"{s}\", or type another name: ");
            }
            None => {
                let _ = write!(err, "Type a name for the new install user: ");
            }
        }
        let _ = err.flush();
        let mut line = String::new();
        match input.read_line(&mut line) {
            Ok(0) | Err(_) => {
                let _ = writeln!(err);
                return AltUser::DeclinedEof;
            }
            Ok(_) => {}
        }
        // A line with no trailing newline means EOF was hit mid-line (the operator
        // closed the TTY without pressing Enter). Match the Bash `read` contract —
        // EOF → decline — rather than accept a half-typed name AND avoid a second
        // read that would block forever (the driver sends only one EOF).
        //
        // The old spelling also tested `n > 0`, which cannot be false here: a
        // zero-byte read is the `Ok(0)` arm above and already returned. `>` and
        // `>=` were therefore indistinguishable — an equivalent mutant guarding
        // nothing.
        if !line.ends_with('\n') {
            let _ = writeln!(err);
            return AltUser::DeclinedEof;
        }
        let response = line.trim_end_matches(['\n', '\r']);
        if response.is_empty() {
            // Enter accepts the suggestion — but re-validate it at the point of use
            // (defense-in-depth: never feed an unvalidated name to useradd/sudoers,
            // even one from find_alt_user_name, in case that generator ever changes).
            if let Some(s) = suggested {
                if validate(s) {
                    return AltUser::Chosen(s.to_string());
                }
            }
            // No suggestion / invalid suggestion + empty line → count as invalid.
        } else if validate(response) {
            return AltUser::Chosen(response.to_string());
        }
        tries += 1;
        let _ = writeln!(
            err,
            "invalid name: {response:?} — must match ^[a-z][a-z0-9_-]*$"
        );
    }
    AltUser::Exhausted
}

/// Prompt on stderr / read a line from stdin for the wrong-shell alternate user.
/// Gate behind TTY.
pub fn alt_user_prompt(suggested: Option<&str>, validate: &dyn Fn(&str) -> bool) -> AltUser {
    let stdin = std::io::stdin();
    alt_user_prompt_io(suggested, validate, stdin.lock(), std::io::stderr())
}

#[cfg(test)]
mod wizard_prompt_tests {
    use super::*;
    use std::io::Cursor;

    fn lower_only(n: &str) -> bool {
        !n.is_empty()
            && n.chars()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
    }

    #[test]
    fn confirm_enter_and_y_accept() {
        let mut e = Vec::new();
        assert!(confirm_remediate_io(
            "sudoers",
            "d",
            Cursor::new(b"\n"),
            &mut e
        ));
        assert!(confirm_remediate_io(
            "sudoers",
            "d",
            Cursor::new(b"Y"),
            &mut e
        ));
        assert!(confirm_remediate_io(
            "sudoers",
            "d",
            Cursor::new(b"y"),
            &mut e
        ));
        // The sentinel substring is present.
        assert!(String::from_utf8(e)
            .unwrap()
            .contains("Proceed with this remediation? [Y/n]"));
    }

    #[test]
    fn confirm_n_declines_and_eof_declines() {
        let mut e = Vec::new();
        assert!(!confirm_remediate_io(
            "npm-prefix",
            "d",
            Cursor::new(b"n"),
            &mut e
        ));
        assert!(!confirm_remediate_io(
            "npm-prefix",
            "d",
            Cursor::new(b""),
            &mut e
        ));
    }

    #[test]
    fn confirm_first_char_steers_rest_of_line_discarded() {
        // 'n' + injection on the same line: only 'n' is read; the rest is drained
        // on the NEXT read cycle by the caller. Here we assert 'n' → decline and
        // the leftover bytes are still in the reader (not consumed by a valid answer).
        let mut e = Vec::new();
        let mut cur = Cursor::new(b"n; rm -rf /tmp/poison\nY\n".to_vec());
        assert!(!confirm_remediate_io("npm-prefix", "d", &mut cur, &mut e));
        // Second prompt: ';' is invalid → drain line → 'Y' accepts.
        let mut e2 = Vec::new();
        assert!(confirm_remediate_io("sudoers", "d", &mut cur, &mut e2));
        assert!(String::from_utf8(e2).unwrap().contains("invalid response"));
    }

    #[test]
    fn confirm_three_invalid_declines() {
        let mut e = Vec::new();
        assert!(!confirm_remediate_io(
            "sudoers",
            "d",
            Cursor::new(b"a\nb\nc\nd\n"),
            &mut e
        ));
    }

    #[test]
    fn confirm_invalid_at_eof_without_newline_declines_not_hangs() {
        // A lone invalid char with no trailing newline: the single-byte read gets
        // 'x', the drain hits EOF (Ok(0)) → decline immediately (no second read).
        let mut e = Vec::new();
        assert!(!confirm_remediate_io(
            "sudoers",
            "d",
            Cursor::new(b"x"),
            &mut e
        ));
    }

    #[test]
    fn alt_user_partial_line_at_eof_declines() {
        // A typed name with no trailing newline (EOF mid-line) → DeclinedEof, not
        // an accepted half-typed name (Bash `read` EOF contract).
        assert_eq!(
            alt_user_prompt_io(
                Some("agent2"),
                &lower_only,
                Cursor::new(b"mybot"),
                &mut Vec::new()
            ),
            AltUser::DeclinedEof
        );
    }

    #[test]
    fn alt_user_enter_accepts_suggested() {
        let mut e = Vec::new();
        assert_eq!(
            alt_user_prompt_io(Some("agent2"), &lower_only, Cursor::new(b"\n"), &mut e),
            AltUser::Chosen("agent2".to_string())
        );
    }

    #[test]
    fn alt_user_typed_valid_and_eof_and_exhausted() {
        let mut e = Vec::new();
        assert_eq!(
            alt_user_prompt_io(Some("agent2"), &lower_only, Cursor::new(b"mybot\n"), &mut e),
            AltUser::Chosen("mybot".to_string())
        );
        assert_eq!(
            alt_user_prompt_io(
                Some("agent2"),
                &lower_only,
                Cursor::new(b""),
                &mut Vec::new()
            ),
            AltUser::DeclinedEof
        );
        // Three shell-metachar names → Exhausted.
        assert_eq!(
            alt_user_prompt_io(
                Some("agent2"),
                &lower_only,
                Cursor::new(b"a;b\nc;d\ne f\n"),
                &mut Vec::new()
            ),
            AltUser::Exhausted
        );
    }
}

#[cfg(test)]
mod wizard_tests {
    use super::*;

    /// Both retry loops give the operator exactly three attempts. `<` becoming
    /// `<=` grants a fourth, and `tries += 1` becoming `*=` never advances the
    /// counter at all — a prompt loop that only ends because stdin ran out.
    ///
    /// The RESULT is the same in every case (the default / a decline), so the
    /// only witness is how many times the prompt was written. That is what these
    /// assert.
    #[test]
    fn the_user_prompt_gives_exactly_three_attempts() {
        let input = std::io::Cursor::new(b"BAD-1\nBAD-2\nBAD-3\nBAD-4\nBAD-5\n".to_vec());
        let mut err = Vec::new();
        let chosen = choose_install_user_io("agent", &|name: &str| name == "good", input, &mut err);

        assert_eq!(chosen, "agent", "three strikes falls back to the default");
        let text = String::from_utf8(err).unwrap();
        assert_eq!(
            text.matches("Install AgentLinux under which user?").count(),
            3,
            "exactly three prompts — no more, no fewer:\n{text}"
        );
        assert_eq!(
            text.matches("invalid name").count(),
            3,
            "and each rejection is reported"
        );
    }

    /// A valid answer short-circuits the loop, so "three attempts" is not
    /// satisfied by always prompting three times.
    #[test]
    fn a_valid_name_is_accepted_on_the_first_prompt() {
        let input = std::io::Cursor::new(b"good\n".to_vec());
        let mut err = Vec::new();
        let chosen = choose_install_user_io("agent", &|name: &str| name == "good", input, &mut err);

        assert_eq!(chosen, "good");
        let text = String::from_utf8(err).unwrap();
        assert_eq!(
            text.matches("Install AgentLinux under which user?").count(),
            1
        );
    }

    /// The consent prompt has the same three-attempt bound, and the same
    /// mutations survived on it. A run of invalid answers must end in a DECLINE,
    /// never in an accidental accept.
    #[test]
    fn the_consent_prompt_gives_exactly_three_attempts_then_declines() {
        let input = std::io::Cursor::new(b"x\nq\nz\ny\ny\n".to_vec());
        let mut err = Vec::new();
        let accepted = confirm_remediate_io("npm-prefix", "chown the prefix", input, &mut err);

        assert!(
            !accepted,
            "three invalid answers must decline — never fall through to accept"
        );
        let text = String::from_utf8(err).unwrap();
        assert_eq!(
            text.matches("Proceed with this remediation?").count(),
            3,
            "exactly three prompts:\n{text}"
        );
    }

    /// EOF at the very first read is a decline, not a retry — `delete match arm
    /// Ok(0)` survived, and without it a closed stdin loops against a stream
    /// that will never produce another byte.
    #[test]
    fn eof_declines_the_consent_prompt_immediately() {
        let input = std::io::Cursor::new(Vec::new());
        let mut err = Vec::new();
        assert!(
            !confirm_remediate_io("sudoers", "overwrite drift", input, &mut err),
            "EOF is a decline"
        );
        let text = String::from_utf8(err).unwrap();
        assert_eq!(
            text.matches("Proceed with this remediation?").count(),
            1,
            "one prompt, then EOF ends it:\n{text}"
        );
    }

    /// EOF arriving MID-DRAIN is terminal too. After an invalid answer the rest
    /// of the line is discarded, and `delete match arm Ok(0)` survived on that
    /// drain — the earlier EOF test could not catch it because it exercises the
    /// FIRST read, a different `Ok(0)` two branches up.
    ///
    /// Without the arm the loop re-prompts against a stream that will never
    /// produce another byte. The verdict is a decline either way, so the witness
    /// is again the prompt count: one, not two.
    #[test]
    fn eof_mid_drain_ends_the_consent_prompt_rather_than_re_prompting() {
        // "x" with no trailing newline: the answer byte is read, then the drain
        // immediately hits EOF.
        let input = std::io::Cursor::new(b"x".to_vec());
        let mut err = Vec::new();
        assert!(
            !confirm_remediate_io("npm-prefix", "chown the prefix", input, &mut err),
            "a half-typed answer followed by EOF declines"
        );
        let text = String::from_utf8(err).unwrap();
        assert_eq!(
            text.matches("Proceed with this remediation?").count(),
            1,
            "EOF mid-drain must END the loop, not re-prompt a closed stream:\n{text}"
        );
    }

    /// Y, y and a bare Enter accept; N and n decline. Pinned so the accept set
    /// cannot quietly widen.
    #[test]
    fn only_the_documented_answers_accept_or_decline() {
        for accept in ["Y\n", "y\n", "\n"] {
            let mut err = Vec::new();
            assert!(
                confirm_remediate_io(
                    "c",
                    "d",
                    std::io::Cursor::new(accept.as_bytes().to_vec()),
                    &mut err
                ),
                "{accept:?} accepts"
            );
        }
        for decline in ["N\n", "n\n"] {
            let mut err = Vec::new();
            assert!(
                !confirm_remediate_io(
                    "c",
                    "d",
                    std::io::Cursor::new(decline.as_bytes().to_vec()),
                    &mut err
                ),
                "{decline:?} declines"
            );
        }
    }
    use crate::provision::probe::{NpmPrefixState, SudoersState, UserState};
    use std::io::Cursor;

    /// The AL-50 prompt gate, exhaustively over the axes that decide it.
    ///
    /// `should_prompt_from` was introduced with its own coverage claim already
    /// written into the doc comment — "a one-line test here instead of a fixture
    /// that has to manufacture a brownfield host" — and no such test existed.
    /// Eight mutants survived on a four-input boolean, including `-> true`,
    /// which fires the install-user prompt on a drifted-sudoers host. This
    /// module's own comment says what happens then: the prompt eats the `[Y/n]`
    /// answers out of the shared read buffer and desyncs the consent loop, "the
    /// bug class this project has shipped twice".
    #[test]
    fn the_install_user_prompt_fires_only_on_a_clean_greenfield_host() {
        let clean = || {
            should_prompt_from(
                false,
                UserState::Absent,
                SudoersState::Absent,
                NpmPrefixState::Absent,
            )
        };
        assert!(clean(), "no prior provision and no brownfield flow: prompt");

        // A prior provision. The env-file is the "we already chose a user" mark.
        assert!(!should_prompt_from(
            true,
            UserState::Absent,
            SudoersState::Absent,
            NpmPrefixState::Absent
        ));

        // Each irreconcilable user state owns its own flow: WrongShell is the
        // UX-04 alt-user gate, HomeNotWritable is a REUSE-01 bail. Prompting
        // first would swallow their answers.
        for state in [UserState::WrongShell, UserState::HomeNotWritable] {
            assert!(
                !should_prompt_from(false, state, SudoersState::Absent, NpmPrefixState::Absent),
                "{state:?} has its own flow"
            );
        }
        // Conforming does NOT: an existing compatible user is still offered for
        // rename, so this arm must stay true.
        assert!(should_prompt_from(
            false,
            UserState::Conforming,
            SudoersState::Absent,
            NpmPrefixState::Absent
        ));

        // The two REMEDIATE consent flows. Only the drifted/wrong-owner arms
        // suppress — a sudoers drop-in that merely EXISTS and carries the
        // canonical line, or an npm prefix already owned by the user, does not.
        assert!(!should_prompt_from(
            false,
            UserState::Absent,
            SudoersState::Drifted,
            NpmPrefixState::Absent
        ));
        assert!(should_prompt_from(
            false,
            UserState::Absent,
            SudoersState::Canonical,
            NpmPrefixState::Absent
        ));
        assert!(!should_prompt_from(
            false,
            UserState::Absent,
            SudoersState::Absent,
            NpmPrefixState::WrongOwner
        ));
        assert!(should_prompt_from(
            false,
            UserState::Absent,
            SudoersState::Absent,
            NpmPrefixState::OwnedByUser
        ));
    }

    fn ok(_n: &str) -> bool {
        true
    }
    // Reject anything with an uppercase letter (a cheap stand-in for the real
    // validate_user_name, enough to exercise the reprompt path).
    fn lower_only(n: &str) -> bool {
        !n.is_empty() && n.chars().all(|c| c.is_ascii_lowercase())
    }

    #[test]
    fn typed_name_is_returned_and_prompt_is_rendered() {
        let mut err = Vec::new();
        let got = choose_install_user_io("agent", &ok, Cursor::new(b"claude\n"), &mut err);
        assert_eq!(got, "claude");
        let shown = String::from_utf8(err).unwrap();
        assert!(shown.contains("Install AgentLinux under which user?"));
    }

    #[test]
    fn empty_enter_keeps_the_default() {
        let mut err = Vec::new();
        let got = choose_install_user_io("agent", &ok, Cursor::new(b"\n"), &mut err);
        assert_eq!(got, "agent");
    }

    #[test]
    fn eof_falls_back_to_default() {
        let mut err = Vec::new();
        let got = choose_install_user_io("agent", &ok, Cursor::new(b""), &mut err);
        assert_eq!(got, "agent");
    }

    #[test]
    fn invalid_reprompts_then_accepts_valid() {
        let mut err = Vec::new();
        // First line invalid (uppercase), second valid.
        let got = choose_install_user_io(
            "agent",
            &lower_only,
            Cursor::new(b"BAD\nclaude\n"),
            &mut err,
        );
        assert_eq!(got, "claude");
        assert!(String::from_utf8(err).unwrap().contains("invalid name"));
    }

    #[test]
    fn three_invalid_falls_back_to_default() {
        let mut err = Vec::new();
        let got =
            choose_install_user_io("agent", &lower_only, Cursor::new(b"A\nB\nC\nD\n"), &mut err);
        assert_eq!(got, "agent");
    }
}
