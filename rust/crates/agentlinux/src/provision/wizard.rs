//! provision/wizard.rs — interactive TTY prompts ported from the deleted Bash
//! `plugin/lib/prompt.sh`. The provisioner is flag-driven by default; these
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
pub fn should_prompt_install_user(user: &str, home: &str) -> bool {
    use crate::provision::probe::{
        npm_prefix_state, sudoers_state, user_state, NpmPrefixState, SudoersState, UserState,
    };
    !std::path::Path::new("/etc/agentlinux.env").exists()
        && user_state(user) != UserState::WrongShell
        && sudoers_state(user) != SudoersState::Drifted
        && npm_prefix_state(user, home) != NpmPrefixState::WrongOwner
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
pub fn choose_install_user(default_user: &str, validate: &dyn Fn(&str) -> bool) -> String {
    let stdin = std::io::stdin();
    choose_install_user_io(default_user, validate, stdin.lock(), std::io::stderr())
}

// --- UX-02: per-component REMEDIATE consent prompt (prompt::confirm_remediate) ---

/// Testable core of the remediation consent prompt. Renders
/// `Proceed with this remediation? [Y/n] (<component> — <description>) ` (the
/// leading substring is the tty-driver sentinel — keep it verbatim) and reads a
/// SINGLE byte: Enter(`\n`/`\r`)/`Y`/`y` → accept; `N`/`n` → decline; any other
/// char → drain the rest of that line and re-prompt (max 3 → decline); EOF →
/// decline. Single-byte-then-line-drain is the T-15-01-03 injection mitigation:
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

/// Prompt on stderr / read from stdin for a state-overwriting remediation.
/// `true` = proceed, `false` = decline. Gate behind TTY + no `--yes`.
///
/// INVARIANT: reads directly from the process-global `std::io::Stdin` buffer.
/// Each component (npm-prefix, then sudoers) calls this fresh, and the read-ahead
/// held in that shared buffer is what carries a trailing `\n` from one answer over
/// to the next prompt (the positional-answer contract). Never wrap `stdin.lock()`
/// in a private `BufReader` here — that read-ahead would land in the throwaway
/// wrapper and be lost between components, desyncing the consent loop.
pub fn confirm_remediate(component: &str, description: &str) -> bool {
    let stdin = std::io::stdin();
    confirm_remediate_io(component, description, stdin.lock(), std::io::stderr())
}

// --- UX-04: wrong-shell alt-user prompt (prompt::alt_user_or_bail) ---

/// First free `agent2..agent99` (remediate::find_alt_user_name), or `None` when
/// all are taken.
#[must_use]
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
        let n = match input.read_line(&mut line) {
            Ok(0) | Err(_) => {
                let _ = writeln!(err);
                return AltUser::DeclinedEof;
            }
            Ok(n) => n,
        };
        // A line with no trailing newline means EOF was hit mid-line (the operator
        // closed the TTY without pressing Enter). Match the Bash `read` contract —
        // EOF → decline — rather than accept a half-typed name AND avoid a second
        // read that would block forever (the driver sends only one EOF).
        if !line.ends_with('\n') && n > 0 {
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
    use std::io::Cursor;

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
