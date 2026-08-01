# 022: Bound every wait; degrade loudly rather than block

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

One carve-out, stated here so the rule above is literally true rather than
approximately true. The TTY prompts — `wizard::confirm_remediate`,
`choose_install_user`, `alt_user_prompt` — are unbounded blocking reads on stdin,
deliberately: waiting for a human who is sitting there is the entire point, and a
timeout would turn a considered answer into a default. They are safe because they
are TTY-gated (a non-TTY run takes the bail path instead of blocking) and because
`--dry-run` returns before the DECIDE phase can reach one. Any OTHER unbounded
wait is a defect, including a new prompt that is not TTY-gated.

The specific resolutions:

1. **Kill the process group, not the child.** Every spawn this crate makes goes
   through `process_group(0)`; every escalation signals the negated PGID. A timeout now
   means *the work stopped*, not *we stopped waiting* — which is what makes a
   retry safe, because there is no orphan left racing it over the same npm prefix.

2. **Bound output collection; prefer losing the capture to hanging.** `collect`
   gives up at `READER_DRAIN_GRACE` (5s, shared across both pipes) and says so on
   stderr. Be precise about the cost: it does not return a partial string, it
   returns an EMPTY one — the accumulated bytes live in the reader thread and are
   abandoned with it. The exit status is already known by then, so the caller can
   still act. Several callers parse their capture (`npm ls -g --json` and `npm
   view`, plus the version and `command -v` probes in `detect.rs`), and for each of
   them the announcement is what separates "the probe was cut short" from "the tool
   printed nothing" — which for a detect probe is the difference between "unknown"
   and "absent".

3. **Refuse concurrent mutating runs; do not queue by default.** `statelock`
   takes an exclusive `flock` for `provision`/`install`/`remove`/`upgrade`/
   `adopt`/`pin` and fails fast with `EX_TEMPFAIL` (75), naming the lock file.
   There is deliberately no queue-and-wait flag: `EX_TEMPFAIL` is the conventional
   "try again later" signal, and `until agentlinux install x; do sleep 10; done` is
   both more flexible than any cap we would hardcode and not ours to carry.

   `list`, `--dry-run` and `--report-only` take no lock. The reason is
   operability, not byte-identity: both preview modes already write the detect
   cache under `/run`, and the no-mutation contract they advertise covers `/etc`,
   `/home` and `/etc/passwd` rather than `/run`, so a lock file there would not
   break it. They are exempt because a preview refused while an install runs is the
   same problem as a blocked `list` — you reach for these commands precisely when
   something else is busy.

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

4. **Do not add a general retry.** An earlier cut of this work retried every
   package command three times with exponential backoff. It is gone, for two
   reasons. It retried TIMEOUTS, so one `pkg_install` on debian could run two
   commands x three attempts x the 20-minute bound — quietly multiplying the very
   ceiling the rest of this ADR establishes. And the two transient cases that
   motivated it already have targeted fixes: `DPkg::Lock::Timeout=300` for
   cloud-init holding the dpkg lock, and `curl --retry 3 --retry-connrefused` for
   the NodeSource fetch. A generic retry on top of those was generalisation ahead
   of a requirement, on the privileged path, with no test.

   Two narrow retries remain and are deliberate: the curl flags above, and
   `userdel -r` falling back to `userdel -rf` during `--purge`. Both are bounded
   and both target a named failure. Anything broader should be argued for on its
   own evidence rather than inherited from this ADR.

5. **Defaults are generous; overrides exist; `0` disables.**
   `AGENTLINUX_RECIPE_TIMEOUT_MS` (default 30 min) and `AGENTLINUX_PKG_TIMEOUT_MS`
   (default 20 min) sit far above any legitimate run, so the bound only ever fires
   on a genuine wedge. An unparseable value falls back to the default with a
   warning — a typo in an env var must not be why a provision aborts, and must
   never silently mean "unbounded".

## Consequences

**Accepted: a leaked background process costs us a captured stream.** We prefer
that to an unbounded wait. It is announced on stderr, and during a provision in the
transcript too — note the CLI verbs have no transcript today, so there it is
stderr-only. It affects only the *capture*: on the streamed path the live tee
already forwarded every byte to the console.

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
taken by the six CLI verbs, whose CLI-05 guard forces invoker == install user. It
IS taken throughout `provision`, which runs as root — including the `--purge`
uninstall dispatch — so treat the limitation as live there. Revisit if the sudo hop
ever becomes the common path; the mitigating claim about sudo's monitor is an
assumption about upstream behaviour that nothing here tests.
`dispatcher::escalate_kill` carries the same note.

**Accepted: `0` disables a bound.** A document titled "bound every wait" ships an
explicit way to become unbounded. That is an operator's deliberate opt-out for a
recipe that legitimately runs longer than any default we could pick; the invariant
defended here is that we never become unbounded *by accident* — an unparseable
value falls back to the default rather than to `None`.

**What reviewers should not re-file.** Truncation-on-drain, fail-fast-on-lock,
retry-on-package-ops, and the specific default timeout values are decided
trade-offs, not oversights. What *is* still worth flagging: a new wait with no
bound at all, a bound that cannot fire because the thing it guards outlives it, or
an expiry that produces no operator-visible line.

## Related

- ADR-012 (agent holds `NOPASSWD: ALL` — the privilege context these subprocesses
  run in)
- ADR-021 (convergent steps — why a retry after a timeout is safe)
- ADR-019 (testability seams). The two decisions meet at `Effects`: the bounded,
  symlink-refusing primitives here are what the production `Effects` bag binds,
  and the injected `err` sink is wired to `provision::log::err_sink()` so a
  diagnostic reaching the seam still reaches the transcript. A seam that binds a
  weaker primitive in production — a path-based `chown`, an unbounded
  `Command::status()` — passes every step test and silently undoes this ADR;
  `a_production_ctx_carries_the_real_root_and_effects` exists to catch that.
- `dispatcher.rs`, `pkg.rs`, `statelock.rs`
