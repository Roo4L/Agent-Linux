---
name: qa-testing
description: Run a scoped, time-boxed integration-QA session against AgentLinux deliverables and co-installed catalog tools.
---

# AgentLinux QA Testing

Use this skill at milestone close, release-candidate review, or on demand for a
specific release, milestone, or phase. It is a judgment-driven integration
session, not a replacement for the bats, Docker, or QEMU gates. It is the
reusable workflow for the Phase 50 `TST-08` integration-QA contract.

## Inputs and session record

Start with the unit under test: a phase, milestone, release candidate, or
explicit feature diff. Set these optional environment controls when useful:

- `QA_ROUND_MINUTES` — duration of one bug-hunting round; default `20`.
- `QA_QUIET_ROUNDS` — consecutive rounds with zero new bugs required to stop;
  default `2`.

Create a report before testing and update it during the session. Every finding
uses this schema:

| Field | Required content |
|---|---|
| ID | Stable finding identifier |
| Severity | blocker, high, medium, low, or observation |
| Scope | `direct` or `adjacent` |
| Repro | Minimal repeatable steps, including install order and invocation mode |
| Evidence | Command output, transcript path, screenshot, or config diff (never secrets) |
| Disposition | Fixed inline, deferred to decimal phase, filed as ticket, or hand-off |
| Residual risk | What remains unproven after the disposition |

## Pillar 1 — Scoped coverage

Derive the test scope from three sources:

1. `git diff` and the files touched by the unit under test.
2. The roadmap goal and success criteria for that phase or milestone.
3. Requirement IDs and their downstream consumers in `REQUIREMENTS.md`.

Put direct deliverables in the heavy bucket: exercise them repeatedly with
different orders, partial states, malformed inputs, retries, and human-style
flows. Put adjacent or possibly impacted surfaces in the lighter bucket: run a
small sanity pass to detect regressions without pretending to re-run every
isolated gate. Record both buckets in the report.

## Pillar 2 — Regression-to-zero stop condition

Do not stop merely because a checklist is complete. Run creative bug-hunting
rounds for `QA_ROUND_MINUTES` minutes. A round that finds one or more *new*
reproducible bugs resets the quiet-round counter to zero. A quiet round
increments it. Stop when `QA_QUIET_ROUNDS` consecutive rounds are quiet and
write `done from my side` with the count and duration in the report. If a
maintainer takes over first, write an explicit hand-off with the remaining
quiet-round count and open risks.

Use the loop as a goal-directed search: after each finding, explore nearby
states and likely regressions before moving on. A duplicate symptom is not a
new bug, but it must be linked to the original finding.

## Pillar 3 — Representative TUI session

At least one session must show what a real user sees:

- Allocate a **real interactive PTY**. Do not use a captured pipe as the only
  evidence; pipes can make prompts look like a frozen script.
- Set `TERM=xterm-256color`, keep color/ANSI enabled, and use default geometry
  that exercises approximately 80-column behavior. Repeat the most important
  flow at a documented wider geometry (for example 120 columns).
- Observe prompts, redraws, live/streaming output, and background work. Record
  the terminal dimensions, TERM, color setting, command, and whether apparent
  freezes resolved while work continued.
- Reuse `tests/bats/helpers/tty-driver.py` or the interactive session in
  `tests/docker/rc-sandbox.sh`; preserve its prompt-sentinel and timeout
  behavior instead of inventing a pipe-based substitute.

## Co-install integration matrix

Use fresh disposable environments for each order-sensitive scenario. At
minimum, drive these combinations in both relevant install orders:

1. `gsd` + `codex`: verify both commands, PATH ownership, version/pin behavior,
   and skill/config coexistence.
2. A coding agent + a fan-out MCP provider, such as `codex` + `github-mcp`:
   verify registration into the installed agent set, then install the second
   coding agent and verify reverse-trigger reconciliation produces the same
   final set.
3. A `[bin]` + `[npm]` + `[daemon]` mix, such as `rtk` + `gsd` + `openclaw`:
   verify agent-owned paths, config isolation, no `/usr/local` shim, and the
   daemon/config path. Docker may be unable to prove per-user systemd; mark
   that part QEMU-gated rather than calling it green.

For each combination, remove one member while a sibling remains installed,
then remove the rest. Assert the sibling still resolves, its config remains,
and the removed tool leaves no cross-tool residue. Also run `list` and
`list --by-category` at the default terminal width and inspect both text and
JSON forms where applicable.

## Credentials, harness boundaries, and handback

Credentials are runtime-only. Pass them through the environment of the smoke
process; never write values into a recipe, catalog, image, skill, report, or
command transcript. A missing credential is a clean skip, and the report names
the skipped provider without recording its value.

Use Docker for fast disposable co-install, CLI, wiring, and UX checks. Docker
does not reproduce every systemd-user/logind behavior. The QEMU harness is the
release-level authority for daemon lifecycle and other VM-only paths. Report
which invocation modes were covered (interactive login, non-interactive shell,
SSH, cron/systemd, sudo-user variants as applicable) and which were not.

## Required handback

End every session with a Markdown report containing:

```markdown
## Session outcome
- Unit under test:
- Stop signal: done from my side after N quiet rounds | maintainer hand-off
- Harnesses and dates:

## Findings
| ID | Severity | Scope | Repro | Evidence | Disposition | Residual risk |
|---|---|---|---|---|---|---|

## Coverage limits
- Combinations and install orders:
- Invocation modes:
- Credentialed paths run/skipped:
- Docker coverage:
- QEMU coverage:
- Explicitly not tested:
```

Route every finding to an inline fix, a decimal phase, an AL ticket, or an
explicit maintainer hand-off. The report must not claim “tested everything.”
