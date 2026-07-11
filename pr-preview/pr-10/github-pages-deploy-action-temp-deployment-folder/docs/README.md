# AgentLinux Documentation

This directory holds all reference documentation. `.planning/` holds GSD workflow
state (plans, STATE.md, config) — not documentation. If the output of a task is
a document intended to be read later (ADR, research report, design proposal,
review summary), it goes here.

## Layout

- `HARNESS.md` — authoritative project harness spec (§1 layout, §2 docs,
  §3 systems access, §4 review loop, §5 skills, §6 CLAUDE.md, §7 checklist,
  §8 success criteria).
- `decisions/` — Architecture Decision Records (ADRs). ADR-001..ADR-010 seeded
  in Phase 1 per `HARNESS.md` §2.3. New ADRs land as decisions resolve.
- `research/v0.3.0/` — v0.3.0 research outputs (STACK, FEATURES, ARCHITECTURE,
  PITFALLS, SUMMARY).
- `research/v0.2.0/` — archived v0.2.0 research (carry-forward reference).
- `proposals/` — design proposals pre-ADR.
- `analysis/` — gap analyses, comparison studies.
- `reviews/` — review-loop outputs worth preserving across sessions.
