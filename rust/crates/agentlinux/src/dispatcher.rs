//! dispatcher.rs — the subprocess dispatcher (VERB-02). #1 risk, gated first.
//!
//! Byte-for-byte port of `plugin/cli/src/state/dispatcher.ts` (`asUser`) plus the
//! `dispatchRecipe` wrapper (`runner.ts:96-120`). The load-bearing invariants:
//!
//! - **invoker==target short-circuit** (dispatcher.ts:65-72): when the invoker
//!   already IS the target user, run argv directly — agent→agent sudo is broken
//!   on a default Ubuntu host (no sudoers drop-in) and unnecessary. Otherwise
//!   prepend `["sudo","-u",user,"-H","-E","--"]`; the `--` terminator ends sudo
//!   option parsing so user-controlled args can never be reparsed (T-56-01).
//! - **never throw on a non-zero child exit** (Pitfall 5): a non-zero exit is a
//!   valid `DispatchResult` — callers (npm ls exits 1 on a missing dep) decide
//!   fatality. Only a spawn failure (ENOENT) maps to exit_code 1.
//! - **streaming tee via thread-per-pipe** (Pitfall 2): two blocking pipe reads
//!   in one thread deadlock; one reader thread per pipe forwards each chunk live
//!   AND accumulates it, so the returned strings match the buffered contract.
//! - **timeout escalation SIGTERM→(2000ms)→SIGKILL** (Pitfall 1): `Child::kill()`
//!   is SIGKILL-only; we use `nix::sys::signal::kill` to send SIGTERM first, wait
//!   a 2000ms grace, then SIGKILL if still alive. Both paths honor a timeout
//!   (Open Q2: npm probes run buffered with timeout 30_000), but their exit codes
//!   differ FOR PARITY: the STREAMING path maps a timeout to 124 (GNU `timeout`
//!   convention, dispatcher.ts:167), while the BUFFERED path maps it to 1 — the TS
//!   buffered `execFile` timeout reports `code: null` which collapses to 1
//!   (dispatcher.ts:100). No consumer branches on 124 vs 1 today; the split keeps
//!   strict like-for-like.
//!
//! NOTE (security, M2): the CLI-05 EUID guard (`guardAgentUser`, `guard/user.ts`)
//! — which refuses to run unless the invoker IS the configured install user, and
//! is *why* `as_user` almost always hits the invoker==target short-circuit — has
//! no Rust home yet. The Wave-1/2 verb layer (Plans 02/03) MUST port it before
//! wiring these dispatch entry points into a real `main`, or the CLI silently
//! loses the invoker check that bounds who can trigger a `sudo -u` recipe run.
//!
//! `dead_code` is allowed at module scope for this Wave-0 scaffold: the
//! verb-layer entry points (`dispatch_recipe`, `dispatch_recipe_with_env`) are
//! consumed by the Wave-1/2 adapters (Plans 02/03), and `as_user`/the readers
//! are fully exercised by the `#[cfg(test)]` parity module now. The allow only
//! silences the "not yet wired into a non-test caller" lint until those plans
//! land, keeping the per-task tree warning-clean. Remove once verbs import it.
#![allow(dead_code)]

use crate::recipe_env::{full_child_env, RecipeEnv};
use nix::sys::signal::{kill, Signal};
use nix::unistd::{getuid, Pid, User};
use std::io::Read;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};
use wait_timeout::ChildExt;

/// The grace period between SIGTERM and the SIGKILL escalation (dispatcher.ts:139).
const KILL_GRACE: Duration = Duration::from_millis(2000);

/// Cap on captured child output, mirroring the TS `maxBuffer: 10 * 1024 * 1024`
/// (dispatcher.ts:86). Without it a runaway recipe (a looping installer, npm
/// debug spew, a recipe catting a large file) grows the parent heap until the
/// OOM killer reaps the CLI — the buffered `npm ls -g --json` probe on the
/// unattended `upgrade` path is the most exposed. Past the cap we stop growing
/// the captured `String` (the live tee still forwards every byte, so the console
/// is unaffected) and keep draining the pipe to EOF so a full pipe can't
/// deadlock the child.
const MAX_CAPTURE: usize = 10 * 1024 * 1024;

/// The result shape mirroring `AsUserResult` — never an `Err`/panic on a
/// non-zero child exit (Pitfall 5).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DispatchResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
    /// True only when the streaming path teed output live (callers skip
    /// re-printing). The buffered path leaves it `false`.
    pub streamed: bool,
}

/// Resolve the invoker's username: prefer the passwd entry for the real uid
/// (matches Node's `userInfo().username`), fall back to `$USER`, else empty.
fn invoker_username() -> String {
    if let Ok(Some(user)) = User::from_uid(getuid()) {
        return user.name;
    }
    std::env::var("USER").unwrap_or_default()
}

/// Build the concrete argv: direct when invoker==target, else the sudo hop.
/// The `--` terminator is load-bearing (T-56-01).
fn resolve_argv(user: &str, argv: &[String]) -> Vec<String> {
    if invoker_username() == user {
        argv.to_vec()
    } else {
        let mut v = vec![
            "sudo".to_string(),
            "-u".to_string(),
            user.to_string(),
            "-H".to_string(),
            "-E".to_string(),
            "--".to_string(),
        ];
        v.extend_from_slice(argv);
        v
    }
}

/// Run `argv` as `user`, teeing+capturing when `stream`, honoring an optional
/// `timeout_ms` that escalates SIGTERM→(2000ms)→SIGKILL. Mirrors `asUser`.
pub fn as_user(
    user: &str,
    argv: &[String],
    env: &[(String, String)],
    stream: bool,
    timeout_ms: Option<u64>,
) -> DispatchResult {
    let full = resolve_argv(user, argv);
    // resolve_argv always yields ≥1 element (argv is non-empty at call sites),
    // but guard defensively so an empty argv is a clean error not a panic.
    let (cmd, rest) = match full.split_first() {
        Some((c, r)) => (c.clone(), r.to_vec()),
        None => {
            return DispatchResult {
                exit_code: 1,
                stdout: String::new(),
                stderr: "empty argv".to_string(),
                streamed: stream,
            }
        }
    };

    if stream {
        stream_tee(&cmd, &rest, env, timeout_ms)
    } else {
        buffered(&cmd, &rest, env, timeout_ms)
    }
}

/// A `Command` with the child env set explicitly (`env_clear` + `envs`) and
/// stdin nulled — shared by both paths.
fn base_command(cmd: &str, rest: &[String], env: &[(String, String)]) -> Command {
    let mut c = Command::new(cmd);
    c.args(rest)
        .env_clear()
        .envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .stdin(Stdio::null());
    c
}

/// Map a finished `ExitStatus` to an exit code: a clean code as-is; a
/// signal-kill with no code → 1 (dispatcher.ts:167 `code ?? (signal?1:0)`).
fn status_to_code(status: std::process::ExitStatus) -> i32 {
    status.code().unwrap_or(1)
}

/// Buffered path (stream=false): capture stdout/stderr, honor an optional
/// timeout (Open Q2), never throw on a non-zero exit (Pitfall 5).
fn buffered(
    cmd: &str,
    rest: &[String],
    env: &[(String, String)],
    timeout_ms: Option<u64>,
) -> DispatchResult {
    let mut command = base_command(cmd, rest, env);
    command.stdout(Stdio::piped()).stderr(Stdio::piped());

    let mut child = match command.spawn() {
        Ok(c) => c,
        // Spawn failure (ENOENT) → the shape with exit_code 1 (mirrors the
        // execFile catch), NOT an Err.
        Err(e) => {
            return DispatchResult {
                exit_code: 1,
                stdout: String::new(),
                stderr: e.to_string(),
                streamed: false,
            }
        }
    };

    // Drain the pipes on reader threads so a chatty child can't fill a pipe
    // buffer and deadlock while we wait (Pitfall 2 applies to the buffered
    // capture too, not only the tee).
    let out_rx = spawn_reader(child.stdout.take());
    let err_rx = spawn_reader(child.stderr.take());

    let (exit_code, timed_out) = match timeout_ms {
        Some(ms) => match child.wait_timeout(Duration::from_millis(ms)) {
            Ok(Some(status)) => (status_to_code(status), false),
            Ok(None) => {
                // Expired → escalate SIGTERM→grace→SIGKILL. The BUFFERED path maps
                // a timeout to exit_code 1 for strict parity: the TS buffered
                // `execFile` timeout kills with SIGTERM and reports `code: null`,
                // which `dispatcher.ts:100` collapses to 1 (only the STREAMING path
                // returns 124). Log the timed-out command for the unattended path.
                eprintln!(
                    "agentlinux: recipe `{}` timed out after {}ms; sent SIGTERM…SIGKILL",
                    cmd, ms
                );
                escalate_kill(&mut child);
                let _ = child.wait();
                (1, true)
            }
            Err(_) => {
                let _ = child.kill();
                let _ = child.wait();
                (1, false)
            }
        },
        None => match child.wait() {
            Ok(status) => (status_to_code(status), false),
            Err(_) => (1, false),
        },
    };
    let _ = timed_out; // buffered timeout already collapses to exit_code 1.

    let stdout = out_rx.recv().unwrap_or_default();
    let stderr = err_rx.recv().unwrap_or_default();
    DispatchResult {
        exit_code,
        stdout,
        stderr,
        streamed: false,
    }
}

/// Streaming path (stream=true): tee each chunk live to this process's
/// stdout/stderr AS it arrives, accumulate into the returned strings, and run a
/// timeout watchdog. Always `streamed: true`.
fn stream_tee(
    cmd: &str,
    rest: &[String],
    env: &[(String, String)],
    timeout_ms: Option<u64>,
) -> DispatchResult {
    let mut command = base_command(cmd, rest, env);
    command.stdout(Stdio::piped()).stderr(Stdio::piped());

    let mut child = match command.spawn() {
        Ok(c) => c,
        // ENOENT → exit_code 1, streamed true (dispatcher.ts:157-162).
        Err(e) => {
            return DispatchResult {
                exit_code: 1,
                stdout: String::new(),
                stderr: e.to_string(),
                streamed: true,
            }
        }
    };

    // One reader thread per pipe (Pitfall 2), each teeing live + accumulating.
    let out_rx = spawn_tee_reader(child.stdout.take(), TeeSink::Stdout);
    let err_rx = spawn_tee_reader(child.stderr.take(), TeeSink::Stderr);

    // Timeout watchdog by polling try_wait so we can escalate SIGTERM→SIGKILL
    // even against a child that ignores SIGTERM (VALIDATION escalation case).
    let (exit_code, timed_out) = wait_with_timeout(&mut child, timeout_ms);
    if timed_out {
        eprintln!(
            "agentlinux: recipe `{}` timed out after {}ms; sent SIGTERM…SIGKILL",
            cmd,
            timeout_ms.unwrap_or(0)
        );
    }

    let stdout = out_rx.recv().unwrap_or_default();
    let stderr = err_rx.recv().unwrap_or_default();

    let final_code = if timed_out { 124 } else { exit_code };
    DispatchResult {
        exit_code: final_code,
        stdout,
        stderr,
        streamed: true,
    }
}

/// Poll `try_wait` until the child exits or `timeout_ms` elapses; on expiry
/// escalate SIGTERM→(2000ms)→SIGKILL. Returns `(exit_code, timed_out)`.
fn wait_with_timeout(child: &mut std::process::Child, timeout_ms: Option<u64>) -> (i32, bool) {
    match timeout_ms {
        None => match child.wait() {
            Ok(status) => (status_to_code(status), false),
            Err(_) => (1, false),
        },
        Some(ms) => {
            let deadline = Instant::now() + Duration::from_millis(ms);
            let poll = Duration::from_millis(10);
            loop {
                match child.try_wait() {
                    Ok(Some(status)) => return (status_to_code(status), false),
                    Ok(None) => {
                        if Instant::now() >= deadline {
                            escalate_kill(child);
                            let _ = child.wait();
                            return (124, true);
                        }
                        std::thread::sleep(poll);
                    }
                    Err(_) => return (1, false),
                }
            }
        }
    }
}

/// SIGTERM, wait up to KILL_GRACE for the child to die, then SIGKILL if it
/// hasn't (Pitfall 1 — `nix::kill`, not std `Child::kill` which is SIGKILL-only).
///
/// Known parity behavior (matches dispatcher.ts `child.kill`): this signals only
/// the DIRECT child PID (`bash <recipe>` or `sudo`), not its process group. A
/// recipe's own grandchildren (npm/apt/git) are NOT torn down and reparent to
/// init on timeout — a faithful port of the TS weakness, not a regression. A
/// deliberate improvement (spawn in a new process group + signal the negated
/// PGID to reap the whole subtree) is deferred to keep this like-for-like; if a
/// future release wants a timeout to fully "stop the work," that's the change.
fn escalate_kill(child: &mut std::process::Child) {
    let pid = Pid::from_raw(child.id() as i32);
    let _ = kill(pid, Signal::SIGTERM);
    let grace_deadline = Instant::now() + KILL_GRACE;
    let poll = Duration::from_millis(10);
    loop {
        match child.try_wait() {
            Ok(Some(_)) => return, // exited within grace after SIGTERM
            Ok(None) => {
                if Instant::now() >= grace_deadline {
                    let _ = kill(pid, Signal::SIGKILL);
                    return;
                }
                std::thread::sleep(poll);
            }
            Err(_) => return,
        }
    }
}

/// Which parent stream a tee reader forwards to.
enum TeeSink {
    Stdout,
    Stderr,
}

/// Spawn a thread that reads a child pipe to EOF, teeing each chunk live to the
/// parent's stdout/stderr and accumulating it; sends the full string back.
fn spawn_tee_reader<R: Read + Send + 'static>(
    pipe: Option<R>,
    sink: TeeSink,
) -> mpsc::Receiver<String> {
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut acc = String::new();
        if let Some(mut r) = pipe {
            let mut buf = [0u8; 8192];
            loop {
                match r.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        // Cap the captured string (MAX_CAPTURE) so a runaway child
                        // can't OOM the parent; keep teeing + draining regardless.
                        // The guard bounds growth to ≤ one extra chunk past the cap
                        // (no mid-char `truncate`, which would panic).
                        if acc.len() < MAX_CAPTURE {
                            let chunk = String::from_utf8_lossy(&buf[..n]);
                            acc.push_str(&chunk);
                        }
                        // Live tee to the parent stream.
                        use std::io::Write;
                        match sink {
                            TeeSink::Stdout => {
                                let _ = std::io::stdout().write_all(&buf[..n]);
                                let _ = std::io::stdout().flush();
                            }
                            TeeSink::Stderr => {
                                let _ = std::io::stderr().write_all(&buf[..n]);
                                let _ = std::io::stderr().flush();
                            }
                        }
                    }
                }
            }
        }
        let _ = tx.send(acc);
    });
    rx
}

/// Spawn a thread that reads a child pipe to EOF and accumulates it (no tee) —
/// the buffered-path drain that prevents a full-pipe deadlock.
fn spawn_reader<R: Read + Send + 'static>(pipe: Option<R>) -> mpsc::Receiver<String> {
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut acc = String::new();
        if let Some(mut r) = pipe {
            // Read to EOF (drain the pipe so the child can't deadlock) but stop
            // GROWING the capture past MAX_CAPTURE — `read_to_string` is unbounded
            // and would let a chatty child OOM the parent (npm ls JSON probe).
            let mut buf = [0u8; 8192];
            loop {
                match r.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        if acc.len() < MAX_CAPTURE {
                            acc.push_str(&String::from_utf8_lossy(&buf[..n]));
                        }
                    }
                }
            }
        }
        let _ = tx.send(acc);
    });
    rx
}

/// `dispatch_recipe` — the verb-layer entry (runner.ts:96-120). Builds the argv
/// `["bash", recipe_path]` and delegates to `as_user`. The verb layer (Plans
/// 02/03) builds `env` via `recipe_env::full_child_env` and calls this.
pub fn dispatch_recipe(
    user: &str,
    recipe_path: &str,
    env: &[(String, String)],
    stream: bool,
) -> DispatchResult {
    let argv = vec!["bash".to_string(), recipe_path.to_string()];
    as_user(user, &argv, env, stream, None)
}

/// Convenience: assemble the full child env from a `RecipeEnv` and dispatch a
/// recipe in one call — the shape the Wave-1/2 verb adapters will lean on. Kept
/// here so `full_child_env` (recipe_env.rs) has a non-test consumer.
pub fn dispatch_recipe_with_env(
    recipe: RecipeEnv,
    user: &str,
    recipe_path: &str,
    extra: &[(String, String)],
    stream: bool,
) -> DispatchResult {
    let env = full_child_env(recipe, user, extra);
    dispatch_recipe(user, recipe_path, &env, stream)
}

#[cfg(test)]
mod dispatcher_tests {
    use super::*;
    use nix::unistd::{getuid, User};

    /// The current username — invoker==target so `as_user` runs argv directly
    /// (no sudo), keeping these tests unprivileged and host-portable.
    fn self_user() -> String {
        User::from_uid(getuid())
            .ok()
            .flatten()
            .map(|u| u.name)
            .unwrap_or_else(|| std::env::var("USER").unwrap_or_default())
    }

    fn argv(parts: &[&str]) -> Vec<String> {
        parts.iter().map(|s| s.to_string()).collect()
    }

    // Case 1 (dispatcher-stream.test.ts:44): stream tees stdout+stderr live AND
    // captures them; streamed=true, exit 0.
    #[test]
    fn stream_tees_and_captures() {
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", "echo out-line; echo err-line >&2"]),
            &[],
            true,
            None,
        );
        assert_eq!(r.exit_code, 0);
        assert!(r.streamed);
        assert!(r.stdout.contains("out-line"), "stdout={:?}", r.stdout);
        assert!(r.stderr.contains("err-line"), "stderr={:?}", r.stderr);
    }

    // Case 2 (:64): stream propagates a non-zero exit without panicking.
    #[test]
    fn stream_non_zero_exit_no_panic() {
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", "echo hi; exit 7"]),
            &[],
            true,
            None,
        );
        assert_eq!(r.exit_code, 7);
        assert!(r.streamed);
        assert!(r.stdout.contains("hi"));
    }

    // Case 3 (:77): buffered captures output; streamed stays false.
    #[test]
    fn buffered_captures_streamed_false() {
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", "echo buffered"]),
            &[],
            false,
            None,
        );
        assert_eq!(r.exit_code, 0);
        assert!(r.stdout.contains("buffered"));
        assert!(!r.streamed, "buffered path must not claim streamed");
    }

    // Case 4 (:84): the sudo branch fires when invoker != target; an unknown
    // user makes the outcome deterministic (sudo errors → non-zero), surfaced
    // as a returned shape, never a panic.
    #[test]
    fn sudo_branch_unknown_user_returns_shape() {
        let r = as_user(
            "no-such-user-agentlinux-xyzzy",
            &argv(&["bash", "-c", "echo x"]),
            &[],
            true,
            None,
        );
        assert_ne!(r.exit_code, 0, "unknown sudo target must fail non-zero");
        assert!(r.streamed);
    }

    // Case 5 (:104): ENOENT (missing binary) maps to exit_code 1, streamed true.
    #[test]
    fn enoent_maps_to_one() {
        let r = as_user(
            &self_user(),
            &argv(&["/no/such/binary/agentlinux-xyzzy"]),
            &[],
            true,
            None,
        );
        assert_eq!(r.exit_code, 1, "ENOENT maps to 1");
        assert!(r.streamed);
    }

    // Case 6 (:117): timeout → SIGTERM → exit_code 124 (GNU convention).
    #[test]
    fn timeout_maps_to_124() {
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", "sleep 5"]),
            &[],
            true,
            Some(300),
        );
        assert_eq!(r.exit_code, 124, "timed-out child maps to 124");
        assert!(r.streamed);
    }

    // Case 7 (VALIDATION Manual-Only): a child that IGNORES SIGTERM still
    // terminates via the SIGKILL escalation within the grace window, mapping
    // to 124. `trap '' TERM` makes SIGTERM a no-op so only SIGKILL can end it.
    #[test]
    fn sigterm_ignoring_child_escalates_to_sigkill() {
        let start = Instant::now();
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", "trap '' TERM; sleep 30"]),
            &[],
            true,
            Some(200),
        );
        assert_eq!(r.exit_code, 124, "escalation still maps to 124");
        assert!(r.streamed);
        // Must have been killed via escalation well before the 30s sleep — the
        // 200ms timeout + 2000ms grace bounds it comfortably under ~5s.
        assert!(
            start.elapsed() < Duration::from_secs(5),
            "escalation should terminate the child within the grace window"
        );
    }

    // Buffered path ALSO honors a timeout (Open Q2: npm probes run buffered
    // with timeout 30_000), but maps it to exit_code 1 — strict parity with the
    // TS buffered `execFile`, whose SIGTERM-kill reports `code: null` → 1
    // (dispatcher.ts:100). Only the STREAMING path returns 124.
    #[test]
    fn buffered_timeout_maps_to_1() {
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", "sleep 5"]),
            &[],
            false,
            Some(300),
        );
        assert_eq!(
            r.exit_code, 1,
            "buffered timeout maps to 1 (TS execFile parity)"
        );
        assert!(!r.streamed);
    }

    // dispatch_recipe builds ["bash", <recipe>] and runs it (runner.ts:96-120).
    #[test]
    fn dispatch_recipe_runs_bash_recipe() {
        // A recipe that just echoes proves the argv shape + env passthrough.
        let dir = std::env::temp_dir();
        let path = dir.join(format!("al-56-recipe-{}.sh", std::process::id()));
        std::fs::write(
            &path,
            "#!/usr/bin/env bash\necho recipe-ran: $AGENTLINUX_SOURCE_KIND\n",
        )
        .unwrap();
        let r = dispatch_recipe(
            &self_user(),
            path.to_str().unwrap(),
            &[("AGENTLINUX_SOURCE_KIND".to_string(), "npm".to_string())],
            false,
        );
        let _ = std::fs::remove_file(&path);
        assert_eq!(r.exit_code, 0);
        assert!(
            r.stdout.contains("recipe-ran: npm"),
            "stdout={:?}",
            r.stdout
        );
    }
}
