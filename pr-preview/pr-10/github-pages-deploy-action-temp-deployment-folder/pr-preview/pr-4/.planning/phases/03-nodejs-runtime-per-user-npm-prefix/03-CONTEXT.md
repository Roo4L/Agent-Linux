# Phase 3: Node.js Runtime + Per-User npm Prefix - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning

<domain>
## Phase Boundary

After Phase 3 the agent user has a working Node.js LTS runtime and a writable `npm install -g` path under its own home — proving the keystone ownership decision (ADR-004 + ADR-005) before any actual agent (Claude Code, GSD, Playwright) is installed on top in Phase 5. `npm install -g <throwaway>` works without sudo, without `EACCES`, and without shim/wrapper workarounds, across all six BHV invocation modes.

Requirements in scope: RT-01 (Node.js LTS available), RT-02 (`npm install -g` works unprivileged across invocation modes), RT-03 (`npm uninstall -g` cleanly removes), RT-04 (`npm config get prefix` returns a path under agent home).

Out of scope for Phase 3: Registry CLI (Phase 4), catalog entries (Phase 4), real agents (Phase 5), release distribution (Phase 6).

</domain>

<decisions>
## Implementation Decisions

### Node.js Install Path
- Install source: **NodeSource apt repo** (Node 22 LTS "Jod"), added via `curl -fsSL https://deb.nodesource.com/setup_22.x | bash`. Authoritative upstream distro of Node on Ubuntu; pinned major version.
- New provisioner: **`plugin/provisioner/30-nodejs.sh`** — runs AFTER `10-agent-user.sh` (user must exist) and AFTER `40-path-wiring.sh` (PATH/npmrc semantics already wired). Ordering: 10 → 30 → 40 remains numerically monotonic.
- Idempotency: `command -v node` + version compare; if `node --version | cut -dv -f2 | cut -d. -f1` ≥ 22 → skip install (log_info "Node ≥22 already installed"). If < 22 or missing → add NodeSource repo (idempotent — skip repo add if `/etc/apt/sources.list.d/nodesource.list` exists) and `apt-get install -y nodejs`.
- Major version: **Node 22 LTS** per ADR-005. No floating "latest LTS" — major bumps are a release-gate decision, not an install-time auto-upgrade.
- Pre-existing Node behavior: if user has Node installed (any version), log_warn the version and respect it if ≥22. Never destructively downgrade or remove. Full purge only via the `--purge` flag (wired in Phase 4/6 for INST-04).

### Per-User npm Prefix Layout
- Prefix location: **`/home/agent/.npm-global`** — matches v0.2.0 precedent; human-obvious; under agent home so agent fully owns it.
- Configuration mechanism: write `~agent/.npmrc` with literal line `prefix=/home/agent/.npm-global` via `as_user` + `ensure_line_in_file` (idempotent, no duplicate lines on re-run). Directory created with `ensure_dir /home/agent/.npm-global 0755 agent:agent`.
- PATH wiring: **already complete from Phase 2** — `/etc/profile.d/agentlinux.sh`, `/etc/agentlinux.env`, `/etc/cron.d/agentlinux`, and `~agent/.bashrc` marker block all include `/home/agent/.npm-global/bin`. Phase 3 does NOT re-touch those files; it only ensures the target directory exists and the npm config points there.
- npm cache: default location (`/home/agent/.npm`) — agent-owned, no additional config required. Cache collision with other users is impossible because it lives under agent home.

### Phase 3 Test Coverage & Smoke Package
- Smoke package for RT-02: **`cowsay`** — zero runtime deps, ~6 KB tarball, ships a single `cowsay` binary on PATH. Well-known enough that a human reading a test sees it as a throwaway. Explicitly NOT a catalog agent (respects CAT-02 "no agents installed by default"). If cowsay registry availability becomes flaky, fallback to `is-ci` (but cowsay is the canonical choice).
- Invocation-mode coverage: **new `tests/bats/30-runtime.bats`** reuses the six helpers from `tests/bats/helpers/invoke_modes.bash` (already shipped in Phase 2 Plan 02-05). Tests loop all six modes asserting `command -v cowsay && cowsay hi` succeeds in each, after an `as_user -- npm install -g cowsay`.
- RT-04 assertion: **new helper `assert_user_prefix_in_home`** in `tests/bats/helpers/assertions.bash` (append to existing file from Phase 2). Asserts `npm config get prefix` returns a path under `/home/agent/` — never `/usr`, `/usr/local`, or any root-owned path. Includes diagnostic-on-fail (`# RT-04: expected /home/agent/.npm-global, observed $observed`).
- RT-03 uninstall cleanliness: after `as_user -- npm uninstall -g cowsay`, assert across all six invocation modes that `command -v cowsay` returns non-zero AND `/home/agent/.npm-global/bin/cowsay` does not exist AND `/home/agent/.npm-global/lib/node_modules/cowsay` does not exist. No leftover bytes.

### Claude's Discretion
- Exact split of `plugin/provisioner/30-nodejs.sh` — single file or a tiny `plugin/lib/nodejs_install.sh` helper, whichever keeps the provisioner under ~100 LOC.
- Implementation detail of `assert_user_prefix_in_home` — any shape that returns non-zero with a diagnostic when `npm config get prefix` is outside `/home/agent/`.
- Whether `cowsay` version is pinned in the smoke test (`npm install -g cowsay@1.5.0`) or floating — Claude picks based on registry pinning precedent; pinning is safer against upstream churn, floating is simpler.
- Whether 30-nodejs.sh caches the NodeSource PGP key to a temp file or pipes through `gpg --dearmor` inline — either is acceptable; research will recommend the upstream pattern.
- Plan count and wave structure — Phase 2 used 5 plans × 3 waves; Phase 3 is smaller scope (4 requirements), probably 2 plans × 2 waves (provisioner + tests). Planner decides.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (shipped in Phase 2)
- `plugin/lib/log.sh` — log_info / log_warn / log_error / log_debug (timestamped, tee'd to installer log).
- `plugin/lib/idempotency.sh` — ensure_line_in_file, ensure_marker_block, ensure_user, ensure_dir, visudo_validate (unused here), plus arg-count guards on every primitive.
- `plugin/lib/as_user.sh` — the keystone `as_user` + `as_user_login` helpers. Every npm invocation in this phase goes through `as_user` — never raw `sudo -u`. (Enforced by Phase 2 review loop; Phase 3 continues the pattern.)
- `plugin/lib/distro_detect.sh` — detect_distro returns `ubuntu-22.04` or `ubuntu-24.04`. Phase 3 uses it to gate NodeSource repo add (NodeSource supports both; Phase 3's idempotent gate is "skip if already present").
- `plugin/bin/agentlinux-install` — sources lib in dependency order, dispatches `plugin/provisioner/[0-9][0-9]-*.sh` in numeric order. Phase 3's `30-nodejs.sh` lands in that dispatch path automatically.
- `plugin/provisioner/10-agent-user.sh` — agent user + UTF-8 locale + DOC-02 CLAUDE.md with marker tag `agentlinux-doc-02`.
- `plugin/provisioner/40-path-wiring.sh` — four-file PATH with `/home/agent/.npm-global/bin` already included. Phase 3 reuses this; it does not modify these files.
- `tests/bats/helpers/invoke_modes.bash` — six-mode helpers (`run_interactive`, `run_ssh`, `run_cron`, `run_systemd_user`, `run_sudo_u`, `run_sudo_u_i`). Phase 3 `30-runtime.bats` loops all six for RT-02.
- `tests/bats/helpers/assertions.bash` — `assert_no_eacces`, `assert_path_has`, `assert_exit_zero` with diagnostic-on-fail. Phase 3 adds `assert_user_prefix_in_home` here.
- `tests/docker/Dockerfile.ubuntu-{22,24}.04` + `run.sh` — already installs the Phase 2 env and runs bats. Phase 3 adds `30-runtime.bats` to the bats run; no Dockerfile change required unless NodeSource apt key fetch needs `curl`/`gnupg` (likely already present; verify in research).
- `.github/workflows/test.yml` — Docker matrix wired in Phase 2 Plan 02-05. Phase 3 additions flow through automatically.

### Established Patterns
- Per-task atomic commits via `git add <files> && git commit --no-gpg-sign -m "feat(03-NN): ..."` — continuing Phase 1/2 precedent.
- Every bats `@test` references its requirement ID (`# RT-02: ...` or in the assertion message).
- Review loop before task complete: `bash-engineer` + `security-engineer` + `qa-engineer` on any new bash; `qa-engineer` + `behavior-coverage-auditor` on any new bats; `behavior-coverage-auditor` at phase close per TST-07.
- Threat model block on every plan (T-03-NN).
- Idempotent primitives for every state mutation — no raw `echo >>`, no raw `sed -i`, no bare `apt-get install` without a pre-check.
- `as_user -- cmd args` signature — never `sudo -u agent cmd` directly.

### Integration Points
- `30-nodejs.sh` is dispatched by `plugin/bin/agentlinux-install`'s `run_provisioners` loop automatically (numeric order); no entrypoint change needed.
- `.npmrc` for agent user is placed at `/home/agent/.npmrc`, owned by agent, mode 0644. `npm config get prefix` picks it up across all invocation modes since it lives in agent home and is read by npm regardless of shell invocation.
- `30-runtime.bats` lives alongside `10-installer.bats` and `20-agent-user.bats`; the Docker harness's `bats tests/bats/` invocation picks it up automatically.

</code_context>

<specifics>
## Specific Ideas

- NodeSource setup script is canonical but does several things: adds apt repo, imports PGP key, runs `apt-get update`. Our provisioner runs it exactly once (guarded by `/etc/apt/sources.list.d/nodesource.list` existence) so re-runs don't re-import keys or re-add repos.
- `npm config get prefix` respects `.npmrc` even when invoked from non-interactive shells. That's why we write `~agent/.npmrc` rather than setting `NPM_CONFIG_PREFIX` in the env — the file-based approach is self-contained and visible via standard npm tools.
- RT-02 check must loop all six invocation modes. This is identical in structure to Phase 2's BHV-02..06 tests; the planner can copy the loop pattern from `tests/bats/20-agent-user.bats`.
- RT-03 cleanliness check is stronger than "binary gone from PATH" — it asserts the filesystem is byte-clean (no orphaned `/home/agent/.npm-global/lib/node_modules/cowsay` directory). Catches the class of bugs where npm leaves a directory behind.
- Node 22 LTS "Jod" is the current v22 LTS line (as of April 2026); check NodeSource for the current active setup_22.x availability in research. If the distro repo name changes between NodeSource versions, the provisioner idempotency gate is the `/etc/apt/sources.list.d/nodesource.list` file existence — file name is stable across NodeSource revisions.
- The `cowsay` package installed under the agent's own prefix MUST produce a binary at `/home/agent/.npm-global/bin/cowsay`. If it produces `/usr/local/bin/cowsay` instead, the entire keystone ownership decision has failed — the test fails loudly rather than passing with a note.

</specifics>

<deferred>
## Deferred Ideas

- `agentlinux doctor` command to check Node version, npm prefix health, PATH correctness, etc. (CLI-08 v0.4+).
- Floating "latest LTS" Node.js major version — Phase 3 pins to 22 LTS; bumping to 24 LTS is a v0.4+ decision.
- Multi-Node-version support (e.g., Node 20 + 22 coexisting for compatibility testing) — not needed for v0.3.0; one LTS suffices.
- Node.js installed from a binary tarball for air-gapped environments — v0.4+.
- Alternative package managers (pnpm, yarn) globally installed for the agent — none of the v0.3.0 catalog agents require them; v0.4+ decision.
- Pinning the Node PATCH version (e.g., 22.11.0 rather than latest 22.x) — out of scope; NodeSource pins major + tracks minor/patch.

</deferred>
