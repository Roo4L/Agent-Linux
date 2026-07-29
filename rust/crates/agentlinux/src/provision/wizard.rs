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

use std::io::{BufRead, IsTerminal, Write};

/// True when stdin is an interactive terminal (the wizard's guard). The
/// curl-installer pipes the installer over stdin → not a TTY → no prompt.
#[must_use]
pub fn stdin_is_tty() -> bool {
    std::io::stdin().is_terminal()
}

/// Greenfield when the provisioner's env-file marker is absent — matches the
/// Bash gate that only prompted for the install user on a fresh host (a second
/// run already has `INSTALL_USER` chosen and prompting would derail remediation).
#[must_use]
pub fn is_greenfield() -> bool {
    !std::path::Path::new("/etc/agentlinux.env").exists()
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
