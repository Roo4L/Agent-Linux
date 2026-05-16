# Phase 13: Reuse Wiring - Context

**Gathered:** 2026-05-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire Phase 12's `detect::` readers into the provisioners and catalog recipe runner so that compatible pre-existing state causes a clean short-circuit instead of a clobber. Concretely:

- `plugin/provisioner/10-agent-user.sh` skips its `useradd` step when `detect::user_present == true` AND a strict-but-fair compatibility check passes.
- `plugin/provisioner/30-nodejs.sh` skips both the NodeSource apt install and the per-user npm-prefix bootstrap when a v22 Node install with a writable global prefix already exists.
- `plugin/cli/src/commands/install.ts` (the TypeScript CLI `agentlinux install <name>`) shortcuts to a no-op + sentinel write when an installed catalog agent is detected at the path the recipe would have written to, healthy, and version-compatible.
- A `status: "reused"` sentinel record in `~agent/.agentlinux/state/<agent>.json` makes reused agents fully managed by `agentlinux list / upgrade / remove` going forward (per user-locked aggressive ownership policy).
- A brownfield smoke @test (pre-populated `agent` user + NodeSource Node 22 + manually-installed `claude-code` global) asserts `agentlinux install` runs with ZERO useradd / apt-install / `npm install -g claude-code` invocations.

Requirements in scope: REUSE-01, REUSE-02, REUSE-03.

Out of scope:
- Remediate path (Phase 14 — REMEDIATE-01..04 owns "compatible-with-defect" decisions, e.g. missing NOPASSWD-for-apt, wrong-owner npm prefix, drifted sudoers, broken catalog agent reinstall).
- `--yes` consent flag + exit codes 64/65/1 (Phase 14 — UX-03 + UX-05).
- `--dry-run` flag + interactive prompts (Phase 15).
- README brownfield section + docs/MIGRATION.md (Phase 16).

</domain>

<decisions>
## Implementation Decisions

### Area 1: REUSE Decision Policy

**REUSE-01 (existing `agent` user) — compatibility check (Q1, user-amended):**

Required predicates, ALL must hold:
1. `detect::user_present == true`
2. `detect::user_shell` is one of `/bin/bash`, `/usr/bin/bash` (exact path match — symlinks resolved via `readlink -f` before comparison)
3. `detect::user_home_writable == true`
4. **NEW (user constraint):** the user has passwordless sudo for at least `apt` and `apt-get` commands. Test via `sudo -u <user> -n /usr/bin/apt-get --help >/dev/null 2>&1` → exit 0. This is broader than "has `/etc/sudoers.d/agentlinux`" — any sudoers entry granting NOPASSWD for the apt binary path satisfies the check.
5. If `--user=NAME` was supplied AND `NAME != detect::user_name`, the test fails (user mismatch is its own incompatibility class).

If ALL pass: REUSE. If any fail: fall through to Phase 14 Remediate (specifically, REMEDIATE-03 for missing-sudoers, or other handlers for shell/home failures). Phase 13 does NOT contain Remediate logic — it falls through; Phase 14 will register on the same dispatch points.

**REUSE-02 (existing Node 22 install) — compatibility check (Q2, accepted as recommended):**

REUSE if at least ONE entry in `detect::nodejs[]` satisfies BOTH:
- `version` matches `/^v22\./` (semver major == 22; minor/patch free)
- `install_user_can_write_to_global_prefix == true` (this is the per-entry boolean from DET-02)

First match wins. The "active" Node on the install user's PATH is NOT enforced — REUSE-02 is about whether catalog recipes can `npm install -g <agent>` successfully, which is a per-Node-install property, not a PATH-resolution property. (Phase 14's REMEDIATE-01 handles wrong-owner-prefix cases for the active Node.)

**REUSE-03 (existing catalog agent install) — compatibility check (Q3, accepted as recommended):**

REUSE if ALL three hold:
1. `detect::agent_status <name> == "healthy"`
2. The detected `version` falls within the catalog's `compatibility_window` for that agent (read from `plugin/catalog/catalog.json` entry's `compatibility_window` field; semver range check)
3. The detected `binary` path equals what `install.sh` would have written to. For each agent this is the catalog-recipe-known canonical path:
   - `claude-code` → `~agent/.npm-global/bin/claude` (per existing install.sh:25)
   - `gsd` → `~agent/.npm-global/bin/get-shit-done-cc`
   - `playwright-cli` → `~agent/.npm-global/bin/playwright-cli`
   Brownfield reality: a user-installed `claude` may be at `/usr/local/bin/claude` or `~/.npm-global/bin/claude` under a NON-agent user. The path-match check distinguishes "AgentLinux can adopt this" from "AgentLinux can't safely manage this path."

If ALL pass: REUSE-with-management. If any fail but the agent is `healthy`: fall through to Phase 14 Remediate (uninstall + reinstall via the recipe).

**Log shape (Q4, accepted as recommended):**

Mirrors Phase 12's `[DET-NN] key=value` markers:
- `[REUSE-01] agent user reused: uid=1001 shell=/bin/bash home=/home/agent home_writable=true sudo_apt=true`
- `[REUSE-02] nodejs reused: version=v22.4.0 source=nodesource prefix=/usr/lib/node_modules prefix_writable=true`
- `[REUSE-03] claude-code reused: binary=/home/agent/.npm-global/bin/claude version=1.5.2 (in window 1.4.0-2.0.0) status=healthy`

Tests grep `[REUSE-NN]` reliably; humans read the same lines.

### Area 2: Sentinel Record + Brownfield Smoke

**Sentinel format (Q1, accepted as recommended):**

Reuses the existing Phase 4 sentinel shape with a `status` field:
```json
{
  "name": "claude-code",
  "status": "reused",
  "binary_path": "/home/agent/.npm-global/bin/claude",
  "version": "1.5.2",
  "detected_source": "manual-npm-global",
  "reused_at": "2026-05-16T12:34:56Z",
  "compatibility_window_at_reuse": "1.4.0-2.0.0"
}
```

Path: `~agent/.agentlinux/state/<agent>.json` (existing dir).

The Phase 4 CLI sentinel reader (`plugin/cli/src/state/sentinel.ts`) gets a new branch handling `status: "reused"`. All consumers (`list`, `upgrade`, `remove`) read this branch.

**Upgrade/remove behavior (Q2, user-amended — AGGRESSIVE ownership):**

The literal reading of REUSE-03 ("operate on the detected install identically to one AgentLinux placed itself") is binding:

- `agentlinux list` shows the entry with a `(reused — managed by agentlinux upgrade/remove)` suffix on the version column. UX disclosure: makes clear that future upgrade/remove WILL act on this binary.
- `agentlinux upgrade [<name>]` treats reused entries identically to installed entries — runs the recipe's `install.sh` against the pinned catalog version, which `npm install -g`s on top of the existing binary, overwriting it. The sentinel `status` flips from `reused` to `installed` after successful upgrade.
- `agentlinux remove <name>` runs the recipe's `uninstall.sh`, which deletes the binary AND removes the sentinel. AgentLinux takes responsibility for the binary it adopted.

Risk acknowledged: a user with a manually-customized claude install loses customizations on first `agentlinux upgrade`. Mitigation: the `(reused — managed)` suffix in `list` output makes the implicit contract explicit; users who don't want this can `agentlinux pin <name>=latest` or remove the sentinel manually.

**Brownfield smoke fixture (Q3, user-chosen — Setup-script in existing Dockerfile):**

No new Dockerfile. Reuse existing `tests/docker/Dockerfile.ubuntu-24.04` (and `-22.04`). Add a per-test setup helper `tests/bats/helpers/brownfield.bash::setup_brownfield_host` that, BEFORE the @test runs the installer:
- `useradd -m -s /bin/bash agent` (manual user creation, NOT via 10-agent-user.sh)
- Writes a minimal NOPASSWD-for-apt sudoers entry: `/etc/sudoers.d/local-agent-apt` with `agent ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt` (deliberately NOT the ADR-012 full-sudo entry — tests that REUSE-01's "at least apt" check passes)
- NodeSource Node 22 install (`curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt-get install -y nodejs`)
- Switches to agent user, runs `npm install -g @anthropic-ai/claude-code`

The @test then runs `agentlinux install` and asserts:
- ZERO matches for `useradd ` in the install log
- ZERO matches for `apt-get install -y --no-install-recommends nodejs` in the install log
- ZERO matches for `npm install -g @anthropic-ai/claude-code` in the install log
- AT LEAST one `[REUSE-01]`, `[REUSE-02]`, and `[REUSE-03]` marker each
- Sentinel file at `~agent/.agentlinux/state/claude-code.json` with `status: "reused"`
- AGT-02 (claude self-update) still passes against the live CDN

**Partial brownfield (Q4, accepted as recommended):**

Per-component decisions. No `--reuse-strict` / `--reuse-best-effort` mode flags. Each of REUSE-01, REUSE-02, REUSE-03 independently decides REUSE vs fall-through. The fall-through targets are:
- REUSE-01 fail → Phase 14 Remediate (sudoers install / shell-incompatible bail / etc.) OR Phase 15 alternate-user prompt
- REUSE-02 fail → Create (greenfield 30-nodejs.sh path) — there's no Remediate path for "no compatible Node", just "install one"
- REUSE-03 fail → Phase 14 Remediate (uninstall-broken-then-reinstall) if `detect::agent_status == "broken"`, else Create (run install.sh)

### Phase 13 → Phase 14 contract

Phase 14's Remediate logic will register on the same dispatch points Phase 13 uses for REUSE decisions. The dispatch shape:

```bash
# In 10-agent-user.sh, AFTER detect::run_once has been called:
case "$(reuse::user_decision "$INSTALL_USER")" in
  reuse) log_info "[REUSE-01] ..."; return 0 ;;   # Skip useradd
  create) ;;                                       # Fall through to existing CREATE path
  remediate|bail) return 1 ;;                      # Phase 14 will replace these
esac
# ... existing useradd code (CREATE path, unchanged) ...
```

The `reuse::user_decision` / `reuse::nodejs_decision` / `reuse::agent_decision` functions live in a new `plugin/lib/reuse.sh` (or `plugin/lib/reuse/<component>.sh` files). They read from `detect::` and return one of {reuse, create, remediate, bail} as a stdout token. Phase 14 will extend the case branches but not change the dispatch shape.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `plugin/lib/detect.sh` + `plugin/lib/detect/*.sh` — Phase 12 readers (`detect::user_present`, `detect::user_uid`, `detect::user_shell`, `detect::user_home_writable`, `detect::nodejs_satisfies_pin`, `detect::npm_prefix_writable_by_install_user`, `detect::agent_status <name>`). Phase 13 sources `detect.sh` and consumes these.
- `plugin/lib/log.sh` — `log_info`, `log_warn` (TTY-aware, used for `[REUSE-NN]` markers).
- `plugin/lib/as_user.sh` + `as_user_login` — for `sudo -u agent -n apt-get --help` test (NOPASSWD-for-apt detector).
- `plugin/lib/idempotency.sh` — Phase 13's mutations are minimal (sentinel write) and use `install -m` patterns for atomicity.
- `plugin/cli/src/state/sentinel.ts` — existing sentinel reader; Phase 13 adds one `status: "reused"` branch.
- `plugin/cli/src/commands/install.ts` — existing recipe runner; Phase 13 adds a pre-flight detection check that may short-circuit to sentinel-write-only.
- `plugin/cli/src/commands/list.ts` — existing list command; Phase 13 adds `(reused — managed)` suffix when `status === "reused"`.
- `plugin/cli/src/commands/upgrade.ts` + `plugin/cli/src/commands/remove.ts` — existing; verify they treat `status: "reused"` and `status: "installed"` identically (the literal REUSE-03 reading).
- `plugin/catalog/catalog.json` — existing. Phase 13 adds a `compatibility_window` field to each agent entry if not already present (semver range string, e.g., `"^1.0.0"` or `">=1.4.0 <2.0.0"`).
- `tests/bats/helpers/detection.bash` — Phase 12 helper file; Phase 13 adds `brownfield.bash` as a sibling.

### Established Patterns

- **Provisioner dispatch:** Each provisioner has a clear "early exit if state already matches" check (e.g., `30-nodejs.sh:50-56` for NodeSource apt repo). Phase 13 extends this pattern with the REUSE branch.
- **CLI sentinel reader:** `plugin/cli/src/state/sentinel.ts` exposes a typed reader. Phase 13 widens the type to include `status: "installed" | "reused"`.
- **Bats test convention:** `tests/bats/NN-<name>.bats` with @tests prefixed by REQ-ID. Phase 13 adds `tests/bats/13-reuse.bats` (slot 13 sits before slot 15-detection.bats numerically, but the file dependencies are inverted: reuse depends on detection — slot number is a sort key, not a dependency order).

### Integration Points

- **Provisioner entry points:** `10-agent-user.sh`, `30-nodejs.sh` gain `reuse::` calls near their top.
- **Sudoers entry point:** `20-sudoers.sh` does NOT change in Phase 13 — REUSE-01 only checks for NOPASSWD-for-apt; if missing, Phase 14 handles it. If `/etc/sudoers.d/agentlinux` is missing but REUSE-01 passes via a non-ADR-012 sudoers entry, Phase 14 may add the canonical drop-in via REMEDIATE-03; Phase 13 leaves the user's existing sudoers alone.
- **CLI install handler:** `plugin/cli/src/commands/install.ts` gains a pre-runner detection check.
- **CLI sentinel reader:** widened with `status: "reused"` discriminator.

</code_context>

<specifics>
## Specific Ideas

- **catalog.json `compatibility_window` field:** Phase 13 may need to add this if it's not already there. Format: a semver range string. For each existing agent, the recommended initial window is `>=<pinned_version_minor> <<pinned_version_major+1>.0.0` (e.g., if pinned is `1.5.2`, window is `>=1.5.0 <2.0.0`). This lets future minor/patch upgrades stay in the window; majors require an explicit catalog churn.
- **NOPASSWD-for-apt detector:** A 1-line bash test, `sudo -u "$user" -n /usr/bin/apt-get --help >/dev/null 2>&1; echo $?`. Exit 0 means user has NOPASSWD for at least apt-get. Caveat: the test FORKS apt-get; on a slow disk this adds ~50ms per invocation. Cache the result in detect:: namespace if performance matters.
- **List-output disclosure wording:** the `(reused — managed by agentlinux upgrade/remove)` suffix MUST be visible without `--verbose`. Users glance at `agentlinux list` and form mental models from what they see.
- **Brownfield helper:** `tests/bats/helpers/brownfield.bash::setup_brownfield_host` runs INSIDE the Docker container during the @test setup phase. It needs to be careful: if 10-agent-user.sh has already run (in a prior @test), the user already exists. The helper should detect this and skip its own useradd, or unconditionally start from a fresh container.

</specifics>

<deferred>
## Deferred Ideas

- **Per-component `--reuse-strict` / `--reuse-best-effort` mode flags.** Not added in v0.3.4 per Q4 — per-component decisions are sufficient.
- **Detecting non-catalog tools (`npx`, `tsx`, `vercel`, `pnpm`).** Out of scope per REQUIREMENTS.md "Future Requirements" — AgentLinux only owns its catalog.
- **`(reused)` warning before upgrade.** Considered: interactive prompt "About to overwrite a user-installed binary — continue?" — rejected because the `list` suffix already discloses the contract. If real users hit confusion, surface a one-line `--yes`-gated prompt in a follow-up milestone.
- **Brownfield smoke also on Ubuntu 22.04.** Initially planned both, deferred to 24.04 only for Phase 13 to save CI minutes. 22.04 is covered by the existing v0.3.0 matrix (greenfield); 24.04 brownfield smoke is the new coverage. Phase 16's AGT-02 milestone-close gate will exercise both.
- **Sentinel migration on `status: "reused" → "installed"` after upgrade.** Belongs to Phase 13's upgrade integration (must happen) but recording here for clarity: post-upgrade, the sentinel's `status` flips, `detected_source` is cleared, and `installed_at` is set.

</deferred>
