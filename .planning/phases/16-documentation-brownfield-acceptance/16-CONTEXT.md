# Phase 16: Documentation + Brownfield Acceptance Gate — Context

**Gathered:** 2026-05-26
**Status:** Ready for planning
**Mode:** Smart-discuss (autonomous batch-table, accept-all)

<domain>
## Phase Boundary

This is the v0.3.4 **milestone-close** phase. Three deliverables:

1. **DOC-01 — README "Brownfield install" section**: explains detection → 4 states (Reuse / Create / Remediate / Bail) → `--dry-run` → `--yes` flag → exit codes. Includes a worked-example transcript on a host with Claude Code already installed. Section linked from the README's main Install section.

2. **DOC-02 — `docs/MIGRATION.md`**: four worked scenarios — (a) `agent` user from manual `useradd`, (b) NodeSource Node.js already correct, (c) Claude Code under root needing reinstall under agent user, (d) Playwright with broken chromium cache. Each scenario shows: pre-flight report output, user decision tree, non-interactive flag set, resulting host state. README links to it.

3. **brownfield-AGT-02 milestone-close gate**: on a Docker container pre-populated with `agent` user + NodeSource Node 22 + `claude-code` global + `gsd` global + `playwright` global, `agentlinux install` (with appropriate Remediate flags) completes → `sudo -u agent -H bash --login -c 'claude update'` against live Anthropic CDN exits 0 with zero EACCES and version monotonicity holds. Transcript committed to `docs/audits/v0.3.4/AGT-02-brownfield-acceptance.md`. **This is v0.3.4's TST-07 equivalent — the release-readiness gate.**

**Greenfield invariant:** the v0.3.0 greenfield AGT-02 release-gate test (`tests/bats/51-agt02-release-gate.bats`) stays green; brownfield path is additive only.

**Milestone close:** behavior-coverage-auditor emits `GATE: GREEN` against all 20 v0.3.4 requirements with cited evidence in `16-AUDIT.md`.

</domain>

<decisions>
## Implementation Decisions

### Locked (user-confirmed via smart-discuss batch table 2026-05-26)

**D-16-01 — README brownfield section placement: MID-README (after main Install, before Catalog)**
- Discoverable on first scroll without breaking the greenfield happy-path flow.
- Section heading: `## Brownfield install (existing user / Node.js / agents)`.
- Linked from the main Install section via: `If you already have an agent user, Node.js, or any of these agents installed, see [Brownfield install](#brownfield-install).`
- Rationale: matches user's prior README-doesn't-bury-key-content preference; greenfield is still the primary flow but brownfield users find their guidance on first scroll.

**D-16-02 — MIGRATION.md scenario depth: FULL TRANSCRIPTS**
- One H2 section per scenario (a-d). Each section ~150-250 words:
  - **Setup:** What the host already has (concrete `apt list --installed | grep nodejs`, `id agent`, etc.)
  - **Pre-flight report:** copy-paste-able `agentlinux install --dry-run` output
  - **Decision tree:** 1-2 sentence narrative explaining what the user should choose
  - **Non-interactive command:** exact `agentlinux install --yes ...` invocation
  - **Resulting host state:** what changed + what was kept
- Concrete commands the user can paste; no abstractions or "use whichever flag suits your scenario" hand-waving.
- Rationale: this doc is consumed by users in incident-recovery mode (their install failed; they need a worked example NOW). Full transcripts > summary tables.

**D-16-03 — brownfield-AGT-02 smoke automation: BATS @TEST (CI-runnable)**
- New test file: `tests/bats/52-agt02-brownfield-gate.bats` (mirrors v0.3.0's `tests/bats/51-agt02-release-gate.bats` pattern).
- Test body:
  1. `setup_brownfield_host` (Phase 13 helper) populates the container with all 5 pre-existing artifacts (agent user manually created, NodeSource Node 22, claude-code global, gsd global, playwright global)
  2. Run `agentlinux install --yes` (must complete with 0 exit)
  3. `sudo -u agent -H bash --login -c 'claude update'` against the live Anthropic CDN (must exit 0; zero EACCES greps)
  4. Version monotonicity check via `sort -V`
  5. Test sidecar writes the transcript to `docs/audits/v0.3.4/AGT-02-brownfield-acceptance.md` (committed by Phase 16 close)
- Greenfield invariant preserved: `tests/bats/51-agt02-release-gate.bats` runs unchanged.
- Rationale: CI-runnable (no manual one-shot dependency on a human running it); matches v0.3.0's release-gate pattern; transcript captured automatically.

**D-16-04 — Phase 16 audit + milestone close: PER-REQ-CITED + behavior-coverage-auditor GATE: GREEN**
- `16-AUDIT.md` cites every v0.3.4 requirement (20 total: DET-01..06 + REUSE-01..03 + REMEDIATE-01..04 + UX-01..05 + DOC-01..02) with one-line evidence pointer (bats @test ref, audit doc path, ADR id, or CI run URL).
- Final paragraph: behavior-coverage-auditor invocation result with `GATE: GREEN` for the full v0.3.4 milestone.
- Milestone-close ceremony: after `16-AUDIT.md GATE: GREEN`, mark v0.3.4 complete in `.planning/STATE.md` + `.planning/ROADMAP.md`.

### Implicit from spec text (no discussion needed)

- **D-16-05 — Audit doc path locked**: `docs/audits/v0.3.4/AGT-02-brownfield-acceptance.md` (matches Phase 16 success criterion #3 verbatim).
- **D-16-06 — README link wiring**: main Install section AND a "What if my host already has stuff?" anchor link both point to the brownfield section.
- **D-16-07 — Four MIGRATION.md scenarios are mandatory** (locked by spec): (a) manual useradd `agent`, (b) NodeSource Node correct, (c) Claude Code under root, (d) Playwright broken chromium. No substitutions.
- **D-16-08 — Greenfield invariant**: `tests/bats/51-agt02-release-gate.bats` remains untouched; Phase 16 only ADDS `52-agt02-brownfield-gate.bats`.
- **D-16-09 — Transcript capture mechanism**: bats test writes to `docs/audits/v0.3.4/AGT-02-brownfield-acceptance.md` via a sidecar `cp` of the captured stdout; the test is also the audit-doc authoring step.

### Claude's Discretion

- README section's example transcript: pick whichever scenario reads cleanest (likely scenario c — Claude Code under root → reinstall under agent — since it exercises REMEDIATE-04 which is the most novel v0.3.4 feature)
- MIGRATION.md section ordering: alphabetical (a, b, c, d) per spec or thematic (simplest → hardest)? Claude's call. Likely thematic ordering (b → a → c → d in difficulty order) but mention this in section anchors so spec letters stay traceable.
- Whether the README brownfield section duplicates the MIGRATION.md transcripts or just links out: link out (avoid duplication, keep README scannable).
- Exact bats fixture composition for `52-agt02-brownfield-gate.bats` (single test that hits all 5 brownfield artifacts vs. per-artifact tests).
- Bot-vs-human transcript wording in `AGT-02-brownfield-acceptance.md` (the bats test writes the raw output; whether a human-readable header is prepended is style choice).

</decisions>

<code_context>
## Existing Code Insights

**Reusable assets:**
- `tests/bats/51-agt02-release-gate.bats` — v0.3.0 release-gate pattern; reference shape for `52-agt02-brownfield-gate.bats`
- `tests/bats/helpers/brownfield.bash::setup_brownfield_host` — Phase 13's brownfield fixture; covers agent user + NodeSource Node 22 + claude-code global; needs extension for gsd + playwright globals (or new `setup_brownfield_host_full` variant)
- `tests/bats/14-remediate.bats` Tests 51-54 — Phase 14's brownfield E2E pattern (PATH-MISMATCH, uninstall-fail, half-uninstalled) — reference for assertion shape
- `tests/bats/15-preflight-ux.bats` Tests 13-18 — Phase 15's alt-user E2E pattern; reference for TTY interaction
- `.planning/phases/{12,13,14,15}-*/AUDIT.md` — Phase audit format reference for `16-AUDIT.md`

**Existing docs to extend:**
- `README.md` — needs new `## Brownfield install` section
- `docs/` — needs new `docs/MIGRATION.md`
- `docs/audits/` — needs new `docs/audits/v0.3.4/` subdir + `AGT-02-brownfield-acceptance.md` (auto-generated by bats test)

**Integration points:**
- README's main Install section gains a one-liner link to Brownfield section
- README's TOC (if present) gains an entry
- Brownfield section's worked-example transcript matches MIGRATION.md scenario (c) literally — single source of truth for the transcript content

**Patterns to match:**
- README section headings use `## H2` (existing convention)
- Code blocks use triple-backtick + language hint (e.g., ` ```console ` for transcripts)
- MIGRATION.md doc style: see `docs/HARNESS.md` for an existing comparable structured-walkthrough doc

</code_context>

<specifics>
## Specific Ideas

**README brownfield section structure (sketch):**

```markdown
## Brownfield install (existing user / Node.js / agents)

If your host already has an `agent` user, a Node.js install, or any of the
catalog agents (claude-code, gsd, playwright), AgentLinux detects them up-front
and decides on a per-component basis: Reuse, Create, Remediate, or Bail.

**Preview first (zero changes):**

\`\`\`console
$ agentlinux install --dry-run
pre-flight report:
  user        agent      Reuse (exists, bash, writable home, NOPASSWD-apt)
  nodejs      v22.x      Reuse (correct version, install user can write to global prefix)
  claude-code v2.0.7     Remediate (REMEDIATE-04: installed under root; will reinstall under agent)
exit code: 0 (dry-run — no state changed)
\`\`\`

**Apply in non-interactive mode:**

\`\`\`console
$ agentlinux install --yes
[REMEDIATE-04] reinstalling claude-code under agent ownership
[INSTALL] complete in 47s
\`\`\`

For per-scenario walkthroughs (manual useradd, NodeSource, root-Claude,
broken Playwright), see [`docs/MIGRATION.md`](docs/MIGRATION.md).
```

**MIGRATION.md scenarios (ordering by difficulty):**

1. **Scenario (b) — NodeSource Node correct** (REUSE-02 happy path)
2. **Scenario (a) — manual useradd `agent`** (REUSE-01 happy path, possibly REMEDIATE-03 sudoers drift)
3. **Scenario (c) — Claude Code under root** (REMEDIATE-04 path)
4. **Scenario (d) — Playwright broken chromium** (REMEDIATE-04 path with broken binary)

**bats Test 52 (brownfield-AGT-02 gate):**

```bash
@test "BHV-52: brownfield-AGT-02 — pre-populated host, claude update zero EACCES" {
  setup_brownfield_host_full   # NEW helper: agent + NodeSource + claude + gsd + playwright

  run agentlinux install --yes
  [[ $status -eq 0 ]]

  run sudo -u agent -H bash --login -c 'claude --version'
  pre_version="$output"

  run sudo -u agent -H bash --login -c 'claude update'
  [[ $status -eq 0 ]]
  ! grep -q 'EACCES\|Permission denied' <<< "$output"

  run sudo -u agent -H bash --login -c 'claude --version'
  post_version="$output"

  printf '%s\n%s\n' "$pre_version" "$post_version" | sort -VC || fail "version monotonicity violated"

  # Transcript capture
  capture_transcript_to docs/audits/v0.3.4/AGT-02-brownfield-acceptance.md
}
```

**Test coverage expectations:**

Bats: 202 baseline → ~204 (+2 new: BHV-52 brownfield-AGT-02 gate, plus 1 additional smoke test for setup_brownfield_host_full helper validation)

Node:test: 165 baseline (no TS changes in Phase 16; pure docs + bats)

</specifics>

<deferred>
## Deferred Ideas

- **README quickstart section update**: the existing greenfield quickstart probably doesn't mention `--dry-run`. Adding it as a tip-callout is nice-to-have but not required by DOC-01. Defer to v0.3.5+ unless Phase 16 has bandwidth.
- **`docs/MIGRATION.md` translation**: not in scope; English-only for v0.3.4.
- **Video walkthrough of `--dry-run`**: out of scope.
- **CI artifact upload of `docs/audits/v0.3.4/AGT-02-brownfield-acceptance.md`**: the file is committed-on-run; whether CI uploads it as an artifact for cross-runner inspection is a separate concern; defer.
- **Per-platform AGT-02 brownfield gates**: today we run on Ubuntu 22.04 + 24.04 via Docker. Alma/Rocky brownfield AGT-02 is part of v0.3.5 (AL-47 anchored).
- **5th scenario (e.g., partially-installed catalog agent)**: spec locks 4 scenarios. Adding more is scope creep.

</deferred>
