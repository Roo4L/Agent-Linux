# 015: Agenda redefinition — two pillars, vision-only doc

**Status:** Accepted
**Date:** 2026-05-16
**Drives:** v0.3.3 VIS-09 (Phase 15)
**Companion to:** docs/VISION.md, docs/exploration/PILLAR-2-NOTES.md, docs/exploration/PILLAR-3-CANDIDATE-NOTES.md

## Status

Accepted (2026-05-16).

## Context

Jira epic [AL-7 — Project agenda redefinition](https://copiedwonder.atlassian.net/browse/AL-7) opened the v0.3.3 milestone with a single framing question: what is AgentLinux *about*, now that the v0.3.0 single-pillar story (a separated, correctly-owned agent environment) had shipped? Three framings competed during smart-discuss, and each one got in the way for a different reason.

The original single-pillar framing — "separated, correctly-owned agent environment" carried from v0.3.0 — was getting in the way positionally. It was too narrow to position the product against agent-environment competitors entering the same space, and it left no room in the story for the stability work the v0.3.0 reality already supported (curated catalog, compat-guarded version pinning per ADR-011, the TST-08 4-gate release pipeline). External contributors reading the README found a product whose framing was smaller than its delivered surface.

The original three-pillar bundle proposed by AL-7 (separated environment + stability/benchmarks + security hardening) was getting in the way once we explored it. Phase 14 (`docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` § Verdict) found no honest already-shipped table-stakes for security as a pillar — every candidate commitment (capability-scoped sudoers, cosign-signed catalog, npm provenance, bubblewrap sandbox, iptables egress allowlist) was forward-looking and would have forced aspirational drift per Pitfall #6. Phase 13 (`docs/exploration/PILLAR-2-NOTES.md` § Decision summary) consolidated stability + time-to-productive into a single pillar named by its optimization values, not by historical engineering vocabulary.

The original combined vision + strategy + roadmap + framework-trade-offs document (per the 2026-05-09 ROADMAP) was getting in the way at the document level. Vision-level identity claims and execution-level rules + roadmap themes serve different audiences and benefit from doc-level separation; mixing them invited drift on both axes. The framework-shape trade-offs (Sourcegraph template vs Lean Canvas vs Business Model Canvas vs PR-FAQ vs OKRs) added ceremony for no reader value.

## Decision

**Two pillars, named by optimization value.** Pillar 1 — Time-to-productive. Pillar 2 — Stability. Locked by Phase 14 verdict (b) (`docs/exploration/PILLAR-3-CANDIDATE-NOTES.md`: "Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3.") and Phase 13 Decision summary (`docs/exploration/PILLAR-2-NOTES.md`).

**Vision-only document at `docs/VISION.md`, separated from strategy/roadmap.** The strategy/roadmap content (execution principles, themes for v0.6+, near-term focus, current state) moves to `docs/STRATEGY.md`, authored in Phase 16. Locked by user reframe 2026-05-16 during `/gsd-discuss-phase`.

`docs/VISION.md` is the canonical "what we want to be" reference; `docs/STRATEGY.md` (Phase 16, forthcoming) will be the canonical "how we get there" companion. The vision doc carries the Pillar 2 sub-concern (active supply-chain monitoring + curated catalog admission) from Phase 14 verdict (b), and records the ADR-012 NOPASSWD tension inside Pillar 2's section as a known limitation rather than via an ADR-012 file edit (which closes DOC-05 as N/A in `15-AUDIT.md`).

## Considered alternatives

### Alternative 1 — Stay single-pillar

Rejected: AL-7 explicitly called for broadening. Continuing to ship as "separated, correctly-owned agent environment" alone left no room for the stability story (curated catalog, compat-guarded version pinning, ADR-011) that the v0.3.0 reality already supported. Single-pillar framing was the starting point AL-7 set out to leave behind.

### Alternative 2 — Ship vision + strategy + roadmap + framework trade-offs in one `docs/STRATEGY.md` (original Phase 15 plan)

Rejected: user reframe 2026-05-16 mid-`/gsd-discuss-phase`. Vision-level identity claims and execution-level rules serve different audiences (product leadership reading "what is AgentLinux" vs contributors and AI agents reading "how do we operate"); mixing them invited drift on both axes. The framework-shape trade-offs (Sourcegraph template vs Lean Canvas vs Business Model Canvas vs PR-FAQ vs OKRs) added ceremony for no reader value. Splitting the deliverable into VISION.md (Phase 15) and STRATEGY.md (Phase 16) costs one extra commit window but produces a sharper artifact at each path.

### Alternative 3 — Pivot security-first to a Pillar 3

Rejected: Phase 14 verdict (b) (`docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` § Verdict). No honest already-shipped table-stakes for security as a pillar — every candidate commitment (capability-scoped sudoers, cosign-signed catalog, npm provenance, bubblewrap sandbox, iptables egress allowlist) was forward-looking and would have forced aspirational drift per Pitfall #6 ("voice-rule discipline catches future-tense leaking into present-tense product claims"). The one honest forward commitment (active supply-chain monitoring + curated catalog admission) folds into Pillar 2 as a sub-concern; the rest stays as a v0.6+ `opportunistic` theme in the forthcoming `docs/STRATEGY.md`.

## Consequences

- **Phase 16 strategy/roadmap document inserted** at `docs/STRATEGY.md` (`.planning/phases/16-strategy-roadmap-doc/`). Hosts the execution principles + themes for v0.6+ + near-term focus content cut from Phase 15. Lands after Phase 15 closes so it can cite VISION.md as upstream "what."
- **Phase 16 → Phase 17 renumber.** The previously-numbered Phase 16 (website refresh at agentlinux.org) becomes Phase 17. Phase directories renamed in the same ROADMAP rewrite 2026-05-16.
- **DOC-05 closes N/A.** Phase 14 verdict (b) means there is no Pillar 3, so the original DOC-05 acceptance ("`docs/decisions/012-agent-user-full-sudo.md` gains a forward-reference to Pillar 3") is not applicable. The Phase 15 audit (`15-AUDIT.md`, Plan 15-02) records DOC-05 as N/A with a one-line rationale and cites EXPL-02's `## Verdict` line.
- **ADR-012 NOPASSWD tension recorded inside Pillar 2 of VISION.md**, not via an ADR-012 file edit. The unresolved trade-off (passwordless sudo for the agent user vs the future Pillar 2 supply-chain monitoring sub-concern) lives as a known limitation in the vision doc until a Security Hardening milestone resolves it.
- **Voice rule (PITFALLS.md) becomes a hard gate** at VIS-07 (Phase 15, on VISION.md), STRATR-06 (Phase 16, on STRATEGY.md), and SITE-06 (Phase 17, on rendered HTML). The grep is the spec; the command + output get committed verbatim to each phase's AUDIT file.
- **Cadence binding deferred.** The `/gsd-complete-milestone` template amendment that would update the VISION.md `> Last reviewed:` header (and a future STRATEGY.md equivalent) on every milestone close is flagged for the v0.3.3 retrospective, not in-milestone. Pitfall #12 / #23 mitigation.

## References

- [AL-7 — Project agenda redefinition](https://copiedwonder.atlassian.net/browse/AL-7) — Jira epic anchoring the milestone.
- [docs/VISION.md](../VISION.md) — the canonical vision document this ADR records the framing decision behind.
- [docs/exploration/PILLAR-2-NOTES.md](../exploration/PILLAR-2-NOTES.md) — Phase 13 verdict (EXPL-01), cited in Decision section above.
- [docs/exploration/PILLAR-3-CANDIDATE-NOTES.md](../exploration/PILLAR-3-CANDIDATE-NOTES.md) — Phase 14 verdict (b) (EXPL-02), cited as the pillar-count lock.
- [.planning/REQUIREMENTS.md](../../.planning/REQUIREMENTS.md) §"Superseded Items (2026-05-16 reframe)" — the requirement-ID delta from the reframe (STRAT-* → VIS-* + STRATR-*).
