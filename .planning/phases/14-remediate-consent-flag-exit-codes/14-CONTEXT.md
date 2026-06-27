# Phase 14: Remediate + Consent Flag + Exit Codes - Context

**Gathered:** 2026-05-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the `remediate|bail) return 1 ;;` dispatch stubs left by Phase 13 with real handlers. Add a single `--yes` consent flag (Unix convention, matching `apt install -y`) that gates state-overwriting Remediate actions in non-TTY contexts. Introduce structured exit codes (64 EX_USAGE / 65 EX_DATAERR / 1 runtime) honored by every subsequent phase.

Concrete deliverables:
- `plugin/lib/remediate.sh` orchestrator + `plugin/lib/remediate/{user,nodejs,sudoers,agents}.sh` per-component handlers.
- `plugin/bin/agentlinux-install` `--yes` flag parsing + non-TTY policy gate that, without `--yes`, converts any required state-overwriting Remediate decision into a `bail` token.
- Structured `[BAIL] component=<name> reason=<token> hint=<short>` lines + a "Refusing to proceed" header + exit-code wiring.
- Per-agent `preserve_paths.json` files for REMEDIATE-04 user-data preservation (CAT-04).
- `--help` "Exit codes" section + a footer in the bail message pointing at `--help`.

Requirements in scope: REMEDIATE-01, REMEDIATE-02, REMEDIATE-03, REMEDIATE-04, UX-03, UX-05.

Out of scope:
- TTY-interactive per-action prompts (Phase 15 — UX-02 owns `Proceed? [Y/n]` for each Remediate action when stdin is a TTY).
- `--dry-run` flag end-to-end (Phase 15 — UX-01).
- Alternate-user-name prompt when `agent` user is incompatible (Phase 15 — UX-04).
- README brownfield section + docs/MIGRATION.md (Phase 16).

</domain>

<decisions>
## Implementation Decisions

### Area 1: `--yes` flag scope + exit code semantics (accepted as recommended)

**Q1 `--yes` scope (state-overwriting Remediates only):**

`--yes` gates ONLY state-overwriting Remediate actions:
- REMEDIATE-01 chown OR rebase (overwrites npm-prefix ownership/location)
- REMEDIATE-03 sudoers drift overwrite (replaces a non-canonical sudoers file)
- REMEDIATE-04 broken-agent reinstall (deletes binary + replaces)

Additive Remediates run UNCONDITIONALLY (no `--yes` needed):
- REMEDIATE-02 PATH wiring (ensure_marker_block — additive, never touches user content outside the marker)
- REMEDIATE-03 missing-file install (writes new file in a known-controlled directory; doesn't overwrite anything)

This split matches REQUIREMENTS REMEDIATE-02 wording ("no interactive consent required for PATH wiring (additive, idempotent, never overwrites user content)") and REMEDIATE-03 wording ("a missing file installs without prompt (additive, not overwriting user state)").

No per-component flags (no `--yes-prefix`, no `--yes-sudoers`). One flag opts into the whole set.

**Q2 Bail message format (structured markers):**

When non-TTY mode without `--yes` encounters a required state-overwriting Remediate:

```
Refusing to proceed — N components need Remediate (run with --yes to apply, or --dry-run to preview):

[BAIL] component=npm-prefix reason=wrong-owner hint=run with --yes to chown or rebase
[BAIL] component=sudoers reason=drift hint=run with --yes to overwrite with the canonical ADR-012 line
[BAIL] component=playwright-cli reason=broken hint=run with --yes to reinstall

Exit code 65 (EX_DATAERR — incompatible host state). See agentlinux install --help.
```

The `[BAIL]` markers are stable per-component lines that CI wrappers can grep. The header and footer are for humans.

**Q3 Exit code mapping (per REQUIREMENTS UX-05):**

| Code | Mnemonic | Triggers |
|------|----------|----------|
| 64 | EX_USAGE | bad CLI flags: unknown flag, contradictory options (`--yes --no-yes`), `--report-format=xyz`, `--user=` with invalid chars |
| 65 | EX_DATAERR | host state surfaced by detection that the installer cannot proceed against: non-TTY bail without --yes (any [BAIL]), incompatible existing user (wrong shell, conflicting UID, --user mismatch) |
| 1 | runtime | execution failure during Create or Remediate: apt fails, chown fails, useradd fails, install.sh exits non-zero, recipe install fails — anything that happens AFTER policy gate passes |
| 0 | success | install completed (Create or Reuse or Remediate-with-yes); --dry-run printed report; --report-only printed report |

The codes are checked into `plugin/bin/agentlinux-install` as bash readonly constants near the top: `readonly EX_USAGE=64 EX_DATAERR=65`. Used throughout via `exit "$EX_DATAERR"` for grep stability.

**Q4 `--help` doc surface:**

`agentlinux install --help` gains an "Exit codes" section near the bottom (after Options, before Examples):

```
Exit codes:
  0   success — install completed, report printed, or dry-run finished
  1   runtime — execution failure during Create or Remediate (apt, chown, useradd, install.sh)
  64  usage   — bad command-line flags or contradictory options
  65  data    — incompatible host state surfaced by detection (run --dry-run to preview)

  Most actionable in non-TTY contexts (cron, CI, curl|bash): exit 65 means
  state-overwriting Remediate would be required — re-run with --yes to apply.
```

The bail message footer ("See `agentlinux install --help`") points back at this section. No separate `agentlinux exitcodes` subcommand.

### Area 2: REMEDIATE-01 npm-prefix strategy (accepted as recommended)

**Q1 Strategy selection algorithm:**

```
function reuse::nodejs_decision OR remediate::nodejs_decision detects wrong-owner prefix
  IF (effective_prefix is under detect::user_home) AND (prefix dir is empty-or-trivially-salvageable per Q2)
    THEN strategy="chown"  → chown -R agent:agent <prefix>
    LOG "[REMEDIATE-01] strategy=chown path=<prefix>"
  ELSE
    strategy="rebase"      → create ~user/.npm-global, migrate modules, update ~user/.npmrc
    LOG "[REMEDIATE-01] strategy=rebase from=<old> to=~user/.npm-global"
```

Rebase is the safer default. Chown is the optimization when it's clearly safe (under home + empty).

**Q2 "Trivially salvageable" definition:**

The prefix dir is trivially salvageable IF it contains ONLY these entries:
- `lib/` (empty OR contains only `node_modules/` which is empty)
- `bin/` (empty)
- `share/` (empty)
- `etc/` (empty)
- `package.json`, `package-lock.json` (npm-managed metadata)

Anything else (a user-installed module dir under `lib/node_modules/`, a custom binary in `bin/`) means the prefix is NOT trivially salvageable → fall back to rebase strategy.

Implementation: `find <prefix> -maxdepth 3 -mindepth 1 -not -path '<prefix>/lib' -not -path '<prefix>/bin' ...` etc. — exit 0 if only allowlisted paths present.

**Q3 Module migration on rebase:**

Enumerate global modules via `as_user <old-owner> npm ls -g --json --depth=0` (parsed by bash with `jq`):
```bash
modules_manifest=$(jq -r '.dependencies | to_entries[] | "\(.key)@\(.value.version)"' <<<"$npm_ls_output")
```

Then for each `pkg@ver`: `as_user agent -H -- npm install -g "$pkg@$ver"` (best-effort per module). Failures logged with `[REMEDIATE-01:partial] module=<name> reason=<...>`; count surfaced in install summary.

Special-cases:
- The catalog agents (claude-code, gsd, playwright-cli) — DO NOT migrate via this path. The catalog's own install machinery handles them. Filter them out of the manifest before migration.
- npm itself — never migrated; comes from the system Node install.

**Q4 Atomicity (best-effort, NOT atomic):**

Migration is best-effort. Old prefix is NEVER deleted by Remediate (user can clean manually after verifying). Per-module migration failures don't abort the whole Remediate — they're logged and counted. New `~user/.npm-global` is the canonical location post-Remediate.

If THE REBASE ITSELF fails (mkdir denied, chown denied, ~user/.npmrc write denied): exit 1 (runtime) with `[REMEDIATE-01:fail] reason=<...>`. Leaves the old prefix untouched; user can retry.

### Area 3: REMEDIATE-04 broken-agent reinstall semantics (accepted as recommended)

**Q1 User data preservation paths (CAT-04):**

Per-agent allowlist read from `plugin/catalog/agents/<name>/preserve_paths.json` (NEW file). Schema:

```json
{
  "preserve_paths": [
    "~/.claude/",
    "~/.config/claude/"
  ],
  "comment": "User credentials + session state — must survive uninstall + reinstall."
}
```

Initial values (Phase 14 ships these):
- `claude-code`: `~/.claude/`, `~/.config/claude/`
- `gsd`: `~/.gsd/`, `~/.config/get-shit-done/`
- `playwright-cli`: `~/.cache/ms-playwright/` (browser binaries — expensive to re-download)

Catalog schema (`plugin/catalog/schema.json`) gains `preserve_paths_file` optional field per agent; loader reads the JSON, falls back to empty preserve-set when absent.

**Q2 Uninstall → install order:**

Sequential: `uninstall.sh` runs first (via `as_user agent ...`); on success, `install.sh` runs. Preserve_paths are filtered out of uninstall.sh's `rm -rf` list at the catalog-loader level — the loader sets `AGENTLINUX_PRESERVE_PATHS=":separated:list"` env var that uninstall.sh consumes via a `_should_remove()` helper. If uninstall.sh fails: bail with `[REMEDIATE-04:uninstall-fail]`, exit 1; do NOT proceed to install (don't double-mutate).

**Q3 Sentinel handling during reinstall:**

The existing sentinel (whatever `status` it had: `reused`, `installed`, or `broken-after-remediate`) is read BEFORE uninstall, then left in place during uninstall.sh execution (uninstall.sh doesn't delete the sentinel — that's the loader's responsibility post-uninstall). On successful install.sh, the sentinel is rewritten with:
- `status: "installed"` (NOT `reused` — even if the original sentinel was `reused`, Remediate means AgentLinux now owns this install)
- `version: <freshly-detected>`
- `installed_at: <now>`
- Previous `detected_source`, `reused_at`, `compatibility_window_at_reuse` fields dropped

**Q4 Failure handling (uninstall succeeded but install failed):**

Surface as `[REMEDIATE-04:half-uninstalled] agent=<name>` with exit 1. The sentinel is updated to `status: "broken-after-remediate"` (a NEW status value Phase 14 introduces). Subsequent `agentlinux list` shows this state with a `(broken — half-uninstalled, manual recovery needed)` suffix. User intervenes manually (run `agentlinux remove <name>` to clean up, then `agentlinux install <name>` fresh).

The `status: "broken-after-remediate"` is added to the sentinel union type in `plugin/cli/src/state/sentinel.ts` and to the list renderer.

### Phase 14 → Phase 15 contract

Phase 15 will add TTY-interactive per-action prompts on top of Phase 14's `--yes` gate. The gating logic:

```bash
# In remediate dispatch, per-action:
if remediate_action_overwrites_state "$action"; then
  if [[ -t 0 ]]; then
    # Phase 15: interactive prompt here
    if ! confirm_remediate "$action"; then
      log_warn "[REMEDIATE-NN:declined] skipping $action — continuing with remaining components"
      return 0  # not a hard fail in interactive mode — declining a single action is fine
    fi
  elif ! "$YES_FLAG"; then
    # Phase 14 owns this branch:
    bail "[BAIL] component=$component reason=$reason hint=run with --yes"
  fi
fi
# Dispatch to remediate handler
```

Phase 14 ships the non-TTY branch (`bail` without `--yes`); Phase 15 fills in the TTY-interactive branch. The state-overwriting predicate `remediate_action_overwrites_state` is centralized in `plugin/lib/remediate.sh` so Phase 15 doesn't duplicate the policy.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `plugin/lib/detect.sh` + `plugin/lib/detect/*.sh` (Phase 12 readers — Phase 14 calls them to compose remediate decisions)
- `plugin/lib/reuse.sh` + `plugin/lib/reuse/{user,nodejs,agents}.sh` (Phase 13 decision functions — Phase 14 adds REMEDIATE branches in the SAME decision functions, returning `remediate` instead of `bail` for fixable defects)
- `plugin/lib/idempotency.sh` (ensure_marker_block, ensure_line_in_file — Phase 14 uses these for the additive Remediate paths)
- `plugin/lib/as_user.sh` (as_user, as_user_login — Phase 14 uses heavily for chown/npm operations)
- `plugin/lib/log.sh` (log_info, log_warn, log_error — `[REMEDIATE-NN]` and `[BAIL]` markers via log_warn/log_error)
- `plugin/provisioner/{10-agent-user,20-sudoers,30-nodejs,40-path-wiring}.sh` (provisioners; Phase 14 replaces the `remediate|bail) return 1 ;;` case branches with actual handlers)
- `plugin/catalog/agents/<name>/{install,uninstall}.sh` (recipe runners — REMEDIATE-04 invokes them; preserve_paths filtering wraps the `rm -rf` calls)
- `plugin/cli/src/state/sentinel.ts` (sentinel reader — Phase 14 adds `"broken-after-remediate"` to the status union)
- `plugin/cli/src/commands/install.ts` (Phase 14 adds REMEDIATE branch alongside REUSE branch)
- `plugin/cli/src/catalog/loader.ts` (Phase 14 adds preserve_paths.json loading + AGENTLINUX_PRESERVE_PATHS env var injection)

### Established Patterns

- **Decision-function dispatch:** Phase 13 established `reuse::user_decision` etc. returning {reuse, create, remediate, bail}. Phase 14 keeps the same return tokens; only the dispatcher's handling of `remediate` changes (was `return 1`, becomes "call remediate::<component>::<action>").
- **`[REUSE-NN] key=value`** markers in Phase 13. Phase 14 uses `[REMEDIATE-NN] key=value` (same shape, different prefix).
- **`as_user agent ...`** for any operation on agent-owned state.
- **Strict mode + ERR trap** inheritance from entrypoint — Phase 14 lib files use `return N` not `exit N`.
- **CAT-04 user data preservation** — established in Phase 4 (catalog uninstall.sh contract). Phase 14 makes it data-driven via preserve_paths.json instead of hard-coded.

### Integration Points

- **Entrypoint argv parsing:** `plugin/bin/agentlinux-install` adds `--yes` parsing (mirrors `--user=NAME` shape added in Phase 12).
- **Policy gate location:** new function `remediate::gate_or_bail` in `plugin/lib/remediate.sh`; called from each provisioner's case-branch before dispatching to a remediate handler. Returns 0 if proceed, 65 if bail.
- **Bail aggregation:** `remediate::gate_or_bail` doesn't bail immediately — it accumulates all required Remediates into a `BAILED_COMPONENTS` array, then the entrypoint's wrap-up phase prints the full bail message and exits 65 if the array is non-empty. (Otherwise users get a partial install that fails halfway through.)
- **CLI install command:** the TS `install <name>` already gained REUSE branch in Phase 13; Phase 14 adds REMEDIATE branch for `broken` catalog agents.

</code_context>

<specifics>
## Specific Ideas

- **`--yes` is a `--no-yes` opposite:** support `--no-yes` for explicitness even though it's the default. This lets CI scripts that wrap `agentlinux install` toggle the flag from a variable without rebuilding the argv. Document briefly in `--help`.
- **`[BAIL]` aggregation must happen even if more than one component bails.** A user with wrong-owner npm prefix AND drifted sudoers should see BOTH `[BAIL]` lines, not just the first. This is critical for `--dry-run` parity (Phase 15) — the dry-run report is the same shape as the bail.
- **`broken-after-remediate` sentinel status:** new value in the union. Update `plugin/cli/src/types.ts` Sentinel type. The list renderer should show this in red (TTY-aware).
- **preserve_paths.json schema validation:** add to `plugin/cli/scripts/validate-catalog.mjs`. The file is optional but if present must conform to the schema.
- **Greenfield invariant:** On a fresh host, no Remediate paths fire. The full v0.3.0 bats matrix must still be 66/66 green. Plan must include a verification step running the greenfield matrix and asserting Phase 14's changes don't regress it.

</specifics>

<deferred>
## Deferred Ideas

- **TTY-interactive per-action prompts** — Phase 15 (UX-02).
- **`--dry-run` flag** — Phase 15 (UX-01). Phase 14 only ships `--yes`.
- **Alternate-user-name prompt** when `agent` user has wrong shell — Phase 15 (UX-04). Phase 14 just bails with exit 65 + `[BAIL] component=user reason=incompatible-shell hint=use --user=NAME`.
- **`--rollback` flag** for the `broken-after-remediate` recovery — out of scope for v0.3.4. Users intervene manually.
- **Auto-atomic module migration** during REMEDIATE-01 rebase — out of scope per Q4. Best-effort with per-module logging is sufficient.
- **Per-component `--yes-<component>` flags** — explicitly rejected per Q1; would multiply the surface unnecessarily.
- **A separate `agentlinux remediate` subcommand** to fix host state without installing — considered, deferred. v0.3.4 keeps remediate scoped to the `agentlinux install` flow.

</deferred>
