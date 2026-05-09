# Stability Model Reconsideration — Catalog Install/Upgrade/Remove

**Date:** 2026-04-19
**Context:** User reframing during Phase 4 smart-discuss — "ship stable curated versions, support user-owned escape hatch, reconcile on release." Earlier research (`cli-vs-apt-advisor.md`) rejected on criterion-1 grounds: that research assumed we wanted latest-always; user explicitly wants controlled-lag.
**Outcome:** Option **A'** (custom CLI + version-locked catalog + reconcile verb + pin) recommended. Supersedes earlier recommendation (which was effectively "thin wrapper" = rejected D').

---

## The Reframe

Earlier research (2026-04-18) recommended Option A (custom CLI + `npm install -g` pass-through) on three arguments:
1. apt lags upstream (problem if we want latest).
2. apt + npm self-update = split-brain.
3. CAT-03 submitter friction.

User's reframing (2026-04-19):
> "Last GSD update I hit an upstream bug fixed days later. I want to save my users from poor upstream testing. Ship a STABLE version they can rely on. Let power-users go ahead if they want — detect divergence, reconcile on next release. Don't be a thin wrapper around npm — that's of no value to users."

This flips argument (1): lagging upstream is now a **feature**, not a bug. But A' achieves *controlled* lag (pinned_version, CI-tested) where B' lags uncontrolledly. Arguments (2) and (3) are unchanged against B'.

## Updated Comparison Table (17 criteria × 5 options)

Scoring: `++` strong, `+` fit, `~` partial, `-` poor, `--` blocker.

| # | Criterion | A' CLI + pinned | B' Per-agent .deb | C' Lockfile + profile | D' Thin wrapper | E' Hybrid (CLI-as-.deb + A') |
|---|-----------|:---:|:---:|:---:|:---:|:---:|
| 1 | **Version pinning** (curated CI-tested combo) | `++` `pinned_version` field | `++` .deb IS the pin | `++` lockfile is the pin | `--` no pin | `++` (delegates to A') |
| 2 | **Testing-gate before ship** | `++` Docker+QEMU on pinned combo | `+` per-.deb build matrix | `++` lockfile drives CI | `--` "tested" = whatever latest | `++` |
| 3 | **Divergence detection** | `+` `npm ls -g` vs pin | `+` fs-detectable shadow | `++` profile diff first-class | `--` no concept | `+` |
| 4 | **Reconciliation UX** | `+` 3-way per agent | `~` `apt upgrade` blunt | `++` profile diff | `--` no concept | `+` |
| 5 | **Escape-hatch friction** | `++` record divergence, don't fight | `-` split-brain (AGT-02 regression) | `+` profile detects mismatch | `n/a` | `++` |
| 6 | **Continuous-flow cadence** | `++` JSON-line edit, minutes | `-` rebuild N .debs + re-sign + republish, hours | `++` lockfile edit | `++` (no work, no value) | `~` agent fast, CLI-.deb republish on CLI bumps |
| 7 | **"Why use AgentLinux?"** | Curated combo + reconcile | apt-shaped install of npm tools — weak | Reproducible atomic profiles | Nothing | A' value + apt-bootstrap |
| 8 | **Ubuntu 22.04/24.04 fit** | `++` | `+` (needs PPA/INF-01) | `++` | `++` | `+` |
| 9 | **v0.4+ multi-distro (DST-01..03)** | `++` portable bash recipes | `--` .deb needs .rpm/pacman parallel tracks | `++` portable | `++` | `~` CLI portable, .deb side not |
| 10 | **CAT-03 (entry + recipe, no CLI edit)** | `++` `pinned_version` in JSON | `--` submitter authors full `debian/` tree | `++` lockfile pin | `+` | `++` |
| 11 | **AGT-02 under version-lock** | `++` permission invariant holds | `--` split-brain regression | `++` agent-owned prefix | `++` | `++` |
| 12 | **INST-04 (`--purge`)** | `++` `npm uninstall -g` + sentinel | `+` apt-remove + npm-shadow cleanup needed | `++` profile unlink + GC | `+` | `+` |
| 13 | **ADR-004 per-user npm prefix** | `++` by construction | `~` postinst-as-root defeats audit | `++` | `+` | `++` |
| 14 | **ADR-009 no Snap** | `++` | `++` | `++` | `++` | `++` |
| 15 | **Submitter experience** | JSON + install.sh + bump pin | Full `debian/` tree + sign | JSON + lockfile entry | JSON only | Same as A' |
| 16 | **v0.3.0 cost** | `+` +2 plans vs current | `--` +4-6 plans incl. INF-01 | `~` +2 plans | `++` zero extra | `--` A' + PPA for CLI |
| 17 | **Ongoing maintenance** | `+` CLI + JSON snapshot | `--` PPA index, signing rotation, per-agent pipelines | `+` CLI + lockfile | `+` minimal | `~` A' + PPA |

## End-to-End Divergence Walkthrough (Option A')

**Setup:** AgentLinux 0.3.0 ships with pinned combo `claude-code@2.1.7 + gsd@1.42.0 + playwright@1.55.0`. User runs `claude update` → claude-code jumps to `2.2.0`. AgentLinux 0.3.1 ships pinning `claude-code@2.1.8`. User runs `agentlinux upgrade`.

```
$ agentlinux upgrade
Reading catalog snapshot: /opt/agentlinux/catalog/0.3.1/catalog.json
Comparing installed versions to curated combo:

  claude-code   user-installed: 2.2.0   ← override (you ran `claude update`)
                curated 0.3.1:  2.1.8
                last curated:   2.1.7

  gsd           user-installed: 1.42.0  ← matches curated 0.3.0
                curated 0.3.1:  1.42.1
                last curated:   1.42.0

  playwright    user-installed: 1.55.0  ← matches curated 0.3.1 (no change)
                curated 0.3.1:  1.55.0

Reconcile? Choose per agent:
  claude-code:  [k]eep your override 2.2.0  /  [c]urated 2.1.8  /  [l]atest npm
  gsd:          [k]eep 1.42.0  /  [c]urated 1.42.1  /  [l]atest npm
  playwright:   already in sync — no action

Or apply across all: --reset-all-curated / --respect-overrides / --all-latest
```

User picks `c` for gsd, `k` for claude-code. CLI runs `sudo -u agent -H npm install -g gsd@1.42.1`, leaves claude-code alone, writes `/opt/agentlinux/state/installed.json` recording source-of-truth per agent. Override flag is sticky — next `agentlinux upgrade` continues to surface the claude-code diff until user explicitly clears with `agentlinux pin claude-code=curated`.

## AGT-02 Under Version-Lock

AGT-02 is a **permission invariant**, not a **version invariant**. Under A':
- `agentlinux install claude-code` → `sudo -u agent -H npm install -g @anthropic-ai/claude-code@2.1.7` → binary at `/home/agent/.npm-global/bin/claude`.
- User runs `claude update` → Claude Code's auto-updater detects npm-global → runs `npm install -g @latest` as agent user → writes to same agent-owned path → success, no EACCES.
- Result: claude-code now 2.2.0; AGT-02 passes; `agentlinux list` surfaces divergence on next run.

**Add companion test AGT-02b**: install pinned version, assert `claude --version == pinned_version`, no EACCES. Verifies "version-lock mechanism works."

## CI Testing-Gate Spec (Phase 6)

Before tagging AgentLinux 0.3.1:
- (a) Install pinned combo: `agentlinux install --all-curated` + run all bats.
- (b) Smoke-test: `claude --version == 2.1.7`, `gsd --version`, `npx playwright --version`.
- (c) Canonical AGT-02: `claude update` from 2.1.7, assert no EACCES, version increased.
- (d) Snapshot reproducibility: re-install from frozen snapshot — byte-identical sentinels.
- (e) Rollback test: install 0.3.1 combo → `agentlinux upgrade --pin-from snapshot/0.3.0` → assert versions revert.

Under A', all five steps run against the same single tarball + catalog snapshot — ~30-60 min total CI.

## Continuous-Flow Cadence

Anthropic ships `claude-code@2.1.8` Monday 09:00 → AgentLinux 0.3.1 ships:

| Step | A' | B' | C' | E' |
|------|----|----|----|----|
| Catalog PR edit | 5 min | 2-4 hr (debian/changelog, rebuild, sign) | 5 min | Same as A' |
| CI run | 30-60 min | 60-120 min | 30-60 min | 30-60 min |
| Release tag + publish | Minutes | 30-60 min (PPA index) | Minutes | +30 min if CLI changed |
| **Total** | **~1 hr** | **~5-7 hr** | **~1 hr** | **~1.5 hr** |

User's "continuous flow, days not weeks" → A', C', E' satisfy. B' borderline.

## Recommendation + Reversal Analysis

**Recommendation: Option A' (Custom CLI + version-locked catalog + reconcile/pin verbs).**

C' (lockfile + symlink profile) is genuinely competitive and arguably more elegant (Nix precedent), but its symlink-profile machinery adds ~2 plans, novel atomic-swap semantics, and GC story — significant new abstraction. v0.3.0 ships A'; treat C'-style profiles as v0.4+ UX upgrade if users want richer rollback.

**Reversal analysis vs earlier research:**
The earlier research recommended Option A on 3 arguments. The reframing does NOT invalidate them — it reinforces them. It DOES flip criterion #1 (latest→stable is now a feature), but A' achieves controlled lag via `pinned_version` while B' lags uncontrolledly.

The earlier "Option A" was effectively the now-rejected D' (thin wrapper, no pinning). User's reframing converts recommendation from "thin wrapper around npm" to "thin wrapper around npm WITH curated lockfile gate." **Strict superset — no pivot, just a missing layer.**

B' does not become competitive under new criteria. Split-brain (#11), poor reconcile (#4), non-portability (#9), submitter friction (#10) unchanged. PPA cadence (#6) now actively worse. The "version pinning" criterion (#1) satisfied equally well by A' via JSON field, with none of B''s costs.

## Phase 4 Scope Delta

Current Phase 4 (baseline Option A, 5 plans):

| Plan | Baseline (now D') | **Option A' (recommended)** |
|------|------|------|
| 04-01 | CLI scaffolding + `list` | Same + read `pinned_version` from catalog |
| 04-02 | `install` verb (npm pass-through) | `install` honors `pinned_version`; writes `installed.json` sentinel with version+source (curated\|override\|latest) |
| 04-03 | `remove` verb + `--purge` | Same + clears sentinel |
| 04-04 | Catalog schema + 3 entries | Schema adds `pinned_version` (required), `npm_package_name`, optional `version_constraint` |
| 04-05 | bats coverage | Same + pinned_version honor + divergence detection bats |
| **04-06 NEW** | — | **`agentlinux upgrade` verb + reconcile flow (3-way diff)** |
| **04-07 NEW** | — | **Catalog snapshot manifest shipped with release; `agentlinux pin` verb for sticky overrides** |

**Plan-count delta:** 5 → 7 plans.

Phase 5: AGT-02b "install pinned, assert version" added (1 extra `@test`, not a plan).

Phase 6: release pipeline ships catalog snapshot artifact alongside tarball (1 workflow step, not a plan).

## Escape-Hatch UX Spec (Option A')

**Detection** (on `agentlinux upgrade` or `agentlinux list --verbose`):
- Read `/opt/agentlinux/state/installed.json` (version+source recorded at install).
- Run `sudo -u agent -H npm ls -g --json --depth=0 <pkg>` → current version.
- Three states per agent:
  - `synced`: installed == sentinel == curated
  - `override-ahead`: installed > sentinel
  - `override-behind`: installed < sentinel

**`agentlinux list` output:**
```
NAME           STATUS                CURATED     INSTALLED
claude-code    [override-ahead]      2.1.7       2.2.0
gsd            [synced]              1.42.0      1.42.0
playwright     [not installed]       1.55.0      —
```

**Reconciliation commands:**
- `agentlinux upgrade` — interactive 3-way reconcile per diverged agent.
- `agentlinux upgrade --reset-all-curated` — accept all curated; clear override flags.
- `agentlinux upgrade --respect-overrides` — install curated only for non-overridden agents.
- `agentlinux upgrade --all-latest` — npm latest for all (sets all to override).
- `agentlinux pin <name>=curated` — accept curated for one; clear override.
- `agentlinux pin <name>=latest` — sticky-override, future upgrades won't nag.
- `agentlinux pin <name>=2.1.7` — pin to specific version (sticky override).

**Sticky-override semantics:** Flag set automatically when user picks `[k]eep` on upgrade. Cleared on `pin <name>=curated`. Precedent: Homebrew's `brew pin` (suppresses nag; `brew outdated` still surfaces).

## Prior-Art References

| System | Pattern | Steal-able |
|---|---|---|
| **Nix flakes + `flake.lock`** | Inputs pin to exact commits; `nix flake update` recreates lock; reproducible by construction | Lockfile-as-source-of-truth; install verb obeys it |
| **Homebrew `brew pin` + `brew outdated`** | Pin suppresses upgrade nag; outdated lists diff anyway | Sticky-override with non-suppressed list visibility |
| **mise `mise.lock` + `mise upgrade`** | `mise.toml` fuzzy (`node = "20"`); `mise.lock` exact (`20.5.7`); upgrade preserves precision | Two-layer: `version_constraint` fuzzy + `pinned_version` exact |
| **npm `package-lock.json` + `overrides`** | Lock pins resolved; `overrides` force a version | `agentlinux pin <name>=2.1.7` syntax |
| **Debian stable vs sid (apt-pinning)** | `/etc/apt/preferences.d/` for per-package pins; default "stable, don't surprise me" | Conceptual precedent for curated-default + documented escape |

## What to Do Next

1. **Author ADR-011** — "stability-first version pinning with explicit reconciliation." Captures reframe so re-litigation doesn't happen. Cites sticky-override, snapshot, reversal analysis.
2. **Update Phase 4 plan count 5 → 7** in ROADMAP.md. Add 04-06 (`upgrade` verb + reconcile) and 04-07 (snapshot + `pin` verb).
3. **Extend `plugin/catalog/schema.json`** — add `pinned_version` (required, semver), `npm_package_name` (required), `version_constraint` (optional, semver range).
4. **Add NEW requirements to REQUIREMENTS.md:**
   - **CAT-04**: Each catalog entry declares `pinned_version` validated by JSON Schema.
   - **CAT-05**: Release artifact includes catalog snapshot at `/opt/agentlinux/catalog/<release>/catalog.json`.
   - **CLI-06**: `agentlinux upgrade` detects per-agent divergence and offers per-agent reconcile.
   - **CLI-07**: `agentlinux pin <name>=<curated|latest|x.y.z>` sets persistent override.
   - **TST-08**: CI installs pinned combo and runs full bats suite before release tag.
   - **AGT-02b**: Installing pinned version produces exactly that version; `claude --version` matches `pinned_version`.
5. **Update Phase 6** scope — release pipeline publishes `catalog-<version>.json` sibling of tarball + `.sha256`.
6. **(Optional)** Create user-facing `docs/STABILITY-MODEL.md` documenting "we lag on purpose; here's how to override." Marketing-grade message.
7. **(Optional, v0.4+)** Follow-up research: migrate A' → C' (symlink profiles) for richer rollback UX. Defer.
