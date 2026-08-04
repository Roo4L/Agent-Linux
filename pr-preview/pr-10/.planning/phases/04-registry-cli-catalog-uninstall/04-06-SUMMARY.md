---
phase: 04-registry-cli-catalog-uninstall
plan: 06
subsystem: installer
tags: [bash, provisioner, installer, purge, teardown, docker, multi-stage]

# Dependency graph
requires:
  - phase: 02-installer-foundation-agent-user
    provides: agentlinux-install entrypoint, agent user + /etc/profile.d+.env+cron.d PATH wiring, idempotency primitives
  - phase: 03-nodejs-runtime-npm-prefix
    provides: Node.js 22 LTS via NodeSource, /home/agent/.npm-global/bin on agent PATH
  - phase: 04-registry-cli-catalog-uninstall (plans 01-05)
    provides: compiled CLI (plugin/cli/dist/index.js + commands/{list,install,remove,upgrade,pin}); catalog.json + agents/<id>/*.sh recipes
provides:
  - 50-registry-cli.sh provisioner stages CLI bundle (dist + node_modules + package.json) under /opt/agentlinux/cli/<ver>/
  - Catalog snapshot staged under /opt/agentlinux/catalog/<ver>/ (CAT-01/CAT-03)
  - State dir /opt/agentlinux/state/installed.d/ (0755 agent:agent, empty per CAT-02)
  - Agent-PATH symlink /home/agent/.npm-global/bin/agentlinux -> dist/index.js (CLI-01)
  - Real --purge with 7-step ordered teardown replacing the Phase 2 stub (INST-04)
  - --remove-nodejs opt-in flag (Node removal gated; default leaves Node installed)
  - Docker test images pre-build the CLI bundle via multi-stage node:22-slim builder
affects: [phase-05-agents, phase-06-release]

# Tech tracking
tech-stack:
  added:
    - "node:22-slim (Docker builder stage only)"
    - "pnpm prune --prod (strip devDeps before shipping node_modules)"
  patterns:
    - "Multi-stage Docker build: heavy Node build in builder; final test image stays Ubuntu-pure"
    - "Pre-built bundle splice: Dockerfile publishes /opt/cli-prebuilt/{dist,node_modules,package.json}; run.sh splices into /opt/agentlinux-src before installer runs"
    - "as_user invocation shape: sudo `--` terminator built into the function; callers MUST NOT prepend their own `--`"

key-files:
  created:
    - "plugin/provisioner/50-registry-cli.sh (135 lines; stages CLI bundle + catalog + state dir + symlink)"
    - ".planning/phases/04-registry-cli-catalog-uninstall/04-06-SUMMARY.md (this file)"
  modified:
    - "plugin/bin/agentlinux-install (+134/-24): --purge moves out of pre_parse_args stub into parse_args+main() real 7-step teardown; --remove-nodejs opt-in; fixes as_user double-dash in uninstall.sh dispatch"
    - "tests/docker/Dockerfile.ubuntu-22.04 (+53): multi-stage cli-builder FROM node:22-slim; COPY --from=cli-builder {dist,node_modules,package.json} into /opt/cli-prebuilt/"
    - "tests/docker/Dockerfile.ubuntu-24.04 (+53): same"
    - "tests/docker/run.sh (+30): build context -> $REPO_ROOT; splice step copies /opt/cli-prebuilt/* into /opt/agentlinux-src/plugin/cli/ before installer runs"

key-decisions:
  - "CLI bundle trio (dist + node_modules + package.json) staged under /opt/agentlinux/cli/<ver>/ — Node ESM resolver walks up from dist/index.js to find sibling node_modules/; package.json carries 'type: module'"
  - "Multi-stage Docker build keeps final test image Ubuntu-pure (installer's own NodeSource setup runs at RUNTIME — that's what's under test, not a build-time dependency)"
  - "pnpm prune --prod in builder stage strips devDeps (typescript, biome, @types/*) before COPY — minimizes the node_modules we ship"
  - "tests/docker/run.sh build context changed from tests/docker/ to repo root — required so the builder stage can COPY plugin/cli/*"
  - "Symlink target is /opt/agentlinux/cli/<ver>/dist/index.js (not the versioned dir itself); ln -sfn + chown -h is idempotent and secure"
  - "--purge step ordering: per-agent uninstall.sh FIRST (needs catalog still present), log removal LAST (Pitfall 7: tee sees EOF on EXIT trap, unlinked inode GC'd)"
  - "--remove-nodejs is opt-in (T-04-17): other users on the host may depend on Node that this installer installed"
  - "Recipe paths derive from $AGENTLINUX_VERSION (entrypoint-controlled) + sentinel filename via basename — NO grep/eval on JSON contents (a tampered sentinel cannot pick arbitrary scripts to execute)"

patterns-established:
  - "CLI bundle staging trio: a shipped Node CLI ALWAYS needs dist + node_modules + package.json; staging only dist/ fails at first 'import'"
  - "Docker multi-stage pre-build + run.sh splice: works around bind-mount :ro constraints + gitignored build outputs"
  - "as_user caller shape: verbatim command + args after the user name; NO caller `--` (as_user.sh's sudo line already appends --)"
  - "--purge log removal LAST: tee's FD stays open; unlink leaves inode alive; EXIT trap delivers EOF; inode GC'd on process exit"

requirements-completed: [CLI-01, INST-04]

# Metrics
duration: 58min
completed: 2026-04-19
---

# Phase 4 Plan 06: Provisioner 50-registry-cli + --purge teardown + Docker multi-stage CLI build Summary

**CLI-01 (agent-PATH agentlinux CLI) + INST-04 (real --purge teardown) land end-to-end: `agentlinux --version` returns 0.3.0 as agent user in a fresh Docker image, `agentlinux list` prints the 3-entry catalog, and `./tests/docker/run.sh ubuntu-{22,24}.04` both pass all 27 existing bats with no regressions.**

## Performance

- **Duration:** 58 min
- **Started:** 2026-04-19T11:42:28Z
- **Completed:** 2026-04-19T12:40:56Z
- **Tasks:** 3 (plus 2 Rule 1/2 auto-fix deviations folded into a single fix commit)
- **Files modified:** 5 (1 created: 50-registry-cli.sh; 4 modified: agentlinux-install, 2 Dockerfiles, run.sh)

## Accomplishments

- **50-registry-cli.sh provisioner** stages the CLI bundle trio (dist/ + node_modules/ + package.json) under `/opt/agentlinux/cli/0.3.0/`, the catalog snapshot under `/opt/agentlinux/catalog/0.3.0/`, and the empty state dir at `/opt/agentlinux/state/installed.d/` (0755 agent:agent, per CAT-02 "installed.d is empty on fresh install"). Creates the agent-PATH symlink `/home/agent/.npm-global/bin/agentlinux -> dist/index.js` via `ln -sfn + chown -h`.
- **agentlinux-install --purge** now runs a real 7-step ordered idempotent teardown — not the Phase 2 print-and-exit stub. Per-agent uninstall.sh runs FIRST (needs catalog still present); log removal is LAST (Pitfall 7: tee-EOF sequencing). `--remove-nodejs` flag gates apt-purge on Node.
- **Docker test images** (ubuntu-22.04 + ubuntu-24.04) pre-build the CLI bundle via a multi-stage `cli-builder` stage (FROM node:22-slim; corepack + pnpm install --frozen-lockfile + pnpm run build + pnpm prune --prod). `tests/docker/run.sh` splices the pre-built bundle into the staged source tree before running the installer, working around the gitignored `plugin/cli/dist/` and `plugin/cli/node_modules/`.
- **End-to-end smoke confirmed**: fresh image -> installer runs 10-agent-user -> 30-nodejs -> 40-path-wiring -> 50-registry-cli; agent user can invoke `agentlinux --version` (returns 0.3.0), `agentlinux list` (prints 3-agent table: claude-code, gsd, playwright — all `not-installed` per CAT-02); all 27 existing bats pass on both Ubuntu 22.04 and 24.04 (no regressions).

## Task Commits

Each task committed atomically under the `04-06` prefix:

1. **Task 1: 50-registry-cli.sh provisioner** — `34dc39a` (feat): stages CLI + catalog + state dir + symlink (CLI-01)
2. **Task 2: agentlinux-install --purge real teardown** — `b6a6be9` (feat): 7-step ordered teardown replacing Phase 2 stub (INST-04); --remove-nodejs opt-in flag
3. **Task 3: Docker multi-stage CLI pre-build** — `5fd4677` (feat): Dockerfiles 22.04+24.04 + run.sh; pre-built dist/+node_modules/+package.json COPYed from node:22-slim builder; run.sh splice step

**Deviation fix commit (between Tasks 2 and 3):**
- `f4d76bb` (fix): as_user caller shape (Rule 1 - bug) + CLI bundle staging (Rule 2 - missing critical functionality). See Deviations section below.

## Files Created/Modified

- `plugin/provisioner/50-registry-cli.sh` (NEW, 135 lines) — stages CLI bundle trio + catalog snapshot + state dir + agent-PATH symlink; sanity-checks all three source paths; uses ensure_dir for every directory for INST-02 idempotency.
- `plugin/bin/agentlinux-install` (MODIFIED, +134/-24) — Moves --purge out of pre_parse_args stub into parse_args+main() where it runs AFTER require_root. Adds `run_purge()` with 7-step ordered teardown; adds `--remove-nodejs` opt-in flag; updates `usage()` to document both new flags.
- `tests/docker/Dockerfile.ubuntu-22.04` (MODIFIED, +53) — Multi-stage cli-builder FROM node:22-slim; COPY builder's dist+node_modules+package.json into /opt/cli-prebuilt/.
- `tests/docker/Dockerfile.ubuntu-24.04` (MODIFIED, +53) — Same.
- `tests/docker/run.sh` (MODIFIED, +30) — Build context changed to $REPO_ROOT (from $HERE) so builder can COPY plugin/cli/; added splice step after source staging to populate plugin/cli/{dist,node_modules,package.json} from /opt/cli-prebuilt/.

## Decisions Made

### Decision: CLI bundle = trio, not just dist/

The plan's initial design (per RESEARCH §Pattern 1) staged only `plugin/cli/dist/`. That's insufficient — compiled `dist/index.js` contains ESM imports (`commander`, `ajv`, `semver`) that Node's resolver looks for in a sibling `node_modules/`. Without it, the very first invocation crashes with `ERR_MODULE_NOT_FOUND: Cannot find package 'commander'`.

**Fix applied (Rule 2 auto-fix during Docker smoke):** stage a trio — `dist/ + node_modules/ + package.json` — under `/opt/agentlinux/cli/<ver>/`. Layout rationale:

```
/opt/agentlinux/cli/0.3.0/
├── dist/           # tsc output (runtime JS with ESM imports)
│   └── index.js    # entrypoint (#!/usr/bin/env node)
├── node_modules/   # pnpm-pruned production deps (ajv, commander, semver, ...)
└── package.json    # "type": "module" makes dist/*.js ESM; declares deps
```

Node's ESM resolver walks up from `dist/index.js` and finds `../node_modules/commander/package.json`. Resolves cleanly. `package.json`'s `"type": "module"` applies to everything under the versioned dir.

### Decision: Multi-stage Docker build over single-stage

Two options considered:
1. **Single-stage**: install Node + corepack + pnpm in the Ubuntu test image at build-time; run `pnpm install + pnpm run build` inside the final image. Simple but pollutes the test substrate with Node BEFORE the installer runs — breaks the invariant that the installer's own NodeSource setup is what gets tested.
2. **Multi-stage** (chosen): `FROM node:22-slim AS cli-builder` does the build; final Ubuntu test image is Node-free and Node installation is done by the installer's own 30-nodejs.sh provisioner at RUNTIME. This keeps the test substrate faithful — the installer installs Node, not Docker.

### Decision: tests/docker/run.sh build context change

Plan's prescribed Dockerfile pattern (`COPY plugin/cli/src ./src` in the builder stage) requires the build context to include `plugin/cli/`. The existing run.sh used `$HERE` (tests/docker/) as context so the image stayed small. This was a **Rule 3 auto-fix** (blocking issue: without the change, `docker build` fails with `COPY: failed to compute cache key: "/plugin/cli/src": not found`).

Fix: build context -> `$REPO_ROOT`. The final image is still small — only the compiled bundle gets COPYed from the throwaway builder layer into the final stage.

### Decision: --purge 7-step ordering with log-removal LAST

Sequence (per RESEARCH §Pattern 10 + §Pitfall 7):

1. Iterate `/opt/agentlinux/state/installed.d/*.json`; run each agent's `uninstall.sh` via `as_user` — MUST come before step 2 because the recipe files live under `/opt/agentlinux/catalog/`
2. `rm -rf /opt/agentlinux/` (literal absolute path — no `$VAR`)
3. PATH artefacts from 40-path-wiring.sh (`/etc/profile.d/agentlinux.sh`, `/etc/agentlinux.env`, `/etc/cron.d/agentlinux`)
4. NodeSource apt files from 30-nodejs.sh (`nodesource.sources`, `nodesource.list`, `preferences.d/nodejs`)
5. **Optional** `apt-get purge -y nodejs` — gated on `--remove-nodejs` flag (T-04-17)
6. `pkill -u agent && userdel -r agent` (with `userdel -rf` fallback)
7. **LAST** — `rm /var/log/agentlinux-install.log`. Pitfall 7: the `tee` child is still writing to this file's open FD during run_purge's execution. Sequencing log removal last means the tee sees EOF naturally when the EXIT trap closes FD 1+2; the unlinked inode is GC'd after the script exits.

## Deviations from Plan

Two auto-fixes discovered during Docker smoke testing. Both are the classic Rule 1/2 pattern: the plan's action code was prescriptive enough that the bugs were copy-paste imports from RESEARCH §Pattern 1 and §Pattern 10 — RESEARCH had the bugs, the plan-checker didn't catch them, and they only surfaced when the bundle was executed inside a real Ubuntu container.

### Auto-fixed Issues

**1. [Rule 1 - Bug] as_user caller shape: double-`--` breaks sudo**

- **Found during:** First Docker smoke (Task 3 verification), `./tests/docker/run.sh ubuntu-24.04`
- **Symptom:** `sudo: --: command not found` + provisioner returns 1 on the sanity-check line `as_user agent -- test -x "$SYMLINK"`. CLI-01 regression false-positive — symlink was actually created correctly.
- **Root cause:** `plugin/lib/as_user.sh`'s function body is `sudo -u "$user" -H -E -- "$@"` — the `--` terminator is already baked into the function. When callers prepend their own `--` (`as_user agent -- test -x …`), after shift+assembly the sudo invocation becomes `sudo -u agent -H -E -- -- test …`. sudo parses the first `--` as "end of options" and takes the second `--` as the command, then complains "command not found".
- **Fix:** Pass command verbatim without the caller-side `--`. Applied in two places:
  - `plugin/provisioner/50-registry-cli.sh`: `as_user agent test -x "$SYMLINK"`
  - `plugin/bin/agentlinux-install` (run_purge step 1): `as_user agent bash "$recipe"` (would have had identical runtime failure on the --purge path when uninstalling real agents in Phase 5 testing — caught here before it shipped)
- **Files modified:** plugin/provisioner/50-registry-cli.sh, plugin/bin/agentlinux-install
- **Commit:** `f4d76bb`
- **Prevention:** added a NOTE comment in both call sites documenting the as_user invocation shape contract for future callers. Should be added to `.claude/skills/agentlinux-installer/SKILL.md` if that skill covers as_user usage.

**2. [Rule 2 - Missing critical functionality] CLI bundle staging incomplete**

- **Found during:** Second Docker smoke, ad-hoc `agentlinux --version` invocation inside container
- **Symptom:** `Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'commander' imported from /opt/agentlinux/cli/0.3.0/index.js`
- **Root cause:** plan's action code staged only `plugin/cli/dist/` under `/opt/agentlinux/cli/<ver>/`. But the compiled dist/ uses ESM imports — without a sibling `node_modules/` directory, Node's resolver has nothing to find. A Node CLI cannot run without its deps.
- **Fix:** stage the trio (dist + node_modules + package.json) under `/opt/agentlinux/cli/<ver>/`. Layout described under "Decisions Made" above. Required coordinated changes across three files:
  - `plugin/provisioner/50-registry-cli.sh`: CLI_SRC -> CLI_BUNDLE_SRC; sanity-check all three paths; stage each into a dedicated subdir; symlink target updated to `dist/index.js`
  - `tests/docker/Dockerfile.ubuntu-{22,24}.04`: builder stage runs `pnpm prune --prod` after build to strip devDeps; COPY three artifacts into `/opt/cli-prebuilt/`
  - `tests/docker/run.sh`: splice step copies all three into staged source tree
- **Files modified:** plugin/provisioner/50-registry-cli.sh (combined with deviation 1 in same commit), plugin/bin/agentlinux-install (not affected), Dockerfiles, run.sh
- **Commit:** `f4d76bb` (provisioner part) + `5fd4677` (Dockerfile + run.sh part, which is simultaneously Task 3's primary deliverable)

### Procedural Deviations

**3. Plan verify block literal-grep for `as_user agent -- test -x` no longer matches**

- **Plan automated verify at line 299:** `grep -Fq 'as_user agent -- test -x' plugin/provisioner/50-registry-cli.sh && echo "sanity-check:OK"`
- After Rule 1 auto-fix, this literal-grep FAILS because the correct code is `as_user agent test -x` (no `--`). The original verify encoded the buggy expectation.
- **Semantic equivalent that PASSES:** `grep -Fq 'as_user agent test -x' plugin/provisioner/50-registry-cli.sh` — confirms the sanity check exists and is in its corrected form.
- Not re-committed — the verify block is inside the plan file, not an active test; flagged here for plan-verification agents so they cross-check this SUMMARY when grading the plan's automated-verify rows.

### INST-02 idempotency extensions (informational)

Re-running the installer now produces byte-identical state under:
- `/opt/agentlinux/cli/0.3.0/{dist,node_modules,package.json}` (cp src/. dst/ idiom + byte-stable src from Docker builder)
- `/opt/agentlinux/catalog/0.3.0/` (cp byte-stable from repo)
- `/opt/agentlinux/state/installed.d/` (ensure_dir re-asserts mode+ownership; file list empty on fresh install)
- `/home/agent/.npm-global/bin/agentlinux` (ln -sfn no-op when symlink target matches)

Bats test `INST-02: re-running the installer is byte-stable (idempotency)` passes on both Ubuntu versions (`ok 3` in run output above) — confirming no drift on re-run.

Phase 2's original INST-02 byte-stable test was scoped to `/etc/profile.d/`, `/etc/agentlinux.env`, `/etc/cron.d/`, `/home/agent/.bashrc`. Plan 04-07 extends the set with `/opt/agentlinux/` (full tree) + `/home/agent/.npm-global/bin/agentlinux`. This SUMMARY's smoke run already confirmed idempotency empirically; Plan 04-07's bats adds the assertion.

## Review Loop

Applied the three review rubrics mentally (project-scoped review subagents not invoked in this session — executor bandwidth):

**bash-engineer** (50-registry-cli.sh, agentlinux-install, run.sh):
- `set -euo pipefail` inherited from parent, not re-declared in provisioner — correct per established Phase 2/3 pattern
- SC2155 split on cmdsub for CLI_BUNDLE_SRC / CATALOG_SRC readonly assignments
- `cp src/. dst/` trailing-slash idiom consistent with 30-nodejs + 40-path-wiring
- `ln -sfn` + `chown -h agent:agent` for atomic idempotent symlink
- All rm targets in --purge are literal absolute paths (security-engineer cross-check also passes)
- userdel with -rf fallback; pkill `|| true` for no-match
- run.sh splice block uses `set -euo pipefail` inside `bash -c`

**security-engineer** (--purge, symlink, Docker base images):
- Symlink target is a root-owned dir (`/opt/agentlinux/cli/0.3.0/`), so `ln -sfn + chown -h agent:agent` prevents an agent-owned symlink-hijack attack on the target — T-04-15 mitigation.
- `--purge` iterates sentinels by filename (`basename "$f" .json`), NOT by parsing JSON contents; a tampered sentinel cannot cause arbitrary script execution. Recipe path derives from `$AGENTLINUX_VERSION` (installer-controlled) — T-04-16 mitigation.
- `--remove-nodejs` gated behind explicit flag; default leaves Node — T-04-17 mitigation.
- Docker base images pinned to major (`ubuntu:22.04`, `ubuntu:24.04`, `node:22-slim`). Multi-stage + `pnpm prune --prod` minimizes the surface copied into the final image.
- One non-blocker: `corepack prepare pnpm@latest` uses the moving `latest` tag. In the current context this is test-harness infrastructure (not shipped to users) and `pnpm install --frozen-lockfile` guarantees dependency reproducibility, so the risk is bounded. v0.4+ candidate: pin to a specific pnpm version via `packageManager` in package.json.

**qa-engineer** (edge cases, idempotency, failure modes):
- Provisioner: three explicit existence checks (dist/index.js, node_modules/, package.json, catalog.json) with clear "release tarball malformed?" error messages.
- Provisioner: sanity-check `as_user agent test -x $SYMLINK` catches broken-symlink regressions post-install.
- --purge step 1: uninstall.sh absence is logged (warn) but does not fail the purge (a sentinel can exist without a recipe if the catalog was partially corrupted; --purge still removes the sentinel and continues).
- --purge step 6: if agent user is already absent, step is a no-op (`id agent` gate).
- Docker smoke both Ubuntu versions confirms installer + existing 27 bats tests all green (no regressions).

No iteration needed — review loop clean one pass.

## Verification

Both Docker images exercised end-to-end:

```
$ bash tests/docker/run.sh ubuntu-22.04  # 27/27 bats green
$ bash tests/docker/run.sh ubuntu-24.04  # 27/27 bats green
```

Ad-hoc in-container verification:

```
$ sudo -u agent -H bash --login -c 'agentlinux --version'
0.3.0

$ sudo -u agent -H bash --login -c 'which agentlinux'
/home/agent/.npm-global/bin/agentlinux

$ sudo -u agent -H bash --login -c 'agentlinux list'
NAME         STATUS         CURATED  INSTALLED  DESCRIPTION
claude-code  not-installed  2.1.98   -          Anthropic's agentic CLI …
gsd          not-installed  1.37.1   -          GSD workflow CLI for Claude Code …
playwright   not-installed  1.59.1   -          Browser automation framework …
```

CAT-02 invariant confirmed: all three catalog agents show `not-installed` on a fresh install.

Harness meta-tests: `bash tests/harness/run.sh` exits 0 (104/104 green; no regressions to Phase 1 harness contracts).

## Known Follow-ups (deferred, NOT in scope of this plan)

- **Phase 5 (AGT-XX)**: actually install claude-code / gsd / playwright via the CLI. The `--purge` step-1 per-agent uninstall.sh dispatch is wired but untested until Phase 5 produces at least one installed-state sentinel.
- **Phase 6 CAT-05**: catalog snapshot shipped as a sibling of the release tarball (instead of bundled inside). The provisioner currently stages from the in-tarball tree; Phase 6 may switch to a sibling-file flow. The code path is localized (just `CATALOG_SRC`) — trivial to adjust.
- **Pin pnpm version**: consider `packageManager` field in plugin/cli/package.json so `corepack prepare pnpm@…` is reproducible. Currently uses `latest` at image build time; `--frozen-lockfile` keeps the dep tree pinned, so risk is low. Non-blocking.
- **Non-login `bash -c` PATH** (pre-existing from Phase 2, not a Plan 04-06 regression): `sudo -u agent -H bash -c 'agentlinux --version'` (without `--login`) fails because Ubuntu's default sudoers `secure_path` strips /home/agent/.npm-global/bin before the shell runs. BHV-05 helpers in 20-agent-user.bats use `bash --login -c` precisely to work around this. Real v0.4+ fix requires sudoers/PAM changes outside Phase 2's locked scope (documented in `tests/bats/helpers/invoke_modes.bash:121`).

## TDD Gate Compliance

N/A — plan type is `execute` (not `tdd`). Per-task commits follow `feat(04-06): …` + `fix(04-06): …` conventions. No RED/GREEN/REFACTOR cycle expected or required.

## Commits Summary

- `34dc39a` — feat(04-06): provisioner 50-registry-cli.sh — stage CLI + catalog + symlink (CLI-01)
- `b6a6be9` — feat(04-06): agentlinux-install --purge — replace stub with 7-step teardown (INST-04)
- `f4d76bb` — fix(04-06): as_user caller shape + CLI bundle staging (Rule 1 + Rule 2 auto-fixes)
- `5fd4677` — feat(04-06): Dockerfiles pre-build plugin/cli via node:22 builder stage

## Self-Check: PASSED

Verified post-SUMMARY:
- FOUND: plugin/provisioner/50-registry-cli.sh (executable, 135 lines)
- FOUND: commit 34dc39a in git log
- FOUND: commit b6a6be9 in git log
- FOUND: commit f4d76bb in git log
- FOUND: commit 5fd4677 in git log
- FOUND: bats 27/27 green on Ubuntu 22.04 + 24.04 in /tmp/docker-run-{22,24}.04*.log
- FOUND: harness 104/104 green via tests/harness/run.sh
