# 020: Bound every wait; degrade loudly rather than block

**Status:** Accepted
**Date:** 2026-07-31

## Context

A reliability review found that essentially nothing in the provisioner was
time-bounded: `dispatch_recipe` passed `timeout_ms: None`, `PkgCmd::run` was a
bare `Command::status()`, and the timeouts that did exist were defeatable —
`escalate_kill` signalled only the direct child, so npm/apt grandchildren
reparented to init and kept working while the reader threads blocked on a pipe
those orphans still held.

Fixing that surfaced a design question with no obvious answer: when a bound
expires or a resource is contended, what should the tool *do*? Three cases came
up repeatedly, and each admits a "safe" answer that is actually worse.

**Capturing output from a leaked process.** A recipe can exit 0 while leaving a
background job holding the stdout pipe (`( sleep 300 ) & echo done`). Waiting for
EOF is "complete" but unbounded. Giving up is bounded but may truncate.

**Two concurrent mutating runs.** Blocking the second is "safe" but a blocked
process is indistinguishable from a hung one. Failing it is abrupt.

**A transient package-manager failure.** Aborting is honest; retrying is
convenient but re-runs a command that may have partially applied.

## Decision

**Every wait in this codebase has a bound, and expiry is reported, never silent.**
The specific resolutions:

1. **Kill the process group, not the child.** Every spawn goes through
   `process_group(0)`; every escalation signals the negated PGID. A timeout now
   means *the work stopped*, not *we stopped waiting* — which is what makes a
   retry safe, because there is no orphan left racing it over the same npm prefix.

2. **Bound output collection; prefer truncation to hanging.** `collect` gives up
   at `READER_DRAIN_GRACE` (5s, shared across both pipes) and says so on stderr.
   The exit status is already known by then, so the caller can still act. A
   truncated capture that announces itself is strictly better than a process that
   never returns — and for the one caller that parses its capture (`npm ls
   --json`), the announcement is what distinguishes "the probe was cut short" from
   "npm printed nothing".

3. **Refuse concurrent mutating runs; do not queue by default.** `statelock`
   takes an exclusive `flock` for `provision`/`install`/`remove`/`upgrade`/
   `adopt`/`pin` and fails fast with `EX_TEMPFAIL` (75), naming the lock file and
   offering `--wait-lock`. Blocking by default would recreate the exact confusion
   the timeouts exist to remove. `list`, `--dry-run` and `--report-only` take no
   lock: the first is read-only, and the other two promise a byte-identical host,
   which creating a lock file would break.

   **Contention fails closed; unavailability fails OPEN.** If the lock file cannot
   be created or opened at all — no `/run/lock`, a read-only filesystem, an
   unusual container — we warn and proceed unlocked. Serializing concurrent runs
   guards a rare race; being unable to *set up* that guard must never be why a
   single uncontended install refuses to run. Treating the two identically would
   brick the tool on any host whose `/run` does not look like ours, which is a
   far more likely failure than the race being defended against.

   The lock lives at `/run/lock/agentlinux.lock`, deliberately outside
   `/opt/agentlinux`: a lock inside the tree it protects stops protecting that
   tree exactly when it matters, because `--purge` would unlink the file it is
   holding and the next run would create a fresh one and acquire it cleanly. It is
   opened read-only where possible (`flock` locks the open file description, not
   the file's write permission) so an unprivileged verb can lock a file
   `provision` created as root, and `O_NOFOLLOW` because the directory is
   world-writable.

4. **Retry package operations, and only package operations.** `PkgCmd::run`
   attempts three times with exponential backoff. This is safe *because* apt and
   dnf commands are idempotent (`update`, `install -y`, `remove -y` all converge),
   and it is worthwhile because the failures are overwhelmingly transient: a DNS
   blip, a mirror 503, cloud-init still holding the dpkg lock. Nothing else in the
   codebase retries. Every retry logs the attempt and the reason.

5. **Defaults are generous; overrides exist; `0` disables.**
   `AGENTLINUX_RECIPE_TIMEOUT_MS` (default 30 min) and `AGENTLINUX_PKG_TIMEOUT_MS`
   (default 20 min) sit far above any legitimate run, so the bound only ever fires
   on a genuine wedge. An unparseable value falls back to the default with a
   warning — a typo in an env var must not be why a provision aborts, and must
   never silently mean "unbounded".

## Consequences

**Accepted: a leaked background process can truncate a captured stream.** We
prefer that to an unbounded wait. It is announced on stderr and in the transcript,
and it only affects the *capture* — the live tee already forwarded every byte.

**Accepted: a legitimately slow recipe can hit the 30-minute bound.** The escape
hatch is one env var, named in this ADR and in the module docs. We judged the
alternative — an unattended `upgrade` timer sitting on a black-holed npm socket
forever, logging nothing past the first entry — strictly worse.

**Accepted: the lock is advisory.** `flock(2)` binds only processes that ask for
it, which here means every writer, because they are all this same binary. It is
not a defence against a hostile process and nothing treats it as one. `/run/lock`
being world-writable also means a local user can hold the lock and stall
AgentLinux operations — under ADR-012, where the install user already holds
`NOPASSWD: ALL`, that is not a boundary worth defending.

**Accepted: the group kill is exact on the direct-exec path, not through `sudo`.**
sudo ≥ 1.9.14 enables `use_pty` by default, which runs the command in its own
session behind a monitor, so it escapes the process group we created and a
group-directed signal reaches sudo rather than the work. sudo's monitor does tear
the command down when sudo dies, so the tree comes down — but by sudo's mechanism
and on its schedule, not ours. We do not work around it: overriding `use_pty` is a
sudoers-side setting we do not own, and widening the kill to catch the escaped
session would mean signalling processes we did not create. The exposure is small
because the dispatcher's invoker==target short-circuit means the sudo hop is not
taken on the common path. Recorded here so it reads as a known boundary rather
than an oversight; `dispatcher::escalate_kill` carries the same note.

**Accepted: three attempts can turn one 20-minute hang into a longer one.** Bounded
at three attempts plus backoff, and each attempt is itself bounded, so the worst
case is finite and computable rather than open-ended.

**What reviewers should not re-file.** Truncation-on-drain, fail-fast-on-lock,
retry-on-package-ops, and the specific default timeout values are decided
trade-offs, not oversights. What *is* still worth flagging: a new wait with no
bound at all, a bound that cannot fire because the thing it guards outlives it, or
an expiry that produces no operator-visible line.

## Related

- ADR-012 (agent holds `NOPASSWD: ALL` — the privilege context these subprocesses
  run in)
- ADR-019 (convergent steps — why a retry after a timeout is safe)
- `dispatcher.rs`, `pkg.rs`, `statelock.rs`
