# Roadmap

**Current milestone:** v0.3.4 Aware Installation Process — **shipping** (Phase 17: delivery → release candidate → maintainer validation → final release)

## Active Phase

### Phase 17: Changes Delivery and Release Candidate

**Goal:** Ship the feature-complete v0.3.4 "Aware Installation Process" to a maintainer-testable release candidate and gate the final release on live brownfield review. Polish the worktree branch diff (tests green, commit hygiene), merge to master, cut `v0.3.4-rc1` (tarball + sibling `.sha256` via `scripts/build-release.sh`; push the rc tag to exercise `release.yml` end-to-end — the shipping event), hand the maintainer concrete live-test instructions for his real brownfield VM (non-mutating `agentlinux-install --dry-run` preview + the fail-safe no-`--yes` bail, then the real `--yes` install + `claude update` AGT-02 check, with snapshot/rollback guidance), then await maintainer feedback as an explicit checkpoint. Decision gate: positive feedback → promote rc to final v0.3.4 (close AL-38; transition the 5 phase subtasks AL-41/44/55/56/57 to Done); negative feedback → capture it and spin improvement/bugfix plans before re-cutting.

**Requirements:** Delivery gate — no new behavior requirements (BHV/RT/AGT/CLI/CAT/INST). Re-exercises the existing AGT-02 acceptance (zero-EACCES `claude update`) on the maintainer's real brownfield VM rather than a fixture. Sub-goals: DEL-01 branch polish + merge to master · DEL-02 `v0.3.4-rc1` build (tarball + `.sha256`) + tag push (release.yml green) · DEL-03 maintainer live-test runbook · DEL-04 feedback checkpoint · DEL-05 promote-or-iterate gate.

**Depends on:** Phase 16 (v0.3.4 feature-complete, GATE: GREEN)
**Anchor:** [AL-38](https://copiedwonder.atlassian.net/browse/AL-38) — file a Phase 17 subtask on plan; this is the maintainer-validation gate referenced at milestone close.

**Plans:** 3 plans (3 waves — strict delivery ordering with 2 human checkpoints)

Plans:
- [ ] 17-01-PLAN.md — DEL-02a + DEL-01: lockstep version bump 0.3.2→0.3.4 + merge-integrate origin/master + full suite green (autonomous)
- [ ] 17-02-PLAN.md — DEL-01b/DEL-02b/DEL-03/DEL-04: push branch + open PR → [HUMAN: merge PR] → push v0.3.4-rc1 tag + watch release → write brownfield-VM runbook → [HUMAN: VM validation] (orchestrator-supervised)
- [ ] 17-03-PLAN.md — DEL-05: promote-or-iterate decision record + [HUMAN: decision gate] (describe-only; no autonomous promote/close)

## Shipped / Feature-Complete Milestones

| Version | Name | Phases | Status | Archive |
|---------|------|--------|--------|---------|
| v0.3.4 | Aware Installation Process | 5 (Phase 12-16) | feature-complete 2026-05-27 · **shipping via Phase 17** | [v0.3.4-ROADMAP.md](milestones/v0.3.4-ROADMAP.md) · [v0.3.4-REQUIREMENTS.md](milestones/v0.3.4-REQUIREMENTS.md) · [v0.3.4-MILESTONE-AUDIT.md](v0.3.4-MILESTONE-AUDIT.md) |
| v0.3.3 | Agenda Redefinition | 5 (Phase 13-17) | shipped 2026-05-24 (docs/vision/website) | [v0.3.3-ROADMAP.md](milestones/v0.3.3-ROADMAP.md) · [v0.3.3-REQUIREMENTS.md](milestones/v0.3.3-REQUIREMENTS.md) · phases archived under [milestones/v0.3.3-phases/](milestones/v0.3.3-phases/) |
| v0.4.0 | Open-Source Release | 5 (Phase 7-11) | feature-complete (formal closeout pending) | [v0.4.0-ROADMAP.md](milestones/v0.4.0-ROADMAP.md) · [v0.4.0-REQUIREMENTS.md](milestones/v0.4.0-REQUIREMENTS.md) |
| v0.3.0 | AgentLinux Plugin (Ubuntu) | 6 + 1 inserted (Phase 1-6, 5.1) | shipped 2026-04-20 | [v0.3.0-ROADMAP.md](milestones/v0.3.0-ROADMAP.md) · [v0.3.0-REQUIREMENTS.md](milestones/v0.3.0-REQUIREMENTS.md) |
| v0.2.0 | First Distro Image | 4 (Phase 1-4) | retired 2026-04-18 (pivot) | [v0.2.0-ROADMAP.md](milestones/v0.2.0-ROADMAP.md) · [v0.2.0-REQUIREMENTS.md](milestones/v0.2.0-REQUIREMENTS.md) |
| v0.1.0 | (initial) | — | — | [v0.1.0-ROADMAP.md](milestones/v0.1.0-ROADMAP.md) · [v0.1.0-REQUIREMENTS.md](milestones/v0.1.0-REQUIREMENTS.md) |

> **Phase-numbering note (parallel-milestone overlap).** v0.3.3 (Agenda Redefinition, phases **13–17**) and v0.3.4 (Aware Installation, phases **12–17**) were developed concurrently on separate branches and **reused phase numbers** — both number sets are frozen in immutable git commit prefixes (`feat(13-…)` etc.) on their respective lineages, so renumbering is not possible without rewriting shipped history. Reconciliation: v0.3.3's completed phase dirs are **archived** under `milestones/v0.3.3-phases/`, leaving the active `phases/` dir to v0.3.4's 12–17. One residual number reuse remains in the active dir — **phase 12** is both v0.3.4's `12-detection-layer` and v0.4.0's AL-22 addendum `12-developer-documentation-…`; both are completed and distinguished by dir-slug. This mirrors the project's existing cross-milestone number reuse (v0.2.0's archived 1–4 vs v0.3.0's 1–6).

## Next Milestone Candidates

- **v0.3.5 AlmaLinux support** — port the aware-install pipeline (Phase 12-15 detection + REUSE/REMEDIATE) to AlmaLinux 9. Anchored under [AL-47](https://copiedwonder.atlassian.net/browse/AL-47) (grouped with AL-38 under Epic AL-48 — maintainer-VM daily-driver readiness).

Run `/gsd-new-milestone` to scope the next milestone (after v0.3.4 ships via Phase 17).
