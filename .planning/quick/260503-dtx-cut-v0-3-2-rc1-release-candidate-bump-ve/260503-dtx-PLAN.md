---
quick_id: 260503-dtx
description: Cut v0.3.2-rc1 release candidate (bump versions, push tag, document Docker dogfood test)
status: planned
date: 2026-05-03
jira: AL-18
---

# Quick Task 260503-dtx: v0.3.2-rc1 Release Candidate

## Context

- Last release: **v0.3.1** (2026-05-02). First dogfood test against v0.3.1 failed.
- Fixes shipped to master since v0.3.1 (9 commits): PR #7 (three dogfood-discovered installer-path bugs), PR #5 (Ubuntu 26.04), PR #11 (Node 24-ready actions), PR #13 (review-reminder Stop hook + ADR-010 refinement), PR #14 (workspace-cleanup skill), plus CI deploy fixes (#9, #10) and PR-preview workflow (#4).
- A dangling `release/v0.4.1-rc1-bump` branch exists locally (bumped to 0.4.1) — superseded by user's choice of v0.3.2-rc1 (patch-level).
- AL-18 follow-up: cut a new RC, run Docker-based dogfood against it.
- User decisions:
  - Version: **v0.3.2-rc1** (patch bump)
  - Action: **Bump + push tag** (full release-pipeline flow via `release.yml`)

## Constraints

- `scripts/build-release.sh` enforces a three-way version lock: tag base (`0.3.2`) MUST equal `plugin/cli/package.json.version` AND `plugin/catalog/catalog.json.version`. The `-rc1` suffix is stripped before comparison (see `fix(build): allow rc / pre-release suffix in tag↔package.json version lock`).
- Tag shape regex (curl-installer + release.yml): `^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$` — `v0.3.2-rc1` matches.
- `release.yml` triggers on `push: tags: 'v*.*.*'` → runs gate-1-precommit, gate-2-docker (22.04 + 24.04), gate-3-qemu, gate-4-pinned-combo, build, publish.
- Discard the dangling `release/v0.4.1-rc1-bump` branch — versions there target a different minor.
- Tag push is irreversible. User explicitly authorized.

## Tasks

### Task 1 — Bump versions to 0.3.2

**Files:**
- `plugin/cli/package.json` (`"version": "0.3.0"` → `"0.3.2"`)
- `plugin/catalog/catalog.json` (`"version": "0.3.0"` → `"0.3.2"`)

**Action:** Two single-line `Edit` calls.

**Verify:**
- `node -e 'console.log(require("./plugin/cli/package.json").version)'` prints `0.3.2`
- `jq -r .version plugin/catalog/catalog.json` prints `0.3.2`

**Done when:** Both files report `0.3.2`.

---

### Task 2 — Open release PR against master

**Action:**
1. Switch from `worktree-first-release` to a fresh branch `release/v0.3.2-rc1-bump` based on `origin/master`.
2. Stage + commit the two version-bump files only.
3. Push branch.
4. Open PR with `gh pr create` titled `chore(release): bump version to 0.3.2 for rc1 release`.
5. Wait for CI green (or surface the PR URL if user wants to gate manually).

**Verify:**
- `gh pr view --json mergeable,statusCheckRollup` reports `MERGEABLE` and all required checks `SUCCESS`.

**Done when:** PR is merged into master.

---

### Task 3 — Build release artifacts locally (verification)

**Action:**
After bump is merged to master, on a master checkout, run:
```
scripts/build-release.sh v0.3.2-rc1
```

**Verify:**
- `dist/agentlinux-v0.3.2-rc1.tar.gz` exists
- `dist/agentlinux-v0.3.2-rc1.tar.gz.sha256` exists
- `dist/catalog-v0.3.2-rc1.json` exists
- `(cd dist && sha256sum -c agentlinux-v0.3.2-rc1.tar.gz.sha256)` reports `OK`
- Re-run produces byte-identical tarball (reproducibility, T-06-08)

**Done when:** Artifacts exist and sha256 round-trip passes.

---

### Task 4 — Tag v0.3.2-rc1 + push to origin

**Action:**
On master at the merge commit:
```
git tag -a v0.3.2-rc1 -m "v0.3.2-rc1 — RC for AL-18 dogfood retest

Patch on top of v0.3.1 carrying:
- PR #7 — three dogfood-discovered installer-path bugs (curl-installer ORG default,
  --purge sudoers cleanup, GSD + Playwright CLI skill bootstrap wiring,
  AGENTLINUX_AGENT_HOME export during purge, playwright-cli cd to writable home).
- PR #5 — Ubuntu 26.04 (Resolute Raccoon) added to v0.3.0 supported targets.
- PR #11 — bump GitHub Actions to Node 24-ready versions.
- PR #13 — review-reminder Stop hook + ADR-010 refinement (AL-23).
- PR #14 — workspace-cleanup skill.
- PR #4/#9/#10 — CI / website deploy fixes.

Refs: AL-18"
git push origin v0.3.2-rc1
```

**Verify:**
- `git ls-remote --tags origin v0.3.2-rc1` returns the tag SHA.
- GitHub Actions release workflow run appears for the tag (`gh run list --workflow=release.yml --limit 1`).

**Done when:** Tag pushed, release.yml run triggered.

---

### Task 5 — Document Docker dogfood test instructions

**Action:** Write `${QUICK_DIR}/260503-dtx-SUMMARY.md` containing two dogfood paths the user can copy-paste:

1. **Path A (production-realistic) — curl-pipe-bash against the published RC**, gated on the GitHub Release being live. Uses `tests/docker/Dockerfile.ubuntu-{22.04,24.04,26.04}` plus `AGENTLINUX_VERSION=v0.3.2-rc1` to override.
2. **Path B (pre-publish) — local tarball harness**, runnable as soon as `dist/` is populated. Uses `tests/docker/run.sh` directly.
3. Include the canonical Claude Code self-update assertion (AGT-02) so the dogfood probes the exact bug class AgentLinux exists to eliminate.

**Done when:** SUMMARY.md exists with copy-pasteable commands for at least Ubuntu 22.04 + 24.04.

---

### Task 6 — Commit artifacts + STATE.md update

**Files:**
- `.planning/quick/260503-dtx-cut-v0-3-2-rc1-release-candidate-bump-ve/260503-dtx-PLAN.md`
- `.planning/quick/260503-dtx-cut-v0-3-2-rc1-release-candidate-bump-ve/260503-dtx-SUMMARY.md`
- `.planning/STATE.md` (append row to "Quick Tasks Completed" + update `Last activity`)

**Action:**
```
gsd-sdk query commit "docs(quick-260503-dtx): cut v0.3.2-rc1 release candidate" \
  .planning/quick/260503-dtx-cut-v0-3-2-rc1-release-candidate-bump-ve/260503-dtx-PLAN.md \
  .planning/quick/260503-dtx-cut-v0-3-2-rc1-release-candidate-bump-ve/260503-dtx-SUMMARY.md \
  .planning/STATE.md
```

**Done when:** Single commit lands containing all three files.

## must_haves

- truths:
  - `plugin/cli/package.json.version == "0.3.2"`
  - `plugin/catalog/catalog.json.version == "0.3.2"`
  - `git ls-remote --tags origin v0.3.2-rc1` returns a SHA on master
  - `release.yml` workflow run exists for tag `v0.3.2-rc1`
- artifacts:
  - PR (chore(release): bump version to 0.3.2 for rc1 release) merged into master
  - `dist/agentlinux-v0.3.2-rc1.tar.gz{,.sha256}` (locally, optional after publish)
  - `${QUICK_DIR}/260503-dtx-SUMMARY.md` with Docker dogfood instructions
- key_links:
  - `scripts/build-release.sh`
  - `.github/workflows/release.yml`
  - `tests/docker/run.sh`
  - `packaging/curl-installer/install.sh`
  - `plugin/cli/package.json`
  - `plugin/catalog/catalog.json`
