---
status: complete
quick_id: 260510-n7e
date: 2026-05-10
ticket: AL-33
tags: [docs, claude-md, review-loop, external-audience]
---

# 260510-n7e: Remove GSD artifacts from help and project documentation

Two-task quick scrub: strip internal-vocabulary leaks from externally-facing
artifacts (Task 1), then wire the existing `external-audience-auditor` agent
into the project review-loop dispatch table so future regressions are caught
automatically (Task 2).

## Commits

| Task | Commit    | Title                                                              |
| ---- | --------- | ------------------------------------------------------------------ |
| 1    | `a161cf6` | chore(docs): scrub internal-vocabulary leaks from user-facing surfaces (AL-33) |
| 2    | `bb8f02f` | chore(claude): wire external-audience-auditor into review-loop dispatch (AL-33) |

## Task 1 — files modified

- `README.md` — drop `AGT-02` token; drop `.planning/REQUIREMENTS.md` link;
  contextualize bare `ADR-006` reference with the named decision-record link.
- `CONTRIBUTING.md` — drop `BHV/RT/AGT/CLI/CAT/INST/HRN/TST/DOC-XX` requirement
  ID list from the PR-guidance step; rephrase "cites the relevant requirement
  ID" to "names the behavior it pins".
- `docs/STABILITY-MODEL.md` — replace bare `ADR-011` TL;DR token with a
  one-breath substance + decision-record link; drop `AGT-02`, `TST-08`,
  `Phase 6`, `ADR-012` tokens; clean up bare `ADR-NNN` prefixes in the Related
  list (the link text already carries the substance).
- `docs/README.md` — drop "GSD workflow state" lede phrasing (internal harness
  vocabulary); drop "ADR-001..ADR-010 seeded in Phase 1" sentence; rephrase
  HARNESS.md section descriptors from §-numbers to plain prose.
- `docs/internals/playwright.md` — contextualize bare `ADR-012` reference with
  a named decision-record link.
- `plugin/cli/src/index.ts` — drop `(CLI-06)` from `agentlinux upgrade` and
  `(CLI-07)` from `agentlinux pin` Commander descriptions (these surface in
  user-visible `--help` output).

## Task 2 — files modified

- `CLAUDE.md` — added a new dispatch row to "Review Loop" §"Reviewers applied
  by file type" for externally-facing artifacts (top-level README,
  CONTRIBUTING, docs/internals/, docs/HARNESS.md, docs/STABILITY-MODEL.md,
  docs/README.md, public release notes, blog/email drafts, agentlinux.org
  copy, user-visible packaging strings) → also `external-audience-auditor`,
  in addition to the per-file-type reviewers above. Skip-list documented
  inline (`.planning/`, `docs/decisions/`, `docs/audits/`, `docs/research/`,
  `.claude/`, source under `plugin/`/`packaging/`/`tests/`).

## Leak categories found and substitutions applied

1. **Bare requirement IDs** (`AGT-02`, `TST-08`, `CLI-06`, `CLI-07`, the
   `BHV/RT/AGT/CLI/CAT/INST/HRN/TST/DOC-XX` enumeration). Substitute: drop the
   token and restate the behavior in prose ("the self-update-without-sudo
   invariant"; "the release-gate test"; "Reconcile installed versions against
   the curated catalog").
2. **Bare ADR cross-references** (`ADR-006`, `ADR-011`, `ADR-012`).
   Substitute: cite both the substance and the decision-record file in one
   breath, or replace with a named link without the numeric prefix.
3. **GSD harness vocabulary** ("`.planning/` holds GSD workflow state").
   Substitute: drop the GSD-flavoring; describe the directory's purpose
   neutrally.
4. **Phase numbering** (`Phase 1`, `Phase 6`). Substitute: drop the label;
   keep the substance ("the release-gate test").
5. **Internal workspace paths** in user-facing prose
   (`.planning/REQUIREMENTS.md` link from README). Substitute: delete — the
   internal contract is not a user-facing surface.

## Kept on purpose

- Catalog agent name `gsd` and the npm package `get-shit-done-cc` — these are
  the public installable identifiers users type at the CLI.
- "GSD workflow CLI for Claude Code" inside catalog example output and the
  catalog.json description string — that's the user-visible product
  description that ships in the catalog.
- Source-comment references inside `plugin/`, `packaging/`, `tests/` —
  out of scope per the external-audience-auditor (only user-visible *strings*
  under packaging/ are audited, not source comments).
- ADR cross-references inside `docs/decisions/` — internal-only by audit
  scope (ADR-to-ADR cross-refs are appropriate within the decision tree).
- `Co-Authored-By: Claude Opus 4.7 ...` in commit messages — project
  convention, and commit messages are not user-visible per the plan's scope
  partition (the auditor flags this trailer only in user-visible artifacts
  like blog posts or website copy).

## Out-of-scope deferrals

- `docs/HARNESS.md` is referenced from README.md and matches the auditor's
  externally-facing scope, but it is primarily contributor-harness
  documentation written for people coming into the workspace. Its full
  internal-vocabulary load (Phase numbering, ADR-NN cross-refs, requirement
  ID enumeration) is structurally part of what the document explains. A
  separate quick task is the right vehicle for that scrub; conflating it
  here would have made this commit too large to review cleanly.
- Source comments in `plugin/`, `packaging/`, `tests/` carry phase/plan/req
  vocabulary heavily. These are explicitly out of audit scope per the
  `external-audience-auditor` Rule 1 ("Audit only externally-facing
  artifacts").

## Reviewer findings

The Task tool for spawning subagents was not available in this executor
environment, so the review loop was performed inline against each reviewer's
lens. All concerns either passed or are documented as out-of-scope above.

- **node-engineer** (plugin/cli/src/index.ts): help-text-only edit; no API,
  parsing, or behavior change. PASS.
- **security-engineer** (plugin/cli/src/index.ts): no impact on `preAction`
  EUID guard or input validation. PASS.
- **qa-engineer**: verified no bats test asserts the literal `(CLI-06)` or
  `(CLI-07)` substring against `--help` output (test descriptions name the
  IDs for traceability, but bodies assert behavior — exit codes, sentinel
  state, presence of agent name in upgrade table). PASS.
- **ai-deslop**: substitutions are tighter than originals; word count went
  down. PASS.
- **dev-docs-auditor**: index.ts change is help-text only — no behavior
  change, so docs/internals/registry-cli.md does not need updating. PASS.
- **technical-writer**: each substitution preserves the original sentence's
  meaning while removing unresolvable IDs. The CONTRIBUTING.md substitution
  is *more* actionable for external contributors. PASS.
- **fact-checker**: substantive claims unchanged. "Release-gate test",
  "curated-combo", "agent user's NOPASSWD sudo drop-in" all factually
  accurate. PASS.
- **external-audience-auditor** (sanity check): re-ran the leak grep on the
  post-fix tree against the in-scope file set. Zero hard-fail matches. PASS.

## Verification

Final grep against the in-scope externally-facing files for the canonical
hard-fail leak taxonomy:

```
grep -E '(AL-[0-9]+|\.planning/|BHV-[0-9]+|RT-[0-9]+|AGT-[0-9]+|CLI-[0-9]+|CAT-[0-9]+|INST-[0-9]+|HRN-[0-9]+|TST-[0-9]+|DOC-[0-9]+|gsd-executor|gsd-planner|gsd-sdk|smart discuss|the orchestrator|the executor|the planner|Plan [0-9]+-[0-9]+|\bPhase [0-9]+\b|ADR-[0-9]+)' \
  README.md CONTRIBUTING.md docs/internals/*.md docs/STABILITY-MODEL.md docs/README.md
# → 0 matches
```

The user-visible Commander help-text scan also confirms `(CLI-06)` and
`(CLI-07)` no longer appear in `agentlinux upgrade --help` or
`agentlinux pin --help` output.

## Self-Check: PASSED

- Task 1 commit `a161cf6` exists in `git log`. FOUND.
- Task 2 commit `bb8f02f` exists in `git log`. FOUND.
- All 7 modified files in Task 1 are tracked at the new content. FOUND.
- CLAUDE.md has the new dispatch row at line 60+. FOUND.
- Verify-block grep returns zero hard-fail matches. CONFIRMED.
