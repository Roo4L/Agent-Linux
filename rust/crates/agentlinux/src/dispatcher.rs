//! dispatcher.rs — the subprocess dispatcher (VERB-02): run an argv as another
//! user, buffered or streamed, with an optional timeout.
//!
//! The load-bearing invariants:
//!
//! - **invoker==target short-circuit**: when the invoker already IS the target
//!   user, run argv directly — agent→agent sudo is broken on a default Ubuntu
//!   host (no sudoers drop-in) and unnecessary. Otherwise prepend
//!   `["sudo","-u",user,"-H","-E","--"]`; the `--` terminator ends sudo option
//!   parsing so user-controlled args can never be reparsed as options.
//! - **never throw on a non-zero child exit**: a non-zero exit is a valid
//!   `DispatchResult` — callers decide fatality (`npm ls` exits 1 on a missing
//!   peer dep but still emits usable JSON). Only a spawn failure (ENOENT) maps
//!   to exit_code 1.
//! - **streaming tee via thread-per-pipe**: two blocking pipe reads in one thread
//!   deadlock; one reader thread per pipe forwards each chunk live AND
//!   accumulates it, so the returned strings match the buffered contract.
//! - **timeout escalation SIGTERM→(2000ms)→SIGKILL, group-wide**: every child
//!   gets its own process group (`process_group(0)`) and the escalation signals
//!   the negated PGID, so a recipe's npm/apt/git grandchildren die with it rather
//!   than reparenting to init and racing the retry. Both paths honor a timeout,
//!   but their exit codes differ: the STREAMING path maps a timeout to 124 (the
//!   GNU `timeout` convention) and the BUFFERED path maps it to 1. The split is
//!   deliberate — see `Capture::timeout_exit`.
//! - **every dispatch is bounded**: `dispatch_recipe` carries
//!   `recipe_timeout_ms()`, and output collection gives up after
//!   `READER_DRAIN_GRACE`. A leaked background job holding the pipe open costs
//!   that capture entirely; it can no longer hang the process.
//!
//! # Where the invoker check lives
//! `as_user` almost always hits the invoker==target short-circuit *because* the
//! CLI-05 EUID guard ran first: `guard::guard_agent_user` refuses to run unless
//! the invoker is the configured install user, and `main::dispatch` calls it
//! before every verb. This module does not re-check that — it assumes the guard
//! already bounded who can reach a `sudo -u` recipe run.

use nix::sys::signal::{kill, Signal};
use nix::unistd::{getuid, Pid, User};
use std::io::Read;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// The grace period between SIGTERM and the SIGKILL escalation.
const KILL_GRACE: Duration = Duration::from_millis(2000);

/// How long to wait for a SIGKILLed child to actually be reaped before giving up
/// on it. Only reachable if signal delivery failed or the process is wedged in an
/// uninterruptible syscall (D state on stuck NFS/disk I/O), which no signal can
/// clear. Bounded so the timeout path itself cannot become an unbounded wait.
const REAP_GRACE: Duration = Duration::from_secs(10);

/// How long to wait for a reader thread to hand back its accumulated output
/// after the child has been reaped.
///
/// A pipe closes only when EVERY holder of the write end closes it, and a recipe
/// can leave a background grandchild holding one (`( sleep 300 & )`). The
/// process-group teardown in `escalate_kill` reaps those on the timeout path, but
/// a child that exits 0 while leaking a background job is not a timeout at all —
/// nothing signals it. Without this bound `recv()` would block for as long as the
/// orphan lives, turning a successful dispatch into an unbounded hang.
const READER_DRAIN_GRACE: Duration = Duration::from_secs(5);

/// Default wall-clock bound on one recipe run (`dispatch_recipe`), overridable
/// via `AGENTLINUX_RECIPE_TIMEOUT_MS`.
///
/// 30 minutes is chosen to sit well above the slowest legitimate recipe — the
/// Playwright entry downloads browser bundles — while still bounding the
/// wedged-forever cases (a held dpkg lock, a black-holed npm socket) that an
/// unattended `upgrade` timer would otherwise sit in until someone noticed.
const DEFAULT_RECIPE_TIMEOUT_MS: u64 = 30 * 60 * 1000;

/// Env override for `DEFAULT_RECIPE_TIMEOUT_MS`. `0` disables the bound, which is
/// the escape hatch for an operator whose recipe legitimately runs longer.
const RECIPE_TIMEOUT_ENV: &str = "AGENTLINUX_RECIPE_TIMEOUT_MS";

/// Cap on captured child output. Without it a runaway recipe (a looping installer, npm
/// debug spew, a recipe catting a large file) grows the parent heap until the
/// OOM killer reaps the CLI — the buffered `npm ls -g --json` probe on the
/// unattended `upgrade` path is the most exposed. Past the cap we stop growing
/// the captured `String` (the live tee still forwards every byte, so the console
/// is unaffected) and keep draining the pipe to EOF so a full pipe can't
/// deadlock the child.
const MAX_CAPTURE: usize = 10 * 1024 * 1024;

/// Whether the capture buffer may still grow.
///
/// A named predicate rather than an inline `acc.len() < MAX_CAPTURE`, because
/// the BOUNDARY is the contract and it is otherwise only reachable by producing
/// ten megabytes of child output: `<` vs `<=` differ on exactly one byte, at a
/// size no test is going to generate. Past the cap the live tee still forwards
/// every byte and the pipe is still drained to EOF — only the retained String
/// stops growing.
const fn may_accumulate(len: usize) -> bool {
    len < MAX_CAPTURE
}

/// How a dispatched child's output is handled — and, as a direct consequence,
/// what a timeout reports as its exit code.
///
/// This is an enum rather than a `stream: bool` because the two arms are not
/// merely cosmetic: they disagree about the timeout exit code (see
/// `timeout_exit`), and a bare `false` at a call site said nothing about which
/// contract that call site was signing up for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Capture {
    /// Capture stdout/stderr and return them; nothing reaches the console.
    /// Used by the probes (`npm ls`, `npm view`, detection) whose output is
    /// parsed, not shown.
    Buffered,
    /// Tee each chunk to this process's stdout/stderr as it arrives AND
    /// accumulate it into the returned strings. Used for recipe runs, where the
    /// operator watches the install happen.
    Streamed,
}

impl Capture {
    /// The exit code a timeout reports on this path.
    ///
    /// The two differ deliberately. A streamed recipe run is something an
    /// operator is watching, so it reports 124 — the GNU `timeout` convention
    /// they can recognise and script against. The buffered probes report 1,
    /// which is what their callers were built against; they treat any non-zero
    /// as "probe failed, fall back". No caller branches on 124 vs 1 today, but
    /// the codes are part of each path's observable contract.
    const fn timeout_exit(self) -> i32 {
        match self {
            Capture::Streamed => 124,
            Capture::Buffered => 1,
        }
    }

    /// True on the streaming path — the value `DispatchResult::streamed` carries
    /// so callers know output already reached the console.
    const fn is_streamed(self) -> bool {
        matches!(self, Capture::Streamed)
    }
}

/// The result of one dispatch — never an `Err`/panic on a non-zero child exit.
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
pub(crate) fn invoker_username() -> String {
    if let Ok(Some(user)) = User::from_uid(getuid()) {
        return user.name;
    }
    std::env::var("USER").unwrap_or_default()
}

/// Build the concrete argv for the ambient invoker (the production entry point).
fn resolve_argv(user: &str, argv: &[String]) -> Vec<String> {
    resolve_argv_for(&invoker_username(), user, argv)
}

/// Build the concrete argv: direct when invoker==target, else the sudo hop.
/// The `--` terminator is load-bearing.
///
/// `invoker` is a parameter rather than an ambient read so the argv SHAPE — the
/// flags this module's doc calls load-bearing — can be asserted directly. Every
/// test that goes through `as_user` necessarily runs as the current user, i.e.
/// takes the short-circuit, so the sudo arm was never executed by any assertion
/// that looked at it.
fn resolve_argv_for(invoker: &str, user: &str, argv: &[String]) -> Vec<String> {
    if invoker == user {
        argv.to_vec()
    } else {
        let mut v = vec![
            "sudo".to_string(),
            "-u".to_string(),
            user.to_string(),
            "-H".to_string(),
            // `-E` preserves the INVOKER's env into the child. That is leak-safe
            // ONLY because `base_command` `env_clear()`s first (dispatcher.rs
            // ~L140), so the invoker env is already reduced to exactly the caller-
            // supplied pairs — no ambient root secret (SSH_AUTH_SOCK, tokens,
            // SUDO_*) exists to be preserved. These two lines are COUPLED: dropping
            // `env_clear` would turn `-E` into a root→child env-leak. Keep both.
            "-E".to_string(),
            "--".to_string(),
        ];
        v.extend_from_slice(argv);
        v
    }
}

/// One dispatch's inputs, resolved: the concrete argv to spawn plus the operator-
/// facing label and bound that every diagnostic on this path reports.
///
/// A struct rather than five positional parameters because `label` and `cmd` are
/// both strings that must not be confused: `cmd` is what we exec (often literally
/// `"sudo"`), `label` is what a human needs to see in a timeout line.
struct Spawn<'a> {
    /// argv[0] — the program to exec. `"sudo"` whenever the hop is taken.
    cmd: String,
    /// argv[1..].
    rest: Vec<String>,
    env: &'a [(String, String)],
    timeout_ms: Option<u64>,
    /// What the operator called for — the PRE-sudo argv, so a timeout names the
    /// recipe or the npm probe rather than the `sudo` wrapper around it.
    label: String,
}

/// Render the caller's argv as a single-line operator-facing label, bounded so a
/// recipe invoked with a long argument list cannot produce an unreadable log line.
fn describe(argv: &[String]) -> String {
    const MAX_LABEL: usize = 200;
    let joined = argv.join(" ");
    match joined.char_indices().nth(MAX_LABEL) {
        Some((byte_idx, _)) => format!("{}…", &joined[..byte_idx]),
        None => joined,
    }
}

/// The `as_user` signature, as an injectable fn pointer — the seam a provisioner
/// step's subprocess FAILURE arms are reachable through.
pub type AsUser = fn(
    user: &str,
    argv: &[String],
    env: &[(String, String)],
    capture: Capture,
    timeout_ms: Option<u64>,
) -> DispatchResult;

/// Run `argv` as `user` under `capture`, honoring an optional `timeout_ms` that
/// escalates SIGTERM→(2000ms)→SIGKILL across the child's whole process group.
pub fn as_user(
    user: &str,
    argv: &[String],
    env: &[(String, String)],
    capture: Capture,
    timeout_ms: Option<u64>,
) -> DispatchResult {
    let full = resolve_argv(user, argv);
    // resolve_argv always yields ≥1 element (argv is non-empty at call sites),
    // but guard defensively so an empty argv is a clean error not a panic.
    let Some((cmd, rest)) = full.split_first() else {
        return DispatchResult {
            exit_code: 1,
            stdout: String::new(),
            stderr: "empty argv".to_string(),
            streamed: capture.is_streamed(),
        };
    };
    let spawn = Spawn {
        cmd: cmd.clone(),
        rest: rest.to_vec(),
        env,
        timeout_ms,
        // Label from the ORIGINAL argv, not `full` — `full[0]` is `sudo` on the
        // drop path, which told the operator nothing about what actually hung.
        label: describe(argv),
    };

    match capture {
        Capture::Streamed => stream_tee(&spawn),
        Capture::Buffered => buffered(&spawn),
    }
}

/// A `Command` with the child env set explicitly (`env_clear` + `envs`), stdin
/// nulled, and its OWN process group — shared by both paths.
///
/// `process_group(0)` is what makes the timeout enforceable. Without it a kill
/// reaches only the direct child (`bash <recipe>` or `sudo`) while the npm/apt
/// grandchildren doing the actual work reparent to init and keep running, so a
/// retry would race an orphan over the same npm prefix and the pipe would stay
/// open. With it, `escalate_kill` signals the negated PGID and the whole tree
/// goes down together. Safe with `stdin(Stdio::null())`: a background process
/// group only takes SIGTTIN from a terminal read, which a null stdin never does.
fn base_command(spawn: &Spawn) -> Command {
    let mut c = Command::new(&spawn.cmd);
    c.args(&spawn.rest)
        .env_clear()
        .envs(spawn.env.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .stdin(Stdio::null());
    own_process_group(&mut c);
    c
}

/// Map a finished `ExitStatus` to an exit code: a clean code as-is; a
/// signal-kill with no code → 1 (dispatcher.ts:167 `code ?? (signal?1:0)`).
fn status_to_code(status: std::process::ExitStatus) -> i32 {
    status.code().unwrap_or(1)
}

/// `Capture::Buffered`: capture stdout/stderr, honor an optional timeout, never
/// throw on a non-zero exit.
fn buffered(spawn: &Spawn) -> DispatchResult {
    run(spawn, None, None)
}

/// `Capture::Streamed`: tee each chunk live to this process's stdout/stderr AS
/// it arrives, accumulate into the returned strings, and run a timeout watchdog.
/// Always `streamed: true`.
fn stream_tee(spawn: &Spawn) -> DispatchResult {
    run(spawn, Some(TeeSink::Stdout), Some(TeeSink::Stderr))
}

/// The one spawn-wait-collect body. `out_sink`/`err_sink` are `None` on the
/// buffered path and `Some` on the streaming path — the ONLY difference between
/// the two, which is why there is one implementation and not two near-copies.
fn run(spawn: &Spawn, out_sink: Option<TeeSink>, err_sink: Option<TeeSink>) -> DispatchResult {
    let streamed = out_sink.is_some();
    let mut command = base_command(spawn);
    command.stdout(Stdio::piped()).stderr(Stdio::piped());

    let mut child = match command.spawn() {
        Ok(c) => c,
        // Spawn failure (ENOENT) → the shape with exit_code 1 (mirrors the
        // execFile catch), NOT an Err. Name what we failed to exec: a bare
        // "No such file or directory (os error 2)" left the operator guessing
        // WHICH binary was missing.
        Err(e) => {
            return DispatchResult {
                exit_code: 1,
                stdout: String::new(),
                stderr: format!("failed to spawn `{}` ({}): {e}", spawn.cmd, spawn.label),
                streamed,
            }
        }
    };

    // One reader thread per pipe, each optionally teeing live + accumulating.
    // Two blocking pipe reads in a single thread would deadlock, and draining to
    // EOF is what keeps a chatty child from filling a pipe buffer and wedging.
    let out_rx = spawn_reader(child.stdout.take(), out_sink);
    let err_rx = spawn_reader(child.stderr.take(), err_sink);

    let (exit_code, timed_out) = wait_with_timeout(&mut child, spawn.timeout_ms, &spawn.label);

    // ONE deadline shared by both pipes: the bound belongs to the dispatch, not
    // to each reader. Draining them with a grace apiece would let a single leaked
    // process hold the call for twice as long as the constant advertises.
    let drain_deadline = Instant::now() + READER_DRAIN_GRACE;
    let stdout = collect(out_rx, drain_deadline, &spawn.label, "stdout");
    let stderr = collect(err_rx, drain_deadline, &spawn.label, "stderr");

    DispatchResult {
        exit_code: if timed_out {
            if streamed {
                Capture::Streamed.timeout_exit()
            } else {
                Capture::Buffered.timeout_exit()
            }
        } else {
            exit_code
        },
        stdout,
        stderr,
        streamed,
    }
}

/// Take a reader thread's accumulated output, giving up at `deadline` rather
/// than blocking forever on a leaked pipe holder.
///
/// Losing the capture beats hanging: the exit status is already known by the time
/// this runs, so the caller can still act. Be precise about the cost — the reader
/// sends its whole accumulated string in one go, so there is no partial result to
/// recover and this returns EMPTY, not truncated. The give-up is logged because an
/// empty capture would otherwise look like a child that simply said nothing, and
/// several callers parse what they capture (`npm ls -g --json`, `npm view`, and
/// the version and `command -v` probes in `detect.rs`) — for those, the difference
/// is "unknown" versus "absent".
fn collect(rx: mpsc::Receiver<String>, deadline: Instant, label: &str, stream: &str) -> String {
    let remaining = deadline.saturating_duration_since(Instant::now());
    match rx.recv_timeout(remaining) {
        Ok(s) => s,
        Err(_) => {
            crate::plog!(
                "agentlinux: `{label}` exited but its {stream} pipe is still held by a background \
                 process after {}s; its output could not be captured",
                READER_DRAIN_GRACE.as_secs()
            );
            String::new()
        }
    }
}

/// How often `poll_until` re-checks a child's exit status.
const POLL_INTERVAL: Duration = Duration::from_millis(10);

/// Poll `try_wait` until the child exits or `deadline` passes.
///
/// `Some(code)` when it exited in time, `None` on expiry. The one waiting
/// primitive in this module: both the timeout wait and the SIGTERM grace period
/// are "watch this child until a deadline", and they used to be two hand-rolled
/// copies of this loop plus a third mechanism (the `wait-timeout` crate) on the
/// buffered path.
fn poll_until(child: &mut std::process::Child, deadline: Instant) -> Option<i32> {
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return Some(status_to_code(status)),
            Ok(None) => {
                if Instant::now() >= deadline {
                    return None;
                }
                std::thread::sleep(POLL_INTERVAL);
            }
            // The wait itself failed — treat as exited-with-1 rather than
            // spinning forever on a child we can no longer observe.
            Err(_) => return Some(1),
        }
    }
}

/// Wait for `child`, honoring an optional `timeout_ms`; on expiry escalate
/// SIGTERM→(2000ms)→SIGKILL across its process group. Returns
/// `(exit_code, timed_out)`; on a timeout the caller substitutes its own code.
///
/// `label` names the operation in the timeout line — on the unattended `upgrade`
/// path that line is the only evidence the work was killed rather than failing on
/// its own.
///
/// Crate-visible because `pkg.rs` needs the same bound for apt/dnf, which cannot
/// go through `as_user` (it `env_clear`s, and the package managers need the
/// inherited environment).
pub(crate) fn wait_with_timeout(
    child: &mut std::process::Child,
    timeout_ms: Option<u64>,
    label: &str,
) -> (i32, bool) {
    let Some(ms) = timeout_ms else {
        return match child.wait() {
            Ok(status) => (status_to_code(status), false),
            Err(_) => (1, false),
        };
    };
    match poll_until(child, Instant::now() + Duration::from_millis(ms)) {
        Some(code) => (code, false),
        None => {
            escalate_kill(child, label);
            // Bounded, not a bare `wait()`. If signal delivery ever fails (the
            // EPERM case `escalate_kill` now logs), an unbounded wait here would
            // turn the timeout into an unlogged infinite block — a bound that
            // cannot fire is worse than no bound, because the log claims one does.
            if poll_until(child, Instant::now() + REAP_GRACE).is_none() {
                crate::plog!(
                    "agentlinux: `{label}` has not exited {}s after SIGKILL; \
                     abandoning the wait. Check for a stuck process before retrying.",
                    REAP_GRACE.as_secs()
                );
            }
            crate::plog!(
                "agentlinux: `{label}` timed out after {ms}ms; \
                 sent SIGTERM…SIGKILL to the process group"
            );
            (1, true)
        }
    }
}

/// Put `cmd`'s child in its own process group so a timeout can tear down the
/// whole tree. See `base_command` for why this is the load-bearing half of the
/// timeout contract.
pub(crate) fn own_process_group(cmd: &mut Command) {
    cmd.process_group(0);
}

/// SIGTERM the child's whole process group, wait up to `KILL_GRACE`, then
/// SIGKILL the group if anything is still alive.
///
/// Signalling the negated PGID (the POSIX "whole group" form) rather than the
/// bare PID is what makes the timeout mean "the work stopped" instead of "we
/// stopped waiting". `base_command` puts every child in its own group via
/// `process_group(0)`, so the negated PID *is* the group and no unrelated process
/// can be caught by it. Without this the recipe's npm/apt/git grandchildren
/// survived the kill, reparented to init, and kept mutating the same npm prefix
/// a retry was about to use.
///
/// `nix::kill` rather than std's `Child::kill`, which is SIGKILL-only on the
/// direct child and gives the tree no chance to clean up.
///
/// # KNOWN LIMITATION: the sudo hop
/// This is exact on the direct-exec path (invoker==target, which is the common
/// case — see the module header). It is NOT exact through `sudo`: sudo ≥ 1.9.14
/// enables `use_pty` by default, which runs the command in its own session behind
/// a monitor process, so the command escapes the group we created and a
/// group-directed SIGKILL reaches sudo rather than the work. sudo's monitor
/// terminates the command when sudo dies, so the tree does come down in practice,
/// but not by our signal and not on our schedule. Recorded in ADR-022 rather than
/// worked around: overriding `use_pty` is a sudoers-side setting, and widening the
/// kill to catch it would mean signalling processes we did not create.
fn escalate_kill(child: &mut std::process::Child, label: &str) {
    let group = Pid::from_raw(-(child.id() as i32));
    // A failed signal is the difference between "the work stopped" and "we only
    // stopped waiting", so it is reported rather than discarded — otherwise the
    // timeout line below claims a teardown that never happened.
    if let Err(e) = kill(group, Signal::SIGTERM) {
        crate::plog!("agentlinux: SIGTERM to `{label}`'s process group failed: {e}");
    }
    if poll_until(child, Instant::now() + KILL_GRACE).is_none() {
        // Still alive after the grace period — it ignored SIGTERM.
        if let Err(e) = kill(group, Signal::SIGKILL) {
            crate::plog!("agentlinux: SIGKILL to `{label}`'s process group failed: {e}");
        }
        return;
    }
    // The direct child exited during the grace period but its grandchildren may
    // not have — that leak is what keeps the pipe open and the npm prefix
    // contended. Sweep the group once.
    //
    // The child has ALREADY been reaped at this point (`poll_until` gets its
    // answer from `try_wait`), so this signals a PGID whose leader is gone. That
    // is still safe, and not because of the ordering: Linux refcounts `struct
    // pid`, and every member of a process group holds a reference to the pid
    // backing its PGID. The number therefore cannot be recycled while the group
    // still has members — which is exactly the case we are signalling into. If
    // the group is empty the pid may have been freed, and the call returns ESRCH,
    // which is the normal outcome and is ignored below. `kill(-pgid)` after the
    // leader exits is a standard idiom for precisely this reason.
    if let Err(e) = kill(group, Signal::SIGKILL) {
        if e != nix::errno::Errno::ESRCH {
            crate::plog!("agentlinux: group sweep after `{label}` failed: {e}");
        }
    }
}

/// Which parent stream a reader tees to, or `None` to capture silently.
#[derive(Debug, Clone, Copy)]
enum TeeSink {
    Stdout,
    Stderr,
}

impl TeeSink {
    /// Forward one chunk to the parent stream.
    ///
    /// Not mutation-tested: it writes to the process's real stdout/stderr
    /// (ADR-019 §5). Which sink a stream tees to is decided by the caller and
    /// asserted there; there is nothing here but the write itself.
    #[cfg_attr(test, mutants::skip)]
    fn write(self, bytes: &[u8]) {
        use std::io::Write;
        match self {
            TeeSink::Stdout => {
                let _ = std::io::stdout().write_all(bytes);
                let _ = std::io::stdout().flush();
            }
            TeeSink::Stderr => {
                let _ = std::io::stderr().write_all(bytes);
                let _ = std::io::stderr().flush();
            }
        }
    }
}

/// Spawn a thread that reads a child pipe to EOF, optionally teeing each chunk
/// live to a parent stream, and sends the accumulated string back.
///
/// Reading to EOF is not optional on either path: it drains the pipe so a chatty
/// child cannot fill the buffer and deadlock waiting for us. What IS bounded is
/// how much we KEEP — past `MAX_CAPTURE` we stop growing the `String` while
/// still draining, so a runaway recipe cannot OOM the parent. The cap is checked
/// per chunk, so growth is bounded to at most one extra chunk past it.
///
/// `sink` is `None` on the buffered path and `Some` on the streaming path — the
/// only difference between them, which is why there is one reader and not two.
fn spawn_reader<R: Read + Send + 'static>(
    pipe: Option<R>,
    sink: Option<TeeSink>,
) -> mpsc::Receiver<String> {
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        // Accumulate BYTES and decode once at EOF. Decoding per chunk with
        // `from_utf8_lossy` corrupts any multi-byte sequence that straddles a
        // chunk boundary — each half becomes U+FFFD. For `npm ls -g --json`
        // larger than one chunk with any non-ASCII byte in it, that turned valid
        // JSON into a parse failure whose appearance depended on where the 8 KiB
        // boundary happened to land: size-dependent and intermittent.
        let mut acc: Vec<u8> = Vec::new();
        if let Some(mut r) = pipe {
            let mut buf = [0u8; 8192];
            loop {
                match r.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        if may_accumulate(acc.len()) {
                            acc.extend_from_slice(&buf[..n]);
                        }
                        if let Some(sink) = sink {
                            sink.write(&buf[..n]);
                        }
                    }
                }
            }
        }
        let _ = tx.send(String::from_utf8_lossy(&acc).into_owned());
    });
    rx
}

/// Signature of a recipe dispatch — exactly `dispatch_recipe`'s.
///
/// The DI seam every verb takes: production passes `dispatch_recipe` itself,
/// unit tests pass a stub, so branch selection is exercised without spawning a
/// subprocess. Lives here rather than in a verb module because it is this
/// module's function signature.
pub type RecipeDispatcher =
    fn(user: &str, recipe_path: &str, env: &[(String, String)], capture: Capture) -> DispatchResult;

/// The wall-clock bound one recipe run gets: `AGENTLINUX_RECIPE_TIMEOUT_MS` when
/// set to a parseable value, else `DEFAULT_RECIPE_TIMEOUT_MS`. An explicit `0`
/// means unbounded.
///
/// An unparseable value falls back to the default rather than failing the
/// install: a typo in an env var should not be the reason a provision aborts, and
/// the warning says which value was ignored.
pub(crate) fn recipe_timeout_ms() -> Option<u64> {
    let configured = match std::env::var(RECIPE_TIMEOUT_ENV) {
        Err(_) => DEFAULT_RECIPE_TIMEOUT_MS,
        Ok(raw) => match raw.trim().parse::<u64>() {
            Ok(ms) => ms,
            Err(_) => {
                crate::plog!(
                    "agentlinux: ignoring unparseable {RECIPE_TIMEOUT_ENV}={raw:?}; \
                     using {DEFAULT_RECIPE_TIMEOUT_MS}ms"
                );
                DEFAULT_RECIPE_TIMEOUT_MS
            }
        },
    };
    (configured > 0).then_some(configured)
}

/// The verb-layer entry: build the argv `["bash", recipe_path]` and delegate to
/// `as_user`. Callers build `env` via `recipe_env::full_child_env`.
///
/// Bounded by `recipe_timeout_ms`. A recipe that wedges — a held dpkg lock, a
/// black-holed npm socket — is killed with its whole process group and reported
/// as 124 rather than hanging an unattended `upgrade` timer forever.
pub fn dispatch_recipe(
    user: &str,
    recipe_path: &str,
    env: &[(String, String)],
    capture: Capture,
) -> DispatchResult {
    let argv = vec!["bash".to_string(), recipe_path.to_string()];
    as_user(user, &argv, env, capture, recipe_timeout_ms())
}

#[cfg(test)]
mod dispatcher_tests {
    use super::*;
    use nix::unistd::{getuid, User};

    /// A command that finishes well inside its timeout must not be reported as
    /// timed out. Three mutants survived on the waiting path and every one of
    /// them makes the deadline already-expired: `poll_until -> None`, `>=`
    /// flipped to `<` in its deadline check, and `Instant::now() + ms` becoming
    /// a subtraction. All three turn every dispatch into an instant timeout —
    /// `install` would report exit 124 for a recipe that ran fine.
    #[test]
    fn a_fast_command_under_a_generous_timeout_is_not_a_timeout() {
        let start = Instant::now();
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", "exit 0"]),
            &[],
            Capture::Buffered,
            Some(10_000),
        );
        assert_eq!(r.exit_code, 0, "a command that exits 0 in time reports 0");
        assert!(
            start.elapsed() < Duration::from_secs(3),
            "and it must return promptly, not sit out the timeout"
        );

        // A non-zero exit is still not a timeout: the child chose that code.
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", "exit 7"]),
            &[],
            Capture::Buffered,
            Some(10_000),
        );
        assert_eq!(
            r.exit_code, 7,
            "the child's own exit code must survive, not become the timeout code"
        );
    }

    /// The capture cap is a memory bound on an unattended path — the buffered
    /// `npm ls -g --json` probe that `upgrade` runs. Its arithmetic could be
    /// mutated (`*` to `+` or `/`) to 10250 bytes or 10240 KiB with nothing
    /// noticing, and the `<` could become `<=`.
    ///
    /// Ten megabytes of child output is not something a test will generate, so
    /// the bound and its boundary are asserted directly instead.
    #[test]
    fn the_capture_cap_is_ten_megabytes_and_stops_at_it() {
        assert_eq!(MAX_CAPTURE, 10 * 1024 * 1024, "10 MiB, not 10 KiB or 10250");

        assert!(may_accumulate(0));
        assert!(may_accumulate(MAX_CAPTURE - 1), "one byte short still fits");
        assert!(
            !may_accumulate(MAX_CAPTURE),
            "AT the cap the buffer stops growing — `<=` would let it exceed"
        );
        assert!(!may_accumulate(MAX_CAPTURE + 1));
    }

    /// `is_streamed` is what `DispatchResult::streamed` carries, and callers use
    /// it to decide whether output already reached the console. Both constant
    /// replacements survived.
    #[test]
    fn only_the_streamed_capture_reports_as_streamed() {
        assert!(Capture::Streamed.is_streamed());
        assert!(!Capture::Buffered.is_streamed());
    }

    /// The sudo hop is skipped only when the invoker IS the target user.
    /// `replace == with !=` survived because every test that goes through
    /// `as_user` necessarily runs as the current user and takes the
    /// short-circuit — so the sudo arm was never executed by any assertion that
    /// looked at it. Inverted, a same-user call gets a pointless sudo hop and a
    /// cross-user call runs as the WRONG user.
    #[test]
    fn the_sudo_hop_is_taken_only_when_the_user_differs() {
        let argv = vec!["node".to_string(), "--version".to_string()];

        let same = resolve_argv_for("agent", "agent", &argv);
        assert_eq!(same, argv, "no hop when the invoker is already the target");

        let cross = resolve_argv_for("root", "agent", &argv);
        assert_eq!(cross[0], "sudo");
        assert_eq!(&cross[1..4], &["-u", "agent", "-H"]);
        assert!(
            cross.ends_with(&argv),
            "the original argv must survive the hop intact, got {cross:?}"
        );
    }

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

    // Case 1: stream tees stdout+stderr live AND
    // captures them; streamed=true, exit 0.
    #[test]
    fn stream_tees_and_captures() {
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", "echo out-line; echo err-line >&2"]),
            &[],
            Capture::Streamed,
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
            Capture::Streamed,
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
            Capture::Buffered,
            None,
        );
        assert_eq!(r.exit_code, 0);
        assert!(r.stdout.contains("buffered"));
        assert!(!r.streamed, "buffered path must not claim streamed");
    }

    // --- the sudo hop's ARGV SHAPE (T-56-01) ---
    //
    // Every flag below is load-bearing and every one of them used to be
    // unasserted: the only test touching the sudo branch ran an unknown user and
    // checked `exit_code != 0`, which passes identically if `--` is deleted, if
    // `-E` is dropped, if `-H` is dropped, or if the flags are reordered.

    #[test]
    fn sudo_hop_argv_is_exact() {
        assert_eq!(
            resolve_argv_for("root", "agent", &argv(&["bash", "/opt/recipe.sh"])),
            argv(&[
                "sudo",
                "-u",
                "agent",
                "-H",
                "-E",
                "--",
                "bash",
                "/opt/recipe.sh"
            ])
        );
    }

    #[test]
    fn sudo_hop_keeps_h_so_the_child_gets_the_target_home() {
        // Dropping -H runs the recipe with ROOT's HOME, so `npm install -g`
        // writes to /root/.npm — the ownership bug class AgentLinux exists to
        // eliminate.
        let out = resolve_argv_for("root", "agent", &argv(&["bash", "x.sh"]));
        assert!(out.contains(&"-H".to_string()), "argv={out:?}");
    }

    #[test]
    fn sudo_hop_terminator_precedes_every_caller_supplied_word() {
        // `--` ends sudo's option parsing, so a recipe path that begins with a
        // dash can never be reparsed as a sudo flag.
        let out = resolve_argv_for("root", "agent", &argv(&["bash", "-not-a-flag.sh"]));
        let term = out.iter().position(|w| w == "--").expect("-- terminator");
        let recipe = out.iter().position(|w| w == "-not-a-flag.sh").unwrap();
        assert!(term < recipe, "argv={out:?}");
        // …and it is the LAST sudo-owned word: everything after it is ours.
        assert_eq!(&out[term + 1..], &argv(&["bash", "-not-a-flag.sh"])[..]);
    }

    #[test]
    fn sudo_hop_preserves_env_explicitly() {
        // -E is only leak-safe because base_command env_clear()s first; the two
        // are coupled, so pin that -E is actually emitted.
        let out = resolve_argv_for("root", "agent", &argv(&["bash", "x.sh"]));
        assert!(out.contains(&"-E".to_string()), "argv={out:?}");
    }

    #[test]
    fn invoker_equals_target_short_circuits_without_sudo() {
        // agent→agent sudo is broken on a default Ubuntu host (no drop-in), so
        // the short-circuit is a correctness requirement, not an optimisation.
        let a = argv(&["bash", "x.sh"]);
        assert_eq!(resolve_argv_for("agent", "agent", &a), a);
        assert!(!resolve_argv_for("agent", "agent", &a).contains(&"sudo".to_string()));
    }

    #[test]
    fn the_target_user_lands_in_the_u_slot_verbatim() {
        // An alternate install user (AL-50) must reach sudo as its own argument
        // — never spliced into a longer word.
        let out = resolve_argv_for("root", "claude", &argv(&["bash", "x.sh"]));
        assert_eq!(out[1], "-u");
        assert_eq!(out[2], "claude");
    }

    // Case 4 (:84): the sudo branch fires when invoker != target, and what it
    // EXECUTES is `resolve_argv_for`'s output.
    //
    // This used to invoke the real `sudo` against a nonexistent user and assert
    // `exit_code != 0`. That verdict holds on every host, but for three
    // different reasons — unknown user, invoker not in sudoers, or no `sudo`
    // binary at all (ENOENT → 1, which `enoent_maps_to_one` below already
    // covers) — so it could not distinguish "the sudo branch ran" from "nothing
    // ran". It also executed real `sudo` during `cargo test`, which is how the
    // suite came to print `sudo: error initializing audit plugin sudoers_audit`.
    //
    // A stub `sudo` on PATH makes the claim decidable: the branch is observed by
    // what it invoked, not by a failure code shared with the ways it can not run.
    #[test]
    fn the_sudo_branch_executes_the_resolved_argv() {
        let d = tempfile::TempDir::new().unwrap();
        std::fs::write(
            d.path().join("sudo"),
            "#!/usr/bin/env bash\nprintf '%s\\n' \"$@\"\n",
        )
        .unwrap();
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(
            d.path().join("sudo"),
            std::fs::Permissions::from_mode(0o755),
        )
        .unwrap();

        // The child env is `env_clear`ed, so PATH must arrive through the same
        // `env` argument a real recipe dispatch uses — which is also why this
        // needs no process-global mutation and no `EnvScope` lock.
        let path = format!("{}:/usr/bin:/bin", d.path().display());
        let env = vec![("PATH".to_string(), path)];

        let want = resolve_argv_for(&invoker_username(), "claude", &argv(&["bash", "x.sh"]));
        assert_eq!(
            want[0], "sudo",
            "this test is meaningless on the direct branch"
        );

        let r = as_user(
            "claude",
            &argv(&["bash", "x.sh"]),
            &env,
            Capture::Buffered,
            None,
        );
        assert_eq!(r.exit_code, 0);
        assert!(!r.streamed);
        assert_eq!(
            r.stdout.lines().collect::<Vec<_>>(),
            want[1..].iter().map(String::as_str).collect::<Vec<_>>(),
            "the sudo branch must execute exactly what resolve_argv_for produced"
        );
    }

    // Case 5 (:104): ENOENT (missing binary) maps to exit_code 1, streamed true.
    #[test]
    fn enoent_maps_to_one() {
        let r = as_user(
            &self_user(),
            &argv(&["/no/such/binary/agentlinux-xyzzy"]),
            &[],
            Capture::Streamed,
            None,
        );
        assert_eq!(r.exit_code, 1, "ENOENT maps to 1");
        assert!(r.streamed);
    }

    // Case 6 (:117): timeout → SIGTERM → exit_code 124 (GNU convention).
    #[test]
    fn timeout_maps_to_124() {
        let start = Instant::now();
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", "sleep 5"]),
            &[],
            Capture::Streamed,
            Some(300),
        );
        assert_eq!(r.exit_code, 124, "timed-out child maps to 124");
        assert!(r.streamed);
        // The exit code alone does not prove the child was STOPPED: a broken
        // kill path still reports 124 once the child finishes its own sleep. The
        // clock is the only witness that the timeout bounded anything.
        assert!(
            start.elapsed() < Duration::from_secs(3),
            "the timeout must end the child, not merely outlast it: took {:?}",
            start.elapsed()
        );
    }

    // Case 7 (VALIDATION Manual-Only): a child that IGNORES SIGTERM still
    // terminates via the SIGKILL escalation within the grace window, mapping
    // to 124. `trap '' TERM` makes SIGTERM a no-op so only SIGKILL can end it.
    #[test]
    fn sigterm_ignoring_child_escalates_to_sigkill() {
        let start = Instant::now();
        let r = as_user(
            &self_user(),
            // 8s, not 30: it only has to outlast the escalation window
            // (200ms timeout + 2000ms grace ~= 2.2s) by a comfortable margin.
            // At 30s a BROKEN escalation still failed this test — after thirty
            // seconds, which is past cargo-mutants' per-mutant timeout, so three
            // real mutants on this path were recorded as timeouts rather than as
            // caught. A test that takes 30s to notice a regression is a slow
            // test, not a strong one.
            &argv(&["bash", "-c", "trap '' TERM; sleep 8"]),
            &[],
            Capture::Streamed,
            Some(200),
        );
        assert_eq!(r.exit_code, 124, "escalation still maps to 124");
        assert!(r.streamed);
        // Must have been killed via escalation well before the 8s sleep — the
        // 200ms timeout + 2000ms grace bounds it comfortably under ~5s.
        let elapsed = start.elapsed();
        assert!(
            elapsed < Duration::from_secs(5),
            "escalation should terminate the child within the grace window, took {elapsed:?}"
        );
        // …and NOT instantly. SIGTERM comes first and the child gets its full
        // grace period before SIGKILL. `Instant::now() + KILL_GRACE` becoming a
        // subtraction survived: the grace deadline is then already past, so
        // SIGKILL fires immediately and a child that WOULD have cleaned up on
        // SIGTERM never gets the chance. This child ignores SIGTERM, so the only
        // witness is the clock.
        assert!(
            elapsed >= Duration::from_millis(1_500),
            "the child must get its SIGTERM grace before SIGKILL, took {elapsed:?}"
        );
    }

    // Buffered path ALSO honors a timeout (npm probes run buffered
    // with timeout 30_000), but maps it to exit_code 1 — strict parity with the
    // TS buffered `execFile`, whose SIGTERM-kill reports `code: null` → 1
    // Only the STREAMING path returns 124.
    #[test]
    fn buffered_timeout_maps_to_1() {
        let start = Instant::now();
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", "sleep 5"]),
            &[],
            Capture::Buffered,
            Some(300),
        );
        assert_eq!(
            r.exit_code, 1,
            "buffered timeout maps to 1 (TS execFile parity)"
        );
        assert!(!r.streamed);
        // As on the streamed path: the exit code does not prove the child was
        // stopped, only the clock does.
        assert!(
            start.elapsed() < Duration::from_secs(3),
            "the buffered timeout must end the child too: took {:?}",
            start.elapsed()
        );
    }

    // A recipe that leaks a background grandchild holding the stdout pipe must
    // not hang the dispatch. The child exits immediately; the orphan holds the
    // pipe well past READER_DRAIN_GRACE. Before the bounded `collect`, `recv()`
    // blocked for the orphan's full lifetime — a successful run that never
    // returned. This is the empirical check the review asked for.
    #[test]
    fn leaked_background_child_cannot_hang_the_dispatch() {
        let start = Instant::now();
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", "( sleep 120 ) & echo done"]),
            &[],
            Capture::Buffered,
            None,
        );
        assert_eq!(r.exit_code, 0, "the direct child exited cleanly");
        // The grace is shared across BOTH pipes, so the whole dispatch is bounded
        // by one READER_DRAIN_GRACE — not one per reader.
        assert!(
            start.elapsed() < READER_DRAIN_GRACE + Duration::from_secs(2),
            "dispatch must return on the drain grace, not the orphan's lifetime \
             (took {:?})",
            start.elapsed()
        );
    }

    // The timeout tears down the whole process group, not just the direct child.
    // The recipe spawns a grandchild that writes a marker file after a delay; if
    // the group kill works, the marker never appears. Before this, the grandchild
    // reparented to init and kept running — "a timeout stops the wait, not the
    // work".
    #[test]
    fn timeout_kills_grandchildren_not_just_the_direct_child() {
        let marker = std::env::temp_dir().join(format!("al-pgid-{}.marker", std::process::id()));
        let _ = std::fs::remove_file(&marker);
        let script = format!("( sleep 2; touch {} ) & sleep 30", marker.to_str().unwrap());
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", &script]),
            &[],
            Capture::Streamed,
            Some(200),
        );
        assert_eq!(r.exit_code, 124, "timed-out run maps to 124");
        // Outlive the grandchild's own sleep: if it survived the group kill it
        // would have written the marker by now.
        std::thread::sleep(Duration::from_secs(4));
        let survived = marker.exists();
        let _ = std::fs::remove_file(&marker);
        assert!(
            !survived,
            "grandchild survived the timeout and kept working"
        );
    }

    // The timeout line names what the OPERATOR asked for, not `sudo`. `describe`
    // is what carries that, so assert it directly: on the drop path argv[0] of
    // the spawned command is literally "sudo" and the recipe path is the only
    // thing that identifies the run.
    #[test]
    fn describe_labels_the_callers_argv_not_the_sudo_wrapper() {
        let label = describe(&argv(&[
            "bash",
            "/opt/agentlinux/catalog/agents/gsd/install.sh",
        ]));
        assert!(label.contains("gsd/install.sh"), "label={label}");
        assert!(!label.starts_with("sudo"), "label={label}");
        // The sudo hop is what gets EXECUTED for a non-self target …
        let full = resolve_argv("someone-else", &argv(&["bash", "recipe.sh"]));
        assert_eq!(full[0], "sudo");
        // … while the label the operator reads stays the recipe.
        assert_eq!(describe(&argv(&["bash", "recipe.sh"])), "bash recipe.sh");
    }

    // A long argv is truncated so one dispatch cannot emit an unreadable log line.
    #[test]
    fn describe_bounds_label_length() {
        let long = argv(&["bash", &"x".repeat(500)]);
        let label = describe(&long);
        assert!(
            label.len() < 260,
            "label not bounded: {} chars",
            label.len()
        );
        assert!(label.ends_with('…'));
    }

    // The recipe bound is on by default, overridable, and disengaged by an
    // explicit 0. An unparseable value falls back rather than failing the run.
    #[test]
    fn recipe_timeout_reads_env_with_a_safe_default() {
        let _g = crate::test_support::EnvScope::new();
        std::env::remove_var(RECIPE_TIMEOUT_ENV);
        assert_eq!(recipe_timeout_ms(), Some(DEFAULT_RECIPE_TIMEOUT_MS));

        std::env::set_var(RECIPE_TIMEOUT_ENV, "5000");
        assert_eq!(recipe_timeout_ms(), Some(5000));

        // Explicit 0 = opt out of the bound entirely.
        std::env::set_var(RECIPE_TIMEOUT_ENV, "0");
        assert_eq!(recipe_timeout_ms(), None);

        // Garbage must not become "unbounded" by accident.
        std::env::set_var(RECIPE_TIMEOUT_ENV, "not-a-number");
        assert_eq!(recipe_timeout_ms(), Some(DEFAULT_RECIPE_TIMEOUT_MS));

        std::env::remove_var(RECIPE_TIMEOUT_ENV);
    }

    // A multi-byte UTF-8 sequence straddling the 8 KiB read boundary must survive
    // capture intact. Decoding per chunk replaced each half with U+FFFD, which
    // corrupted `npm ls -g --json` output larger than one chunk — intermittently,
    // depending on where the boundary landed.
    #[test]
    fn multibyte_output_survives_a_read_boundary() {
        // Pad with ASCII so the multi-byte char lands mid-buffer, then emit a
        // 3-byte char (é is 2 bytes, → is 3) many times across the boundary.
        let script = "printf 'a%.0s' $(seq 1 8190); printf '→%.0s' $(seq 1 100)";
        let r = as_user(
            &self_user(),
            &argv(&["bash", "-c", script]),
            &[],
            Capture::Buffered,
            None,
        );
        assert_eq!(r.exit_code, 0);
        assert_eq!(
            r.stdout.matches('→').count(),
            100,
            "multi-byte chars corrupted at the chunk boundary"
        );
        assert!(
            !r.stdout.contains('\u{FFFD}'),
            "replacement char present — a sequence was split"
        );
    }

    // dispatch_recipe builds ["bash", <recipe>] and runs it.
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
            Capture::Buffered,
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
