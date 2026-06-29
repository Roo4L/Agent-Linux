---
name: planning-workflow
description: How GSD `.planning/` files are managed in git for this repo. Intermediate working state (loose `phases/`, `quick/`, `quick-archive/`, in-flight `REQUIREMENTS.md`) lives on a feature branch and is stripped before merge; master carries only the durable record — the `MILESTONES.md` ledger, the per-milestone `milestones/` archive, and the GSD cursor files (`STATE.md`/`ROADMAP.md`/`PROJECT.md`/`RETROSPECTIVE.md`/`config.json`, `research/`, `todos/`). Invoke before merging a branch that touched `.planning/` to bring it to the clean state the CI gate (`scripts/check-planning-clean.sh`) enforces.
---

# /planning-workflow — GSD `.planning/` on git

GSD (`/gsd-*`) writes a lot of working state into `.planning/` as phases and
quick tasks run. Without a policy that churn accumulates on `master`. This skill
is the policy: **intermediate state lives on a feature branch; `master` carries
only the durable record.** The CI gate at `scripts/check-planning-clean.sh` is
the backstop; this skill is how you stay on its good side.

## Classification

Every path under `.planning/` is one of three kinds.

| Kind | Paths | On `master`? | Mechanism |
|---|---|---|---|
| **Durable** | `MILESTONES.md`, `PROJECT.md`, `ROADMAP.md`, `RETROSPECTIVE.md`, `STATE.md`, `config.json`, `milestones/`, `research/`, `todos/` | Yes — the record | Committed and kept. `STATE.md` must read `status: complete` — see the close-out. |
| **Intermediate** | `phases/`, `quick/`, `quick-archive/`, in-flight `REQUIREMENTS.md` | No | Committable on the feature branch (so work survives across sessions and `/gsd-quick resume`), **stripped before merge**. |
| **Transient** | `.continue-here.md`, `HANDOFF.json`, `tmp/`, `reports/`, `.active-skill`, `.phase-manifest.json` | No | `.gitignore`d — never committed anywhere. |

`MILESTONES.md` is the system of record for each shipped milestone: version, ship
date, phases, accomplishments, deferred items. The `milestones/` archive (per-milestone
`ROADMAP`/`REQUIREMENTS`/`AUDIT` snapshots, plus historical phase archives) is
kept as-is — `/gsd-complete-milestone` writes there and that output stays.

## Why not just `.gitignore` `phases/` and `quick/`?

`.gitignore` is all-or-nothing — it can't allow a path on a branch but block it on
`master`. Phase and quick-task work must stay committable so it survives
session/worktree handoff (`/gsd-quick resume`), so it's removed at merge and the
gate enforces its absence instead. Only the genuinely-local transient files are
gitignored.

## Pre-merge close-out

Run this before opening/merging a PR whose branch touched `.planning/`.

### Milestone branch (a milestone was completed on this branch)

1. Run `/gsd-complete-milestone <version>`. It updates `MILESTONES.md` /
   `PROJECT.md` / `STATE.md` / `ROADMAP.md` and writes the
   `milestones/v<version>-*` snapshots (kept).
2. Ensure no **loose** working dirs remain: `.planning/phases/` and
   `.planning/quick/` must be empty/absent on the branch tip. Either archive the
   phases into `milestones/v<version>-phases/` (answer "yes" to the archive
   prompt) or `git rm` them — either way no loose `phases/` reaches `master`.
3. Confirm `STATE.md` frontmatter reads `status: complete`.

### Quick-task branch (a `/gsd-quick` task)

1. Make sure the task's outcome is recorded as a one-line row in the
   **Quick Tasks Completed** table in `STATE.md` (description, date, commit SHA).
   That row — not the working dir — is the durable record.
2. `git rm -r .planning/quick/<task-dir>` (and any stale `quick-archive/`).
3. Confirm `STATE.md` frontmatter reads `status: complete`.

### Verify locally

```bash
bash scripts/check-planning-clean.sh && echo "planning clean"
```

## What the CI gate checks

`scripts/check-planning-clean.sh` runs in `.github/workflows/test.yml` on PRs to
`master`. It fails the merge when:

- any entry tracked under `.planning/` is outside the **Durable** allowlist
  above (i.e. a loose `phases/`, `quick/`, `quick-archive/`, in-flight
  `REQUIREMENTS.md`, or a stray top-level `*-MILESTONE-AUDIT.md` is present), or
- `STATE.md` frontmatter `status` is not `complete`.

It reads the tracked tree (`git ls-files`), so gitignored transient files are
invisible to it and a force-added one is caught.

## Relationship to `workspace-cleanup`

`/workspace-cleanup` (end-of-session worktree wrap-up) defers to this skill for
`.planning/` handling: it never routes intermediate `.planning/` state to
`master` — it runs the close-out above so the branch is gate-clean before the PR
merges.

## When NOT to use

- Mid-milestone work on a feature branch — intermediate state *should* be
  committed there; only close out before the merge.
- Branches that don't touch `.planning/` — the gate passes trivially.
