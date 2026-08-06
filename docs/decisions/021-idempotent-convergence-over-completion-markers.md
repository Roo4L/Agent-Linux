# 021: Convergent, self-verifying steps — not per-step completion markers

**Status:** Accepted
**Date:** 2026-07-31

## Context

A reliability review of the provisioner found a real silent-failure bug in step
10 (`provision/agent_user.rs`):

> Run 1 creates the user, then fails at `locale_ensure` → exit 70. Run 2 probes
> the host, sees a user with a bash shell, classifies it `Conforming` → `REUSE`,
> and skips the locale step entirely. Steps 20–50 pass, the installer prints
> `agentlinux-install complete` and exits 0 — with `LANG`/`LC_ALL` never set,
> violating BHV-01.

The failure was permanent (every later run took the same branch for the same
reason) and silent (exit 0 plus a success banner). The review's stated diagnosis:
*"No per-step completion marker exists to prevent it."*

That points at a general design question the codebase had never answered
explicitly. Two ways to make a re-run safe after a partial failure:

1. **Completion markers.** Each step records "I finished" on disk. A re-run reads
   the marker and skips or repeats accordingly. This is what package managers and
   most migration frameworks do.

2. **Convergence.** Each step is idempotent and *verifies its own postcondition*
   on every run, so running it against an already-correct host is a cheap no-op
   and running it against a half-done host repairs it. Nothing needs to remember
   what happened.

The bug is not an argument for (1) specifically — it is an argument against what
the code actually did, which was neither. Step 10 gated three distinct actions
behind one probe that observed only the first of them. The proxy signal (the
user's login shell) became true after action 1 of 3, so failures in actions 2 and
3 were indistinguishable from success forever after.

## Decision

**AgentLinux provisioner steps converge; they do not journal.** Concretely:

- A step's REUSE/skip gate may only cover actions whose completion the gate's own
  probe actually observes. Step 10's gate now covers `useradd` + home ownership
  only — the identity facts `user_state` reads. Locale and the DOC-02 block run on
  every branch.
- Every step is idempotent: re-running it against a correct host changes nothing.
- Every step verifies rather than assumes. `locale_ensure` ends with a `locale -a`
  gate; `nodejs` re-checks the major version after install; `sudoers` runs
  `visudo -cf` before *and* after the install.
- **No step writes a completion marker, and no step reads one.**

The one apparent exception is the NodeSource repo-file gate in
`provision/nodejs.rs`, which short-circuits when a repo file exists. That is not a
completion marker: it is a probe of the exact artefact the action produces, and
the setup script it guards `rm -f`s and recreates those files, so a missed gate
self-heals.

## Consequences

**What this buys.** A marker records what we *believe* happened; a probe observes
what *is*. Markers go stale in ways nothing detects — an operator edits
`/etc/default/locale` by hand, a config-management run reverts a file, a disk
rolls back to a snapshot — and every one of those leaves the marker saying
"done" over a host that is not. Convergence has no such gap: the run after the
damage repairs it. It also means a half-provisioned host is fixed by the obvious
action (run it again), with no `--force`, no marker-clearing flag, and no
"provisioner state is corrupt, delete this directory" support answer.

It is also less code. There is no marker store to create, version, garbage-collect
on `--purge`, or keep consistent with the sentinel store that already exists for a
different purpose.

**What we give up.** Convergence costs work on every run that a marker would skip.
For this provisioner that cost is a handful of probes — `locale -a`, a version
check, a few `stat`s — against a run whose real cost is `apt-get` and `npm`. If a
future step is genuinely expensive AND genuinely un-probeable, this ADR is the
thing to revisit; that step would be the first evidence the trade-off had changed.

**What reviewers should not re-file.** "No completion markers exist" is not a
finding against this codebase — it is this decision. The finding that *is* valid,
and that this ADR does not excuse, is a gate whose probe does not cover the
actions it guards. That is the bug class above, and it is worth flagging every
time.

## Related

- BHV-01 (agent user + `LANG`/`LC_ALL=C.UTF-8`), verified by
  `product/tests/bats/20-agent-user.bats`
- ADR-011 (stability model — `upgrade` reconciles divergence rather than tracking
  it, the same convergent instinct one layer up)
- `provision/agent_user.rs` — the step whose gate this ADR narrowed
