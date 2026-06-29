---
name: workspace-cleanup
description: Use at the end of a worktree session — before the user deletes the worktree — to catch stray changes outside the feature scope (`.planning/` GSD files, `.claude/skills/`, `.claude/agents/`, `.claude/settings*.json`, hooks, user memories), decide where they belong (feature PR vs side commit vs main worktree), push, open or update the PR, merge after user approval, and refresh the main worktree from origin. Never deletes the worktree itself — the user handles that.
---

# /workspace-cleanup — End-of-Session Worktree Cleanup

Triggered at the end of a feature session inside a git worktree, before the user removes the worktree manually. Catches incidental changes that aren't part of the feature (GSD state, project-scoped skills/agents, hooks, settings, memories) so they don't get lost when the worktree disappears, then ships the PR cleanly.

## What this skill does

1. **Detect** — find every change in the worktree across both feature and non-feature scopes (committed, uncommitted, and unpushed).
2. **Classify** — split changes into `feature` (belongs in PR), `infra` (belongs back in `master`), and `local-only` (memories, lock files).
3. **Decide with the user** — surface the classification, ask whether infra changes ride with the feature PR or get their own commit on `master`.
4. **Ship** — commit, push, open or update the PR, wait for CI, merge after the user confirms.
5. **Refresh** — fetch + fast-forward the main worktree (`/home/agent/agent-linux/`) so it sees the merged work.

## What this skill never does

- **Never deletes the worktree.** The user removes it after exiting the Claude Code session.
- **Never force-pushes to `master`.** Infra changes that go straight to `master` are normal commits with `git push origin master`.
- **Never merges without explicit user confirmation.** Surface the PR URL + merge plan, ask, then merge.
- **Never drops uncommitted changes.** If a file was modified but isn't going anywhere, stop and ask.

## Step-by-step procedure

### 1. Establish where we are

```bash
git worktree list                  # confirm we're in a worktree, not the main checkout
git rev-parse --show-toplevel      # current worktree root
git rev-parse --abbrev-ref HEAD    # current branch
git status --porcelain             # uncommitted files
git log --oneline @{u}..HEAD 2>/dev/null   # unpushed commits (if upstream exists)
git log --oneline master..HEAD     # commits this branch adds beyond master
```

If we're in the main worktree (`/home/agent/agent-linux/`) — abort. This skill only runs from a feature worktree.

### 2. Inventory every change against `master`

Run a single diff that covers both committed and working-tree state:

```bash
git diff --name-status master...HEAD              # committed-only diff vs master
git status --porcelain                             # uncommitted (working tree + index)
```

Classify each path into one of three buckets. Default rules — adjust per user input:

| Path pattern | Bucket | Notes |
|---|---|---|
| `plugin/`, `tests/`, `packaging/`, `docs/`, `scripts/`, `.github/`, top-level repo files | **feature** | Belongs in this PR. |
| `.planning/` durable (`MILESTONES.md`, `PROJECT.md`, `ROADMAP.md`, `RETROSPECTIVE.md`, `STATE.md`, `config.json`, `milestones/`, `research/`, `todos/`) | **feature** — rides with the PR | The durable GSD record. Commit it on the branch with the rest of the work (after the `planning-workflow` close-out sets `STATE.md` `status: complete`). |
| `.planning/` intermediate (loose `phases/`, `quick/`, `quick-archive/`, in-flight `REQUIREMENTS.md`) | **strip before merge** | Must NOT reach `master`. Run the `planning-workflow` close-out (`/gsd-complete-milestone`, or `git rm` the loose dirs) so the branch is gate-clean. Never route these to `master`. |
| `.planning/` transient (`.continue-here.md`, `HANDOFF.json`, `tmp/`, `reports/`, `.active-skill`, `.phase-manifest.json`) | **ignore** | `.gitignore`d — never staged. |
| `.claude/skills/**`, `.claude/agents/**`, `.claude/settings*.json`, `.claude/hooks/**` | **infra** | Tooling improvements made mid-session — should land on `master` separately so every worktree picks them up. |
| `.claude/worktrees/**` | **ignore** | Other worktrees' state — never include. |
| `~/.claude/projects/-home-agent-agent-linux/memory/**` | **local-only** | Lives in `$HOME`, not in the repo, already shared across worktrees. Mention it; do not commit it. |

Memories are not in the repo — they sit at `/home/agent/.claude/projects/-home-agent-agent-linux/memory/`. List recent edits with `find ~/.claude/projects/-home-agent-agent-linux/memory -mtime -7 -type f` for visibility, but never stage them.

### 3. Surface the classification to the user

Print a compact report. Example:

```
Feature changes (10 files, 3 commits) — destined for PR #123
Infra changes (.claude/skills/review/SKILL.md, .claude/agents/qa-engineer.md) — destination?
  a) bundle into the feature PR
  b) separate commit straight on master
  c) skip (leave for another session)
Memory edits (2 files in ~/.claude/.../memory) — already shared, no action needed
Uncommitted: tests/foo.bats (M) — what do you want to do with this?
```

Ask the user to pick a destination for each non-feature item before proceeding. Do not assume.

### 4. Apply the user's decisions

For each bucket:

- **Feature PR (single branch path).** Stage feature files, commit if uncommitted, push:
  ```bash
  git add <feature paths>
  git commit -m "<message>"
  git push -u origin HEAD
  ```
- **Infra straight to master.** Stash the worktree state, switch the **main worktree** to `master`, apply the infra changes there as a fresh commit, push:
  ```bash
  # from the feature worktree, copy diffs into a patch.
  # NOTE: .planning/ is NOT routed to master here — see the planning-workflow
  # skill. Durable .planning/ record changes ride with the feature PR;
  # intermediate state is stripped before merge, never side-committed to master.
  git diff master...HEAD -- .claude/skills .claude/agents > /tmp/infra.patch
  # then in the main worktree
  git -C /home/agent/agent-linux switch master
  git -C /home/agent/agent-linux pull --ff-only origin master
  git -C /home/agent/agent-linux apply /tmp/infra.patch
  git -C /home/agent/agent-linux add <paths>
  git -C /home/agent/agent-linux commit -m "chore: infra updates from <branch>"
  git -C /home/agent/agent-linux push origin master
  ```
  Drop the same paths from the feature branch with `git restore --source=master --staged --worktree -- <paths>` before pushing the feature branch, so the PR diff stays clean.
- **Bundle into PR.** Just stage and commit on the feature branch alongside the feature commits.

### 5. Open or update the PR

```bash
gh pr view --json url,state,mergeable,statusCheckRollup 2>/dev/null \
  || gh pr create --fill   # or with explicit title/body if context warrants
```

If the PR exists, push the new commits and let the existing PR pick them up. If a PR description was already drafted in this session, update it with `gh pr edit --body-file -` only if the scope materially changed.

### 6. Wait for CI, then ask before merging

```bash
gh pr checks --watch
```

Once green, surface to the user: "PR #N is green and mergeable. Merge with squash/rebase/merge?" Wait for explicit confirmation. Then:

```bash
gh pr merge --squash --delete-branch=false   # never delete the branch — worktree still references it
```

`--delete-branch=false` is critical. Deleting the remote branch with the worktree still checked out leaves the worktree in a broken state. The user will clean up the branch when they remove the worktree.

### 7. Refresh the main worktree

```bash
git -C /home/agent/agent-linux fetch origin --prune
git -C /home/agent/agent-linux switch master 2>/dev/null || true
git -C /home/agent/agent-linux pull --ff-only origin master
```

If the main worktree has uncommitted changes or isn't on `master`, don't force a switch — print a warning and skip the pull. The user can resolve it manually.

### 8. Final report

Print a short summary:

- PR URL + merge SHA
- Infra commits (if any) pushed straight to `master`
- Memory files touched (informational, no action)
- Main worktree state (`master` at SHA, clean / dirty)
- Reminder: **worktree at `<path>` is preserved — remove it manually when you exit Claude Code.**

## Edge cases

- **Worktree branch already merged.** `gh pr view` shows `MERGED`. Skip steps 4–6, jump to step 7.
- **No PR exists yet but commits are unpushed.** Push first, then `gh pr create --fill`.
- **CI is red.** Stop. Report which check failed. Do not merge. Ask the user how to proceed.
- **Conflicts when applying the infra patch on `master`.** Stop. Don't `--reject` or force. Show the conflict; let the user resolve in the main worktree.
- **`.planning/` changes are present.** Follow the `planning-workflow` skill: durable record files ride with the PR; intermediate state (loose `phases/`, `quick/`, in-flight `REQUIREMENTS.md`) is stripped before merge so it never reaches `master`; transient session files are gitignored. Do not route intermediate `.planning/` state to `master` as "infra". Verify with `bash scripts/check-planning-clean.sh` before merging.
- **`.claude/settings.local.json` shows up in changes.** This file is per-user and should be `.gitignore`d. If it's tracked by accident, flag it and ask before committing.

## Reference paths

- Feature worktree (current): from `git rev-parse --show-toplevel`
- Main worktree: `/home/agent/agent-linux/`
- User memories (not in repo, shared across worktrees): `/home/agent/.claude/projects/-home-agent-agent-linux/memory/`
- Other worktrees (don't touch): `/home/agent/agent-linux/.claude/worktrees/`

## When NOT to use this skill

- The user is mid-session, not wrapping up.
- The PR is already merged AND the main worktree is already up to date — nothing to do.
- The current directory is the main worktree, not a feature worktree.
