# Phase 17: Changes Delivery and Release Candidate - Context

**Gathered:** 2026-05-30
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — 4 grey areas resolved via maintainer decisions

<domain>
## Phase Boundary

Ship the feature-complete v0.3.4 "Aware Installation Process" (Phases 12–16, GATE: GREEN)
to a **maintainer-testable release candidate**, and gate the **final** release on live
brownfield review. This is a delivery/logistics phase — **no new product behavior**. It
re-exercises the existing AGT-02 acceptance (zero-EACCES `claude update`) on the
maintainer's real brownfield VM rather than a fixture.

In scope: version bump to ship-ready, branch polish + integration with diverged master,
PR open, rc-tag push (release.yml), a maintainer validation runbook, a feedback checkpoint,
and a promote-or-iterate decision gate.

Out of scope: any new BHV/RT/AGT/CLI/CAT/INST behavior; the AL-52 host-clone harness
(parked — `--dry-run` judged sufficient); building new aware-install features.
</domain>

<decisions>
## Implementation Decisions

### Execution Boundary (Q1 = Full drive; reconciled with Q2/Q3)
- Go all the way through the shipping pipeline this pass — do NOT stop at a conservative
  "safe-prep-only" boundary.
- The **single human-reserved step** is the PR merge click (per Q2). I do everything up to
  and including opening the PR; the maintainer merges it.
- After the PR is merged to master, I push the `v0.3.4-rc1` tag **without further approval**
  (per Q3 — "you can push it without my approval").
- Net sequence: prep → push branch → open PR → **[maintainer merges]** → I push rc tag →
  release.yml runs → **[maintainer validates rc on VM]** → promote-or-iterate.

### Merge Path (Q2 = PR on GitHub, maintainer merges)
- Branch `worktree-aware-install` is 7 behind / 82 ahead of `master` (merge-base 77043fa).
- Integrate `origin/master`'s 7 commits INTO the branch first (merge master → branch),
  resolve any conflicts, run the suite green — so the PR is conflict-free and CI runs on the
  integrated result. This is the "merge request polishing" step.
- Push the branch to `origin`; open a PR to `master` via `gh` (exercises test.yml /
  pr-preview.yml). Maintainer reviews the full diff and clicks merge.
- No rebase of the 82 commits (merge-commit integration preferred — lower conflict risk).

### Version + RC Tag (Q3 = I push the tag freely; bump to 0.3.4)
- Bump `plugin/cli/package.json` .version and `plugin/catalog/catalog.json` .version
  0.3.2 → **0.3.4** (there was never a 0.3.3; milestone numbering jumped). `build-release.sh`
  strips the rc suffix (`BASE_VERSION=${VERSION%%-*}`), so tag `v0.3.4-rc1` requires base
  **0.3.4** in both files — the 3-way lock.
- **RISK to handle in plan/execute:** grep the repo + tests/fixtures for hardcoded `0.3.2`
  (and any `/opt/agentlinux/catalog/0.3.2/` style coupling) and reconcile so the bats matrix
  + CLI unit tests stay green after the bump. The installer derives version from package.json
  (sed), so most paths propagate automatically — but verify.
- After the PR merges, I push `v0.3.4-rc1` on the merged `master` commit → release.yml
  (`on: push: tags: 'v*.*.*'`) builds the SHA256-verified tarball + .deb and publishes the rc.

### Close Timing + Feedback Gate (Q4 = Defer close until rc validated)
- This pass ends at a **human checkpoint**: the maintainer tests the rc on his real brownfield
  VM (the genuine v0.3.4 acceptance).
- GSD milestone lifecycle (audit → complete → cleanup) and AL-38 / subtask close run ONLY
  AFTER the maintainer confirms the rc is good and we **promote rc → final v0.3.4**
  (push the `v0.3.4` tag). AL-38 close still asks the user first (per anchor memory).
- On "found issues": capture feedback → spin **gap-closure plans inside Phase 17** → re-cut a
  new rc (rc2). Do not close the milestone on negative feedback.
</decisions>

<code_context>
## Existing Code Insights

### Git / remote state (verified 2026-05-30)
- This worktree is on branch `worktree-aware-install` @ `1521989`; main repo `master` @ `ca605ab`.
- Divergence `7 / 82` (master-only / branch-only); merge-base `77043fa`.
- `origin` = `git@github.com:Roo4L/Agent-Linux.git`. SSH push identity = **Roo4L** (verified);
  `gh` CLI authed as Roo4L with `repo` + `admin:public_key` + `write:packages` scopes.
- Branch NOT yet pushed to origin (`git branch -r --contains HEAD` empty).
- Uncommitted now: `.planning/ROADMAP.md`, `.planning/STATE.md`, the new `17-*` phase dir
  (+ this CONTEXT.md). Commit these as part of execution.

### Release tooling
- `scripts/build-release.sh <tag>` — 3-way version lock (tag == package.json == catalog.json,
  rc suffix stripped); `--dry-run` validates the lock without building. Emits tarball +
  sibling `.sha256` + catalog snapshot copy; `SKIP_DEB=1` skips the .deb.
- `.github/workflows/release.yml` — `on: push: tags: 'v*.*.*'` + `workflow_dispatch`. Gate
  sequence enforced by `needs:`; publish job only on real tag push.
- Existing tags: …`v0.3.2`, `v0.3.2-rc1`, `v0.3.2-rc2` (last shipped = v0.3.2). No v0.3.3/v0.3.4 yet.
- Current code/catalog version = `0.3.2` (dry-run printed `agentlinux-install v0.3.2`).

### Verified preview behavior (for the runbook)
- `sudo agentlinux-install --dry-run` → full detection + decision pass, exit 0, ZERO mutation.
- Plain `sudo agentlinux-install` (no `--yes`, non-TTY) → fail-safe: prints the structured
  `[BAIL] component=… reason=… hint=…` block and exits 65 BEFORE mutating anything.
- Real `--yes` install applies remediations; `claude update` is the AGT-02 zero-EACCES check.
- curl-installer forwards flags (`exec "$exe" "$@"`), so `… | sudo bash -s -- --dry-run` works.
</code_context>

<specifics>
## Specific Ideas

- **Maintainer runbook** = a committed doc (e.g. `docs/releases/v0.3.4-rc1-VALIDATION.md`)
  covering, in order: (1) take a VM snapshot; (2) `--dry-run` preview (read the detection +
  any flagged remediate component); (3) the fail-safe no-`--yes` bail to see the structured
  refusal; (4) the real `--yes` install; (5) `claude update` AGT-02 zero-EACCES check +
  version monotonicity; (6) rollback via snapshot if anything looks wrong; (7) how to send
  feedback back. Reference the exact verified invocations from code_context.
- The rc must be installable on the VM the same way the maintainer will use it — prefer the
  curl-pipe-bash path against the published rc tag (mirrors `tests/docker/dogfood.sh`).
- Jira: file the Phase 17 subtask under AL-38 at plan completion (anchor convention). On
  promote-to-final, transition all phase subtasks → Done and ask before closing AL-38.
</specifics>

<deferred>
## Deferred Ideas

- AL-52 host-clone Docker harness — parked in Backlog (decided 2026-05-30; `--dry-run`
  sufficient for go/no-go). Not part of this phase.
- v0.3.5 AlmaLinux port (AL-47 / Epic AL-48) — next milestone, after v0.3.4 ships.
- Decision-plan block in `--dry-run` (Option B from the dry-run review) — not adopted;
  revisit only if the maintainer's review surfaces a need.
</deferred>
