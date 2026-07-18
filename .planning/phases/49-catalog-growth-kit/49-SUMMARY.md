# Phase 49: catalog growth kit — Summary

**Status:** ✓ COMPLETE (Docker 4/4 green, ubuntu-24.04) — 2026-07-14
**Requirements:** ENABLE-06, ENABLE-07
**Jira:** AL-96

## What shipped

**ENABLE-06 — `agentlinux list --by-category`:**
- `plugin/cli/src/catalog/category.ts` (NEW): `deriveCategory(entry)` maps an entry to one of
  a small fixed set of categories via a **tag-precedence** convention (first canonical tag
  wins; `workflow`/`token` precede `devops`; `coding-agent`/`browser` beat a bare `agent`),
  with `source_kind:"mcp"` as a fallback and "Other" as the catch-all — no entry is ever
  dropped. Categories: Coding agents · AI assistants · MCP servers · DevOps & security ·
  Token & workflow · Browser & automation.
- `list.ts`: added `category`/`category_label` to the JSON row (always) + a `--by-category`
  grouped text view (`## <label>` headers in display order, entries sorted by id). The **flat
  default is unchanged** — first line is still the `NAME/STATUS/…` header — so existing
  grep-the-table tooling and tests keep working. Rendering refactored into a shared
  `renderTable()`.
- `index.ts`: `--by-category` flag. `plugin/cli/test/category.test.ts` (NEW): derivation
  precedence + grouped render + JSON category.

**ENABLE-07 — catalog growth kit:**
- `docs/CATALOG-CONTRIBUTING.md` (NEW): the selection **rubric** (gates: agent-relevant ·
  clean per-user install · free · live · source integrity; then score), the **category-tag
  convention** (lockstep with `category.ts`), a step-by-step **add-an-entry** (copy template →
  add catalog entry → validate → bats → review), and the recipe rules.
- `plugin/catalog/agents/_template/{install,uninstall}.sh` (NEW): copy-and-fill recipe
  skeletons modeling the contract (env vars, shared-helper dispatch per source_kind,
  version-lock, CAT-04 `_should_remove` gate, idempotent symmetric remove). shellcheck-clean;
  the leading-underscore dir has no catalog entry so `validate-catalog` is unaffected (26 OK).

## Verification

`tests/bats/69-catalog-growth-kit.bats` (4 @tests, Docker 4/4 green):
- ENABLE-06: `list --by-category` renders every milestone category header in canonical order,
  every non-test entry appears (none dropped), hermes-agent lands under AI assistants.
- ENABLE-06 backward-compat: the flat default's first line is still the `NAME` header.
- ENABLE-07: template + rubric doc published, template recipes shellcheck-clean, doc category
  labels in lockstep.
- ENABLE-07 (CAT-03 proof): a **template-instantiated entry** (staged in a temp catalog via
  the `AGENTLINUX_CATALOG_DIR` seam) installs → marker at its pinned version → groups under
  its tag → removes — **with zero TypeScript edits**, proving the add-an-entry path.

## Milestone-close note (release gate)

Success criterion #4 (all 22 new entries install→verify→remove green across **Docker + QEMU**)
is the milestone **release gate**. Each entry was verified Docker-green as it shipped
(per-phase); the combined all-entries run + the **QEMU** gate + the milestone lifecycle
(audit → complete → cleanup → release tarball) are the maintainer/CI release step — QEMU is a
release-gate harness (fresh cloud images, systemd/logind) not runnable in the dev container.
The daemon phases (47/48) in particular gate their systemd-user lifecycle on QEMU (ADR-007).

## Review loop

9 reviewers (node-engineer, qa-engineer, behavior-coverage-auditor, catalog-auditor,
security-engineer, ai-deslop, technical-writer, fact-checker, external-audience-auditor).
[Findings + fixes recorded on commit.]
