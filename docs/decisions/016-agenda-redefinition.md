# 016: Agenda redefinition — two pillars, vision-only doc

**Status:** Accepted
**Date:** 2026-05-16
**Tracked as:** [AL-7 — Project agenda redefinition](https://copiedwonder.atlassian.net/browse/AL-7)
**Companion to:** `docs/VISION.md`, `docs/exploration/PILLAR-2-NOTES.md`, `docs/exploration/PILLAR-3-CANDIDATE-NOTES.md`

## Context

[AL-7](https://copiedwonder.atlassian.net/browse/AL-7) opened the v0.3.3 cycle with a single framing question: what is AgentLinux *about*, now that the v0.3.0 story — a separated, correctly-owned agent environment — had shipped? Three framings competed, and each got in the way for a different reason.

The original single-pillar framing carried from v0.3.0 was getting in the way positionally. It was too narrow to position the product against the agent-environment competitors entering the same space, and it left no room in the story for the stability work v0.3.0 already supported: a curated catalog, compat-guarded version pinning (ADR-011), and a four-gate release pipeline. External contributors reading the README found a product whose framing was smaller than its delivered surface.

The three-pillar bundle AL-7 originally proposed — separated environment, stability/benchmarks, and security hardening — got in the way once explored. The security-pillar exploration (`docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` § Verdict) found no honest already-shipped table stakes for security as a pillar: every candidate commitment (capability-scoped sudoers, cosign-signed catalog, npm provenance, bubblewrap sandbox, iptables egress allowlist) was forward-looking, and claiming them would have made the product's voice aspirational rather than descriptive. The stability exploration (`docs/exploration/PILLAR-2-NOTES.md` § Decision summary) consolidated stability and time-to-productive into a single pillar named by its optimization values rather than by historical engineering vocabulary.

The originally-planned combined vision + strategy + roadmap + framework-trade-offs document got in the way at the document level. Vision-level identity claims and execution-level rules serve different audiences and benefit from separation; mixing them invited drift on both axes. The framework-shape trade-offs (Sourcegraph template vs Lean Canvas vs Business Model Canvas vs PR-FAQ vs OKRs) added ceremony for no reader value.

## Decision

**Two pillars, named by optimization value.** Pillar 1 — Time-to-productive. Pillar 2 — Stability. Locked by the security-pillar verdict (`docs/exploration/PILLAR-3-CANDIDATE-NOTES.md`: *"Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3."*) and the stability decision summary (`docs/exploration/PILLAR-2-NOTES.md`).

**A vision-only document at `docs/VISION.md`, separated from strategy and roadmap.** The execution content — principles, longer-range themes, near-term focus, current state — moves to `docs/STRATEGY.md`.

`docs/VISION.md` is the canonical "what we want to be" reference; `docs/STRATEGY.md` is the canonical "how we get there" companion. The vision doc carries Pillar 2's forward sub-concern (active supply-chain monitoring plus curated catalog admission), and records the ADR-012 passwordless-sudo tension inside Pillar 2's section as a known limitation rather than by editing ADR-012.

## Considered alternatives

### Alternative 1 — Stay single-pillar

Rejected: AL-7 explicitly called for broadening. Shipping as "separated, correctly-owned agent environment" alone left no room for the stability story — curated catalog, compat-guarded version pinning (ADR-011) — that v0.3.0 already supported. Single-pillar framing was the starting point AL-7 set out to leave behind.

### Alternative 2 — Ship vision, strategy, roadmap, and framework trade-offs in one document

Rejected. Vision-level identity claims and execution-level rules serve different audiences: product leadership reading "what is AgentLinux" versus contributors and coding agents reading "how do we operate." Mixing them invited drift on both axes. The framework-shape trade-offs added ceremony for no reader value. Splitting into `VISION.md` and `STRATEGY.md` costs one extra commit window but produces a sharper artifact on each path.

### Alternative 3 — Pivot security-first to a third pillar

Rejected on the security-pillar verdict (`docs/exploration/PILLAR-3-CANDIDATE-NOTES.md` § Verdict). No honest already-shipped table stakes existed for security as a pillar — every candidate commitment was forward-looking, and claiming them would have leaked future tense into present-tense product claims. The one honest forward commitment (active supply-chain monitoring plus curated catalog admission) folds into Pillar 2 as a sub-concern; the rest remains an opportunistic longer-range theme in `docs/STRATEGY.md`.

## Consequences

- **`docs/STRATEGY.md` is a separate deliverable**, hosting the execution principles, longer-range themes, and near-term focus cut from the vision doc. It lands after `VISION.md` so it can cite it as the upstream "what."
- **The ADR-012 passwordless-sudo tension is recorded inside Pillar 2 of `VISION.md`**, not by editing ADR-012. The unresolved trade-off — passwordless sudo for the agent user versus Pillar 2's future supply-chain monitoring — lives as a known limitation in the vision doc until a security-hardening cycle resolves it.
- **The voice rule becomes a hard gate** on `VISION.md`, `STRATEGY.md`, and the rendered site copy: no future-tense commitment may be written as a present-tense product claim. The grep is the spec, and its output is committed as the evidence.
- **Keeping the vision doc's review date current is deferred**, and flagged for the next retrospective rather than solved here.

## References

- [AL-7 — Project agenda redefinition](https://copiedwonder.atlassian.net/browse/AL-7) — the Jira epic this decision closes.
- [docs/VISION.md](../VISION.md) — the vision document whose framing this ADR records.
- [docs/exploration/PILLAR-2-NOTES.md](../exploration/PILLAR-2-NOTES.md) — the stability-pillar verdict cited in the Decision section.
- [docs/exploration/PILLAR-3-CANDIDATE-NOTES.md](../exploration/PILLAR-3-CANDIDATE-NOTES.md) — the security-pillar verdict, cited as the pillar-count lock.
