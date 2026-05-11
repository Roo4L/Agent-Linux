# Roadmap: AgentLinux v0.3.4 — Aware Installation Process

**Milestone:** v0.3.4 Aware Installation Process
**Started:** 2026-05-09
**Triggered by:** [AL-38 "Introduce proper migration pass for users with some AI setup already"](https://copiedwonder.atlassian.net/browse/AL-38)
**Phase numbering:** Continues from v0.4.0 (last phase 11 → next phase 12). Existing phase directories under `.planning/phases/01-*..11-*` are preserved (v0.3.0 + v0.4.0 work; v0.4.0 formal closeout pending). v0.3.4 phases land in `.planning/phases/12-*..16-*` alongside them. Conflict-free.
**Granularity:** coarse (5 phases for 20 requirements; matches per-category natural seam)

## Overview

v0.3.4 takes AgentLinux's installer from "fresh-host only" to brownfield-aware. The product surface does not grow — no new agents, no new distros, no new commands. What changes is how `agentlinux install` decides what to do when the host already has an `agent` user, Node.js, npm-global with surprising ownership, a sudoers drop-in with drifted content, or one or more catalog agents already installed.

The critical path is **detection before mutation, never after**. Phase 12 builds the read-only discovery layer that classifies every component AgentLinux owns into Reuse / Create / Remediate / Bail. Phase 13 wires the Reuse short-circuit into the existing v0.3.0 provisioners and recipe dispatcher (the cheapest, safest brownfield branch — "we already have it, do nothing"). Phase 14 lands the mutating Remediate paths plus the single `--yes` consent flag and structured exit codes that gate them in non-TTY mode. Phase 15 polishes the user-facing UX — `--dry-run`, per-Remediate-action TTY prompts (skip-and-continue on decline), alt-user-name flow. Phase 16 closes documentation and the brownfield acceptance gate (AGT-02 still green on a pre-populated host).

Key locked decisions honored by this roadmap (from REQUIREMENTS.md "Design Philosophy" + PROJECT.md Key Decisions):

- **Detection is read-only.** The discovery layer never mutates host state. This makes `--dry-run` trivially correct and is the keystone invariant the Phase 12 gate checks.
- **Greenfield path must not regress.** A fresh host without any of the detected components must produce a result indistinguishable from v0.3.0's greenfield install. Every phase that touches a v0.3.0 provisioner gets a "greenfield Docker matrix stays green" success criterion.
- **Reuse-or-bail is the non-interactive default.** Cron, CI, ssh-non-interactive, and `curl | sudo bash` cannot safely overwrite pre-existing user state. In non-TTY mode, mutating Remediate requires the single `--yes` consent flag (no per-action flags) — Unix-convention shape (`apt install -y` / `pacman --noconfirm`). In TTY mode, every Remediate is its own prompt; declining skips that one remediation and continues.
- **Brownfield-AGT-02 is the milestone-close gate.** Same canonical bug class as v0.3.0 (Claude Code self-update, zero EACCES against the live Anthropic CDN), but verified on a host that completed an aware-install against a pre-populated environment. This is the v0.3.4 phase-close-gate equivalent of v0.3.0's TST-07.
- **Behavior-test discipline carries over.** Every requirement closes with at least one verifiable check (bats @test, audit doc, ADR, CI run citation, or manual smoke transcript) before its phase closes. behavior-coverage-auditor invoked at every phase boundary.
- **AgentLinux only owns its catalog.** Detection and Reuse target the install user, Node.js + npm prefix, the sudoers drop-in, and the three catalog agents (claude-code, gsd, playwright). Arbitrary other npm globals are out of scope.

## Phases

**Phase Numbering:**
- Integer phases (12, 13, 14, 15, 16): Planned milestone work, executed in numeric order
- Decimal phases (e.g., 13.1) reserved for urgent insertions discovered during the milestone (precedent: v0.3.0 Phase 5.1)

- [ ] **Phase 12: Detection Layer** — Read-only discovery primitives covering install user, Node.js sources, npm prefix, catalog agents, sudoers drop-in; pre-flight report in human text + stable JSON.
- [ ] **Phase 13: Reuse Wiring** — Plumb DET output into existing provisioners and the recipe runner so they short-circuit when detected components match contract; first end-to-end brownfield smoke.
- [ ] **Phase 14: Remediate + Consent Flag + Exit Codes** — Mutating fix paths (chown npm prefix, refresh PATH wiring, install missing/drifted sudoers, reinstall broken catalog agent), single `--yes` consent flag for non-TTY mode (Unix-convention, matching `apt install -y`), structured exit codes 64/65/1 that downstream phases honor. Per-action TTY prompts land in Phase 15.
- [ ] **Phase 15: Pre-flight UX** — `--dry-run`, interactive `Proceed? [y/N]` for state-overwriting actions, alt-user-name prompt for incompatible existing user, JSON-format finalization for the report.
- [ ] **Phase 16: Documentation + Brownfield Acceptance Gate** — README "Brownfield install" section, `docs/MIGRATION.md` with four worked scenarios, milestone-close brownfield-AGT-02 smoke transcript on a pre-populated host.

## Phase Details

### Phase 12: Detection Layer
**Goal**: A pre-flight `agentlinux install`-driven discovery pass enumerates every component AgentLinux owns on the host (install user, Node.js installations, npm global prefix, catalog agents, sudoers drop-in) and emits a stable, parseable report in two formats — human-readable text by default, structured JSON via `--report-format=json` — without writing any state to the host. The detection layer is the read-only foundation Phases 13-15 build on.
**Depends on**: Nothing (first v0.3.4 phase; runs against the v0.3.0 installer surface as-is)
**Requirements**: DET-01, DET-02, DET-03, DET-04, DET-05, DET-06
**Success Criteria** (what must be TRUE):
  1. Running `agentlinux install --report-only` (or the equivalent dry-run pre-cursor introduced in Phase 15) on a host with a manually-created `agent` user produces a report whose user section names the UID, GID, login shell, home directory, group memberships (`id -nG`), and home-writability flag — DET-01.
  2. The same report enumerates pre-existing Node.js installations across all eight covered sources (NodeSource APT, distro APT, nvm, fnm, volta, mise, asdf-node, manual `/usr/local/bin/node`); for each entry it captures binary path, `node --version` output, install method, and the install-user-can-write-to-global-prefix boolean — DET-02.
  3. The same report names the npm global prefix the install user resolves to, its filesystem path, ownership (`stat -c %U:%G`), writability for the install user, and surfaces both per-user override and system fallback when both exist — DET-03.
  4. The same report classifies each catalog agent (claude-code, gsd, playwright) as `healthy` / `broken` / `absent` based on binary presence on the install user's PATH, version-source-specific probe (`claude --version`, `get-shit-done-cc --help` banner-grep, `playwright --version`), binary ownership, and a quick `--help` exit-zero health probe — DET-04.
  5. The same report names whether `/etc/sudoers.d/agentlinux` exists, captures its mode + ownership + SHA256, and flags drift from the ADR-012 expected exact line; the file is never edited or removed by detection — DET-05.
  6. The report renders in two formats: human text (default, color-aware, used by every other success criterion above) and stable JSON (`--report-format=json`); the JSON schema is documented and versioned, and a smoke test parses it via `jq` to extract every captured field — DET-06.
  7. Greenfield invariant: running detection on a fresh Ubuntu 22.04 + 24.04 Docker container surfaces every component as `absent` and the existing v0.3.0 bats matrix stays green (zero regression on the 66/66 baseline).
  8. Read-only invariant: a no-op observer (`stat` over /etc, /home, /usr/local/bin, /opt, ~agent before-and-after) confirms detection wrote zero bytes; verified by a dedicated bats @test.
**Plans**: TBD (estimated 3 plans — one per detection module wave + one for JSON schema + report wiring)
**UI hint**: no

### Phase 13: Reuse Wiring
**Goal**: When the Phase 12 detection layer reports a compatible install user, a satisfying Node.js installation, or a healthy catalog agent at a path the recipe would have written to, the corresponding v0.3.0 provisioner / recipe runner short-circuits instead of clobbering. AgentLinux behaves on a brownfield host with all-compatible state as cleanly as on a greenfield host — no surprise overwrites, no `useradd` racing an existing user, no `npm install -g` clobbering a healthy install.
**Depends on**: Phase 12 (Reuse decisions consume the DET report)
**Requirements**: REUSE-01, REUSE-02, REUSE-03
**Success Criteria** (what must be TRUE):
  1. On a host with a pre-existing `agent` user that has bash login shell + writable home, `agentlinux install` skips the `useradd` step in `10-agent-user.sh`; subsequent provisioners (PATH wiring, sudoers, etc.) attach to the existing user; the skip is logged with the resolved UID and references the pre-flight report — REUSE-01.
  2. On a host with Node 22 LTS already installed (any of the eight DET-02 sources) and an npm global prefix the install user can write to, `agentlinux install` skips both the apt installation and prefix bootstrap in `30-nodejs.sh`; the skip is logged with `node --version`, prefix path, and detected source — REUSE-02.
  3. On a host with a healthy + version-pinned catalog agent at the path the recipe would have written to, `agentlinux install <agent>` is a no-op short-circuit; a `reused` sentinel is written so subsequent `agentlinux list` / `upgrade` / `remove` operate on the detected install identically to one AgentLinux placed itself — REUSE-03.
  4. End-to-end brownfield smoke: a Docker container pre-populated with a manually-created `agent` user + NodeSource Node 22 + `claude-code` global completes `agentlinux install` without any `useradd` / apt-install / `npm install -g claude-code` invocation; transcript captured to a phase audit doc.
  5. Greenfield invariant: the existing v0.3.0 bats matrix on a fresh container stays green (66/66 on Ubuntu 22.04 + 24.04). Phase 12's read-only invariant remains intact (Phase 13 is the first phase that mutates state, but only on the Create branch — Reuse and Bail still write zero).
**Plans**: TBD (estimated 2 plans — provisioner-side short-circuits in `10-*.sh`/`30-*.sh`, then recipe-runner side `agentlinux install <agent>` no-op + brownfield smoke bats coverage)
**UI hint**: no

### Phase 14: Remediate + Consent Flag + Exit Codes
**Goal**: When Phase 12 detection finds a fixable defect (wrong-owner npm prefix, missing PATH wiring on the existing install user, missing-or-drifted sudoers drop-in, broken catalog agent), `agentlinux install` can fix it in place. In non-TTY contexts (cron, CI, `curl | sudo bash`) any state-overwriting Remediate is gated behind a single `--yes` consent flag (Unix-convention shape, matching `apt install -y` / `pacman --noconfirm`); without `--yes` the installer bails with a structured error that itemizes which components needed Remediate. Per-action TTY prompts land in Phase 15. Structured exit codes (64 EX_USAGE, 65 EX_DATAERR, 1 runtime) are introduced here and honored by every subsequent phase, providing the contract that downstream UX (Phase 15) and CI wrappers can branch on.
**Depends on**: Phase 13 (Remediate runs on the same dispatched-provisioner path that Reuse short-circuits; the flag surface is the policy gate that distinguishes the two)
**Requirements**: REMEDIATE-01, REMEDIATE-02, REMEDIATE-03, REMEDIATE-04, UX-03, UX-05
**Success Criteria** (what must be TRUE):
  1. On a host where the install user's npm global prefix has wrong ownership (root-owned with no install-user write access, or owned by an unexpected user), invoking `agentlinux install --yes` in non-TTY mode either re-`chown`s the prefix to the install user (when the prefix path is under the install user's home and the prefix is empty/trivially salvageable) or rebases npm-global to `~<user>/.npm-global` with module migration; without `--yes` in non-TTY mode the action is `Bail` with exit 65 (the bail message itemizes the fixable defect and points at `--yes` and `--dry-run`) — REMEDIATE-01.
  2. On a host where the existing install user is missing the six-mode PATH wiring (BHV-02..06: profile.d, .bashrc-at-top, agentlinux.env, cron.d), the PATH-wiring provisioner re-runs additively via `ensure_marker_block`; pre-existing shell init customizations of the user are never edited line-by-line; no consent prompt or flag is required (additive idempotent action) — REMEDIATE-02.
  3. On a host where `/etc/sudoers.d/agentlinux` is missing, the sudoers provisioner installs the canonical ADR-012 line via the v0.3.0 visudo-gated install path without prompt or flag (additive); when the file exists but its SHA256 drifts from ADR-012, the overwrite in non-TTY mode is gated by `--yes` and is `Bail` with exit 65 without it — REMEDIATE-03.
  4. On a host where a catalog agent is `broken` per DET-04 (binary present but health check fails, or version reports unparseable string, or symlink target missing), invoking `agentlinux install --yes` in non-TTY mode runs the recipe's `uninstall.sh` followed by `install.sh`; user data under `~/.claude/`, `~/.cache/ms-playwright/`, etc. is preserved per CAT-04; without `--yes` the broken agent is `Bail` — REMEDIATE-04.
  5. Non-interactive default contract: when stdin is not a TTY, `agentlinux install` reuses-or-bails by default; the single `--yes` consent flag (no per-action flags) opts into all required Remediate actions in one shot; without `--yes` the installer exits with a structured non-zero code naming every component that needed Remediate — UX-03.
  6. Structured exit codes contract: `64` (`EX_USAGE`) for bad command-line flags or contradictory options, `65` (`EX_DATAERR`) for incompatible host state surfaced by detection, `1` for runtime failures during the Create / Remediate path; documented in `agentlinux install --help` and consumable by CI wrappers — UX-05.
  7. Greenfield invariant: a fresh container completes `agentlinux install` (no Remediate flags needed; no Remediate paths fire) and the v0.3.0 bats matrix stays green (66/66 on Ubuntu 22.04 + 24.04).
**Plans**: TBD (estimated 3 plans — REMEDIATE-01..04 across two waves of provisioner / recipe-runner edits, then UX-03/UX-05 `--yes` parsing + exit-code wiring + phase-close audit)
**UI hint**: no

### Phase 15: Pre-flight UX
**Goal**: A user invoking `agentlinux install` on a brownfield host gets the right experience for their context — a non-mutating preview via `--dry-run`, an interactive `Proceed? [y/N]` confirmation for any state-overwriting Remediate action when stdin is a TTY, and a graceful alternate-user-name flow when the existing `agent` user is incompatible. The pre-flight report shipped in Phase 12 reaches its final shape (text + JSON parity, schema versioned).
**Depends on**: Phase 14 (interactive prompts gate the Remediate paths Phase 14 introduces; `--dry-run` exercises the full Phase 12-14 detection-and-decision pipeline)
**Requirements**: UX-01, UX-02, UX-04
**Success Criteria** (what must be TRUE):
  1. `agentlinux install --dry-run` runs the full pre-flight discovery pass, prints the Reuse / Create / Remediate / Bail report (text by default, JSON when `--report-format=json`), and exits 0 without writing any state to the host; re-running `agentlinux install` immediately after `--dry-run` produces identical detection output (the dry-run is observably non-mutating) — UX-01.
  2. When stdin is a TTY, `agentlinux install` prints the pre-flight report and then issues a **per-action prompt** for each Remediate action that overwrites pre-existing user state (REMEDIATE-01 ownership chown, REMEDIATE-03 sudoers drift overwrite, REMEDIATE-04 reinstall-broken): `Proceed with this remediation? [Y/n]`. Declining a prompt **skips that one remediation, logs a warning, and continues the install** with the remaining components (the offending component is left as-is, treated as `Reuse-with-warning`). Additive actions (PATH wiring, missing-file sudoers install, fresh-component Create) run without confirmation. `--yes` is honored in TTY mode too (auto-approves every prompt) — UX-02.
  3. When DET-01 surfaces an incompatible existing install user (wrong shell, no writable home, conflicting UID, or pre-existing user with `--user=` mismatch), interactive mode prompts for an alternate user name with a numerically-suffixed default offer (e.g. `agent2`); non-interactive mode bails with exit code 65 (`EX_DATAERR`) and a remediation hint that names the conflicting attribute and suggests `--user=NAME` as the resolution — UX-04.
  4. JSON-format report finalization: the schema is published at a stable, versioned path; a CI smoke parses every documented field via `jq`; field-removal or breaking-change requires a schema-version bump documented in an ADR.
  5. Greenfield invariant: a fresh container's `agentlinux install --dry-run` produces a report where every component is `absent` → `Create`; running `agentlinux install` after the dry-run produces a v0.3.0-identical greenfield install (66/66 bats green).
**Plans**: TBD (estimated 2 plans — `--dry-run` + interactive prompts + alt-user flow as one wave, JSON schema finalization + phase-close audit as the second)
**UI hint**: no

### Phase 16: Documentation + Brownfield Acceptance Gate
**Goal**: A user landing on the README discovers AgentLinux's brownfield contract on the canonical install path; a user with a partially-populated host follows `docs/MIGRATION.md` to the right flag set and the right outcome for their scenario; the milestone closes only when AGT-02 (Claude Code self-update with zero EACCES against the live Anthropic CDN) is green on a host that completed an aware-install against a pre-populated environment.
**Depends on**: Phase 15 (documentation describes the final UX — `--dry-run` + interactive prompts + flags — which only stabilizes at Phase 15 close)
**Requirements**: DOC-01, DOC-02
**Success Criteria** (what must be TRUE):
  1. README has a "Brownfield install" section explaining the detection pass + dry-run + the four states (Reuse / Create / Remediate / Bail) with a worked example transcript on a host that has Claude Code already installed; the section is linked from the README's main "Install" section — DOC-01.
  2. `docs/MIGRATION.md` walks through four representative pre-existing-setup scenarios: (a) `agent` user from a manual `useradd` setup, (b) Node.js from NodeSource that is already correct, (c) Claude Code installed under root that needs reinstall under the agent user, (d) Playwright with a broken chromium cache; each scenario shows the pre-flight report output, the user's decision tree, the flags they would pass in non-interactive mode, and the resulting host state; README links to it — DOC-02.
  3. **Milestone-close gate (brownfield-AGT-02):** on a Docker container pre-populated with a manually-created `agent` user + NodeSource Node 22 + `claude-code` global + `gsd` global + `playwright` global, `agentlinux install` (with whatever Remediate flags the scenario's pre-flight report justifies) completes; afterwards `sudo -u agent -H bash --login -c 'claude update'` against the live Anthropic CDN exits 0 with zero EACCES / permission-denied lines and version monotonicity holds (`sort -V` confirms post >= pre); transcript committed to `docs/audits/v0.3.4/AGT-02-brownfield-acceptance.md`. This is the v0.3.4 phase-close-gate equivalent of v0.3.0's TST-07.
  4. Greenfield invariant: the v0.3.0 greenfield AGT-02 release-gate test (`tests/bats/51-agt02-release-gate.bats`) stays green on Ubuntu 22.04 + 24.04 Docker; the brownfield path is additive only.
  5. Phase-close audit `.planning/phases/16-documentation-brownfield-acceptance/16-AUDIT.md` cites every v0.3.4 requirement's evidence (bats @test reference, audit doc path, ADR id, CI run URL, or smoke transcript); behavior-coverage-auditor emits `GATE: GREEN`; v0.3.4 is release-ready.
**Plans**: TBD (estimated 2 plans — DOC-01 README + DOC-02 MIGRATION.md as one wave, brownfield-AGT-02 smoke + phase-close audit + milestone-close audit as the second)

## Progress

**Execution Order:**
Phases execute in numeric order: 12 → 13 → 14 → 15 → 16. Decimal phases reserved for urgent insertions (precedent: v0.3.0 Phase 5.1).

| Phase | Plans Estimated | Status | Completed |
|-------|-----------------|--------|-----------|
| 12. Detection Layer | 2/3 | In Progress|  |
| 13. Reuse Wiring | ~2 | Not started | - |
| 14. Remediate + Consent Flag + Exit Codes | ~3 | Not started | - |
| 15. Pre-flight UX | ~2 | Not started | - |
| 16. Documentation + Brownfield Acceptance Gate | ~2 | Not started | - |
| **Total** | **~12 plans** | 0/5 phases done | — |

## Coverage Summary

**Total v0.3.4 requirements:** 20 (6 DET + 3 REUSE + 4 REMEDIATE + 5 UX + 2 DOC)
**Mapped:** 20 / 20
**Orphaned:** 0

Requirement allocation per phase:

| Phase | Requirements | Count |
|-------|--------------|-------|
| 12 Detection Layer | DET-01, DET-02, DET-03, DET-04, DET-05, DET-06 | 6 |
| 13 Reuse Wiring | REUSE-01, REUSE-02, REUSE-03 | 3 |
| 14 Remediate + Consent Flag + Exit Codes | REMEDIATE-01, REMEDIATE-02, REMEDIATE-03, REMEDIATE-04, UX-03, UX-05 | 6 |
| 15 Pre-flight UX | UX-01, UX-02, UX-04 | 3 |
| 16 Documentation + Brownfield Acceptance Gate | DOC-01, DOC-02 | 2 |
| **Total** | | **20** |

**Allocation rationale:**

- **DET-01..06 → Phase 12.** All six detection requirements share a single read-only invariant; they're the foundation Phases 13-15 build on. JSON report (DET-06) lands here too — the schema is referenced by every subsequent phase, so it must stabilize early; Phase 15 finalizes versioning + schema-bump policy but does not redesign the schema.
- **REUSE-01..03 → Phase 13.** All three short-circuit requirements consume the DET report; they share the "Reuse decision when component matches contract" semantics. Splitting them across phases would force Phase 14 / 15 to repeat the wiring; they're cheapest as one wave.
- **REMEDIATE-01..04 + UX-03 + UX-05 → Phase 14.** The four mutating fix paths share the "single `--yes` consent flag in non-TTY mode" gate (UX-03). The structured exit codes (UX-05) are introduced here because Remediate is the first phase whose Bail path needs to distinguish "incompatible host state" (65) from "runtime failure" (1) from "bad flag" (64); downstream phases honor the contract but don't reshape it. UX-03 and UX-05 are owned by Phase 14 because they introduce the consent and exit-code surfaces; UX-02 (per-Remediate-action TTY prompts with skip-and-continue) and UX-04 (alt-user-name flow) are owned by Phase 15 because they're TTY-side polish on top of the Phase 14 contract.
- **UX-01 + UX-02 + UX-04 → Phase 15.** `--dry-run` (UX-01) exercises the full Phase 12-14 pipeline non-mutatingly; the interactive prompts (UX-02) and alt-user-name flow (UX-04) are TTY-mode polish on top of the Phase 14 flag surface. Putting them in their own phase keeps Phase 14's scope tight ("mutating contract") and Phase 15's scope coherent ("user-facing pre-flight UX").
- **DOC-01 + DOC-02 → Phase 16.** Documentation describes the final UX, which only stabilizes at Phase 15 close; both DOCs are co-located with the milestone-close brownfield-AGT-02 acceptance gate, which is the natural milestone-close ceremony.

**Notes on verification:**

- Most v0.3.4 work surfaces as bash + TypeScript edits in the existing v0.3.0 plugin tree (`plugin/bin/agentlinux-install`, `plugin/provisioner/*.sh`, `plugin/cli/src/`). bats coverage in `tests/bats/` is the primary verification surface for DET / REUSE / REMEDIATE / UX requirements (per ADR-002 behavior-test contract). DOC requirements close on inspection + a presence check in the phase audit. The brownfield-AGT-02 milestone-close gate closes on a manual smoke transcript committed to `docs/audits/v0.3.4/AGT-02-brownfield-acceptance.md`.
- The phase-close gate convention (TST-07 / v0.4.0 phase-AUDIT.md pattern) carries over: every requirement must close with a cited evidence artifact in its phase's AUDIT doc before behavior-coverage-auditor emits GREEN.
- The greenfield invariant ("v0.3.0 bats matrix stays green on a fresh container") is checked at every phase close — Phases 13, 14, 15 all touch v0.3.0 provisioners; Phase 12 only adds new code paths but is checked anyway as a defense-in-depth measure.
- The brownfield acceptance gate (AGT-02 still green on a pre-populated host) is the milestone-close gate and lives in Phase 16's success criteria as a hard requirement, not a stretch goal.

## Open Questions for Discuss-Phase

These are open questions to resolve in `/gsd-discuss-phase 12` (and subsequent phases):

- **JSON report schema versioning**: monotonically-incrementing integer `schema_version: N` field, or semver-style `0.1.0`? Decided in Phase 12; the field exists from day 1 either way to avoid a breaking change later.
- **DET-02 source-detection scope**: do nvm / fnm / volta / mise detection hooks also detect *which* Node version is *active* in the install user's shell context, or just which version is installed under the manager's prefix? Decided in Phase 12; affects the "writable to global prefix" boolean shape.
- **REMEDIATE-01 chown vs. rebase split**: when is rebase preferred over in-place chown? Decided in Phase 14; a candidate heuristic is "rebase whenever the prefix is outside the install user's home" — locks via an ADR if non-trivial.
- **UX-04 alt-user-name default suffix**: `agent2` (numeric increment) vs. `agentlinux-agent` (named) vs. user-specified-only? Decided in Phase 15; affects the prompt's default offer.
- **Backwards-compat policy for Bail messages**: are exit-65 messages part of the public API (CI wrappers may grep them)? Decided in Phase 14; if yes, locks via an ADR; if no, free to evolve message text.
