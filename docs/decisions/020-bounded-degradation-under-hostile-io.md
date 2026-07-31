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
   the timeouts exist to remove. `list` takes no lock — serializing the command
   people run to find out what is happening would be a regression.

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
not a defence against a hostile process and nothing treats it as one.

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
