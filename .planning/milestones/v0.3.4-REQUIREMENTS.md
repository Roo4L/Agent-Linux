# Requirements: AgentLinux v0.3.4 — Aware Installation Process

**Defined:** 2026-05-09
**Milestone:** v0.3.4 Aware Installation Process
**Triggered by:** [AL-38 "Introduce proper migration pass for users with some AI setup already"](https://copiedwonder.atlassian.net/browse/AL-38)
**Core Value (carried from PROJECT.md):** An agent can be dropped into any supported Linux system and just work — provisioned correctly the first time. v0.3.4 extends "just work" to brownfield hosts where the user has already installed an agent toolchain by hand: AgentLinux must detect what is there, reuse what fits, remediate what is fixable, and bail clearly when it is not — without ever clobbering the user's pre-existing state.

## Design Philosophy (read first)

**Brownfield is the default, not the exception.** AL-38's reporter is the canonical user: an engineer running an agent in a long-lived VM that already has an `agent` user, Node.js, Claude Code, GSD, and likely Playwright. v0.3.0 assumed a fresh host and clobbers or aborts. v0.3.4 treats every component AgentLinux owns as potentially-already-present and decides per component.

The four states are exhaustive and exclusive:

| State | Meaning | Trigger |
|-------|---------|---------|
| **Reuse** | Detected component matches AgentLinux's contract; provisioner / recipe short-circuits | Detected + healthy + version-compatible + ownership-compatible |
| **Create** | Component absent; provisioner / recipe runs as in v0.3.0 (greenfield path) | Not detected |
| **Remediate** | Detected but with a fixable defect (wrong ownership, missing PATH wiring, drifted sudoers, broken install) | Detected + defect found + (interactive consent OR explicit flag) |
| **Bail** | Detected but with an irreconcilable defect (wrong UID, conflicting home, wrong shell on existing user, etc.); the installer surfaces a clear error + remediation hint and exits with a structured non-zero code | Detected + defect not auto-fixable OR non-interactive without `--remediate` |

**Detection is read-only.** The discovery layer never mutates host state. Mutation lives in the Reuse / Create / Remediate paths, which are gated by the pre-flight report. This makes `--dry-run` trivially correct (run discovery, print report, exit) and gives the user a deterministic preview of every change.

**Non-interactive default is reuse-or-bail.** Cron, CI, ssh-non-interactive, and `curl | sudo bash` cannot safely make policy decisions about pre-existing user state. v0.3.4's non-interactive mode reuses compatible state, runs the greenfield Create path on absent components, and bails on anything that needs Remediate. The user passes a single `--yes` flag (Unix-convention shape, matching `apt install -y` / `pacman --noconfirm`) to opt into all remediations in one shot — there are no per-action flags. In TTY-interactive mode, every Remediate action is its own prompt (`Proceed? [Y/n]`); declining a prompt skips that one remediation, logs a warning, and continues the install with the remaining components.

**The brownfield path must not regress the greenfield path.** AGT-02 (Claude Code self-update with zero EACCES against the live Anthropic CDN) — v0.3.0's canonical acceptance test — must stay green on a host that completed an aware-install against a pre-populated environment. This is the v0.3.4 phase-close gate (analogous to v0.3.0's TST-07).

**Behavior-test discipline carries over.** Every requirement closes with at least one verifiable check before its phase closes — bats @test, CI workflow citation, audit doc with command + output, or a documented manual smoke transcript. The TST-07 phase-close gate convention applies; behavior-coverage-auditor is invoked at every phase boundary.

## v0.3.4 Requirements

Grouped by category. Each `XXX-NN` is a testable, verifiable outcome — auditable before the phase closes.

### Detection (DET) — read-only discovery layer

- [x] **DET-01**: A pre-flight discovery pass identifies whether the install user (default `agent`, overridable via `--user=NAME`) already exists, and captures their UID, GID, login shell, home directory, group memberships (`id -nG`), and whether the home directory is writable. Captured in a structured pre-flight report.
- [x] **DET-02**: A pre-flight discovery pass identifies any pre-existing Node.js installation visible to the install user — sources covered: NodeSource APT, distro APT (`nodejs` package), nvm, fnm, volta, mise, asdf-node, pnpm-managed Node, and a manual `/usr/local/bin/node`. Captured per source: binary path, `node --version` output, install method, and "is the install user able to write to the global prefix" boolean.
- [x] **DET-03**: A pre-flight discovery pass identifies the npm global prefix that the install user would resolve to (`npm config get prefix --location=user` falling back to system), captures its filesystem path, ownership (`stat -c %U:%G`), and whether the install user can write to it. Multiple npm prefixes are surfaced (per-user override + system fallback both reported).
- [x] **DET-04**: A pre-flight discovery pass identifies pre-existing catalog agents (catalog ids `claude-code`, `gsd`, `playwright-cli`; binary names on PATH: `claude`, `get-shit-done-cc`, `playwright-cli` respectively). For each: binary path on the install user's PATH, version (via the agent's documented version source — `claude --version`, `get-shit-done-cc --help` banner-grep, `playwright-cli --version`), ownership of the binary, and a quick health probe (e.g. `claude --help` exit 0). Each is classified as `healthy`, `broken`, or `absent`.

  _Amended in Phase 12 discuss (2026-05-10): catalog actually ships `playwright-cli` (id + binary), not `playwright`; binary names diverge from catalog ids per recipe install paths._
- [x] **DET-05**: A pre-flight discovery pass identifies whether `/etc/sudoers.d/agentlinux` already exists. If present, captures the file's mode, ownership, and the SHA256 of its content; flags drift from ADR-012's expected exact-line content (`agent ALL=(ALL) NOPASSWD: ALL`). The detection pass never edits or removes the existing file.
- [x] **DET-06**: <del>The pre-flight report is emitted in two formats — a human-readable text format (default, color-aware) and a stable JSON format (`--report-format=json`). Both formats expose the same information; the JSON format is suitable for parsing by CI, smoke tests, or downstream tooling. The JSON schema is documented and versioned.</del>

  _Amended in Phase 12 discuss (2026-05-10) — Area 2 / D-05:_ The detection report renders in a human-readable text format (default, TTY-aware color, `[DET-NN] key=value` markers for grep stability). An undocumented `--report-format=json` flag emits the same captured data as a `jq -n`-built object for test-only consumption. **No JSON Schema document. No `schema_version` field. No ADR ceremony.** Bats @tests parse via `jq` for structural assertions.

### Reuse (REUSE) — short-circuit when detected component matches contract

- [x] **REUSE-01**: When DET-01 surfaces an existing install user with a compatible login shell (bash), a writable home directory, and (when `--user=NAME` was specified) the requested name, the user-creation provisioner (`10-agent-user.sh`) skips its `useradd` step and uses the existing user. The skip is logged with the resolved UID and a reference to the pre-flight report; subsequent provisioners (PATH wiring, sudoers, etc.) attach to the existing user.
- [x] **REUSE-02**: When DET-02 surfaces a Node.js installation that satisfies the project's pinned major version (Node 22 LTS line per ADR-005) AND has an npm global prefix the install user can write to, the Node.js provisioner (`30-nodejs.sh`) skips both the apt installation and the prefix bootstrap. The skip is logged with the resolved `node --version`, prefix path, and the source identifier (NodeSource / distro / nvm / etc.).
- [x] **REUSE-03**: When DET-04 surfaces a catalog agent that is `healthy`, installed at a path the agent recipe would have written to, and version-pinned within the catalog's compatibility window, `agentlinux install <agent>` is a no-op short-circuit. A `reused` sentinel record is written so subsequent `agentlinux list` / `upgrade` / `remove` operate on the detected install identically to one AgentLinux placed itself.

### Remediate (REMEDIATE) — fix the fixable, with explicit consent

- [x] **REMEDIATE-01**: When DET-03 finds the npm global prefix has wrong ownership (root-owned with no write access for the install user, or owned by an unexpected user), the installer either re-`chown`s the prefix to the install user (only if the prefix path resolves under the install user's home and is currently empty or trivially salvageable) or rebases npm-global to `~<install-user>/.npm-global` and migrates the existing global modules. Either action requires TTY-interactive confirmation (per-action prompt) OR the `--yes` flag in non-TTY mode.
- [x] **REMEDIATE-02**: When DET-01 surfaces an existing install user that is missing the six-mode PATH wiring (BHV-02..06: profile.d, .bashrc-at-top, agentlinux.env, cron.d), the PATH-wiring provisioner re-runs against that user using the existing `ensure_marker_block` primitives. The pre-existing shell init customizations of the user are never edited line-by-line — only the AgentLinux-managed marker block is added (or refreshed if drifted). No interactive consent required for PATH wiring (additive, idempotent, never overwrites user content).
- [x] **REMEDIATE-03**: When DET-05 finds `/etc/sudoers.d/agentlinux` is missing or its SHA256 does not match ADR-012's expected line, the sudoers provisioner installs the canonical version via the v0.3.0 visudo-gated install path. Drift overwrite requires TTY-interactive confirmation (per-action prompt) OR the `--yes` flag in non-TTY mode; a missing file installs without prompt (additive, not overwriting user state).
- [x] **REMEDIATE-04**: When DET-04 classifies a catalog agent as `broken` (binary present but health check fails, or version reports an unparseable string, or symlink target missing), the installer runs the recipe's `uninstall.sh` followed by `install.sh` to reinstall it cleanly. Reinstall requires TTY-interactive confirmation (per-action prompt) OR the `--yes` flag in non-TTY mode; the `uninstall.sh` step preserves user data per CAT-04.

### UX (UX) — pre-flight report, dry-run, interactive vs. non-interactive

- [x] **UX-01**: `agentlinux install --dry-run` runs the full pre-flight discovery pass, prints the Reuse / Create / Remediate / Bail report (text format by default, JSON when `--report-format=json`), and exits 0 without writing any state to the host. Re-running `agentlinux install` immediately after `--dry-run` produces identical detection output (the dry-run is observably non-mutating).
- [x] **UX-02**: When stdin is a TTY (interactive mode), `agentlinux install` prints the pre-flight report and then issues a **per-action prompt** for each Remediate action that overwrites pre-existing user state (REMEDIATE-01 ownership chown, REMEDIATE-03 sudoers drift overwrite, REMEDIATE-04 reinstall-broken): `Proceed with this remediation? [Y/n]`. Declining a prompt **skips that one remediation, logs a warning to the install transcript, and continues the install** with the remaining components — the offending component is left as-is, treated as `Reuse-with-warning`. Additive actions (PATH wiring, missing-file sudoers install, fresh-component Create) run without confirmation.
- [x] **UX-03**: When stdin is NOT a TTY (cron, CI, `ssh host 'agentlinux install'`, automation, `curl | sudo bash`), `agentlinux install` runs in non-interactive mode: defaults to reuse-or-bail, never prompts, never overwrites pre-existing user state. A single `--yes` flag (Unix-convention shape, matching `apt install -y` / `pacman --noconfirm`) opts into all Remediate actions in one shot. Without `--yes`, any required Remediate action causes the installer to bail with a structured non-zero code; the bail message itemizes which components needed Remediate and points the user at the `--yes` flag and at `--dry-run` for inspection. There are **no per-action flags** — `--yes` is the only consent surface in non-TTY mode.
- [x] **UX-04**: When DET-01 surfaces an incompatible existing install user (wrong shell, no writable home, conflicting UID, or pre-existing user with `--user=` mismatch), interactive mode prompts for an alternate user name (with the user's default offer being a numerically-suffixed variant — e.g. `agent2`); non-interactive mode bails with exit code 65 (`EX_DATAERR`) and a remediation hint that names the conflicting attribute and suggests `--user=NAME` as the resolution.
- [x] **UX-05**: Pre-flight failures surface as structured exit codes so wrappers, CI, and documentation can branch on the failure mode: `64` (`EX_USAGE`) for bad command-line flags or contradictory options; `65` (`EX_DATAERR`) for incompatible host state surfaced by detection; `1` for runtime failures during the Create / Remediate path. The codes are documented in README and in `agentlinux install --help`.

### Documentation (DOC)

- [x] **DOC-01**: README gains a "Brownfield install" section explaining the detection pass + dry-run + the four states (Reuse / Create / Remediate / Bail) with a worked example transcript on a host that has Claude Code already installed. The section is linked from the README's main "Install" section so a user landing on the canonical install path discovers the brownfield contract immediately.
- [x] **DOC-02**: A focused `docs/MIGRATION.md` walks through four representative pre-existing-setup scenarios: (a) `agent` user from a manual `useradd` setup, (b) Node.js from NodeSource that is already correct, (c) Claude Code installed under root that needs reinstall under the agent user, (d) Playwright with a broken chromium cache. Each scenario shows the pre-flight report output, the user's decision tree, the flags they would pass in non-interactive mode, and the resulting host state. README links to it.

## Future Requirements (not in this milestone)

- **Auto-migration of nvm / fnm / volta / mise managed Node.js to a system Node.js install.** Out of scope for v0.3.4; surfaced as `Bail` with a remediation hint pointing at the user-managed manager's own removal path.
- **Detection and reuse of arbitrary user-installed npm globals beyond the catalog** (`npx`, `tsx`, `vercel`, `pnpm`, etc.). Out of scope; AgentLinux only owns its catalog.
- **Brownfield support on Fedora / CentOS / Alma / Arch / openSUSE.** Out of scope for v0.3.4; brownfield-aware install is Ubuntu-only initially, the same OS surface as v0.3.0.
- **Migrating an existing user's shell init files (`.bashrc`, `.profile`).** Out of scope; v0.3.4 preserves additive `ensure_marker_block` semantics and never edits pre-existing lines.
- **Telemetry / opt-in pre-flight report upload for support purposes.** Out of scope; the report is local-only.

## Out of Scope (explicit exclusions)

**v0.3.4 out of scope:**
- Changing the v0.3.0 greenfield contract. Brownfield-aware install is additive: a fresh host without any of the detected components must produce a result indistinguishable from v0.3.0's greenfield install.
- Non-Ubuntu distro detection (no Fedora / CentOS / Alma / Arch / openSUSE). The Ubuntu LTS surface (22.04 / 24.04 / 26.04) carried from v0.3.0 is the v0.3.4 surface.
- Multi-arch (ARM). x86_64 only (carried forward).
- A GUI or TUI for the pre-flight report. CLI-only; the report is plain text + machine-readable JSON.
- Agent-tool detection beyond the existing three catalog agents. New agents land via catalog churn in feature milestones.
- Editing pre-existing shell init lines. AgentLinux's writes are exclusively in `ensure_marker_block` regions; user content outside the marker is never touched.
- Auto-rotating npm packages installed under a different user. If the install user's npm global prefix has unrelated content owned by another user, that is a `Bail`, not a `Remediate`.

**Permanently out of scope (carried from prior milestones):**
- User accounts or login functionality on website
- Blog or content management system
- Mobile app
- E-commerce / payments
- Multi-arch (ARM) — x86_64 only for now
- Docker-in-Docker inside the agent environment

## REQ-ID Traceability

Populated by gsd-roadmapper during ROADMAP creation. Empty initially.

| Requirement | Phase | Status |
|-------------|-------|--------|
| DET-01 | Phase 12 | Complete |
| DET-02 | Phase 12 | Complete |
| DET-03 | Phase 12 | Complete |
| DET-04 | Phase 12 | Complete |
| DET-05 | Phase 12 | Complete |
| DET-06 | Phase 12 | Complete |
| REUSE-01 | Phase 13 | Complete |
| REUSE-02 | Phase 13 | Complete |
| REUSE-03 | Phase 13 | Complete |
| REMEDIATE-01 | Phase 14 | Complete |
| REMEDIATE-02 | Phase 14 | Complete |
| REMEDIATE-03 | Phase 14 | Complete |
| REMEDIATE-04 | Phase 14 | Complete |
| UX-01 | Phase 15 | Complete |
| UX-02 | Phase 15 | Complete |
| UX-03 | Phase 14 | Complete |
| UX-04 | Phase 15 | Complete |
| UX-05 | Phase 14 | Complete |
| DOC-01 | Phase 16 | Complete |
| DOC-02 | Phase 16 | Complete |

**Coverage:**
- v0.3.4 requirements: 20 total
- Mapped to phases: 20 ✓ (filled by gsd-roadmapper 2026-05-09)
- Unmapped: 0
- Distribution: Phase 12 (DET-01..06) = 6; Phase 13 (REUSE-01..03) = 3; Phase 14 (REMEDIATE-01..04, UX-03, UX-05) = 6; Phase 15 (UX-01, UX-02, UX-04) = 3; Phase 16 (DOC-01..02) = 2.

## Verification Convention

Each requirement closes with at least one verifiable artifact before its phase closes (TST-07 phase-close pattern from v0.3.0):

| Verification kind | Where it lives |
|-------------------|----------------|
| Bats @test | `tests/bats/*.bats` (every DET / REUSE / REMEDIATE / UX requirement gets ≥1 @test referencing the REQ-ID in a comment or assertion) |
| Audit doc | `docs/audits/v0.3.4/<REQ-ID>-*.md` for any requirement closed by a manual smoke or tooling output |
| ADR | `docs/decisions/ADR-XXX-*.md` for design decisions surfaced during the milestone (e.g. report-JSON schema versioning, four-state taxonomy) |
| Workflow run citation | GitHub Actions run URL captured in the audit doc when CI is the verification path |
| Manual smoke transcript | Terminal-session paste committed to the audit doc with date and host, for the brownfield acceptance smoke |

The phase-close gate (analogous to v0.3.0's TST-07): every requirement has at least one of the above evidence forms cited in its phase's AUDIT.md, and the phase's behavior-coverage-auditor emits `GATE: GREEN`. The brownfield acceptance smoke (AGT-02 still green on a pre-populated host) is the milestone-close gate.

---
*Requirements defined: 2026-05-09*
*Last updated: 2026-05-09 — Traceability table populated by gsd-roadmapper (5 phases 12-16, 20/20 requirements mapped 1:1).*
