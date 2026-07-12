# Roadmap

**Current milestone:** None — between milestones. v0.3.5 shipped 2026-07-11; start the next with `/gsd-new-milestone`.

## Milestones

- ✅ **v0.3.5 AlmaLinux 9 Support** — Phases 18–22 (SHIPPED 2026-07-11) — archived: [`milestones/v0.3.5-ROADMAP.md`](milestones/v0.3.5-ROADMAP.md)
- ✅ **v0.3.4 Aware Installation Process** — Phases 12–17 (SHIPPED 2026-06-08)
- ✅ **v0.4.0 Open-Source Release** — Phases 7–11 (feature-complete; formal closeout pending)
- ✅ **v0.3.3 Agenda Redefinition** — Phases 13–17 (shipped 2026-05-24)
- ✅ **v0.3.0 AgentLinux Plugin (Ubuntu)** — Phases 1–6 + 5.1 (shipped 2026-04-20)
- ⏏️ **v0.2.0 First Distro Image** — Phases 1–4 (retired 2026-04-18, pivot)
- ✅ **v0.1.0 Landing Page** (shipped 2026-03-10)

## Shipped / Feature-Complete Milestones

| Version | Name | Phases | Status | Archive |
|---------|------|--------|--------|---------|
| v0.3.5 | AlmaLinux 9 Support | 5 (Phase 18-22) | **SHIPPED 2026-07-11** (Docker ×4 incl. almalinux-9 + nightly-QEMU green) | [v0.3.5-ROADMAP.md](milestones/v0.3.5-ROADMAP.md) · [v0.3.5-REQUIREMENTS.md](milestones/v0.3.5-REQUIREMENTS.md) · phases archived under [milestones/v0.3.5-phases/](milestones/v0.3.5-phases/) |
| v0.3.4 | Aware Installation Process | 6 (Phase 12-17) | **SHIPPED 2026-06-08** (final v0.3.4, Latest; rc1→rc4 maintainer-validated) | [v0.3.4-ROADMAP.md](milestones/v0.3.4-ROADMAP.md) · [v0.3.4-REQUIREMENTS.md](milestones/v0.3.4-REQUIREMENTS.md) · [v0.3.4-MILESTONE-AUDIT.md](v0.3.4-MILESTONE-AUDIT.md) |
| v0.3.3 | Agenda Redefinition | 5 (Phase 13-17) | shipped 2026-05-24 (docs/vision/website) | [v0.3.3-ROADMAP.md](milestones/v0.3.3-ROADMAP.md) · [v0.3.3-REQUIREMENTS.md](milestones/v0.3.3-REQUIREMENTS.md) · phases archived under [milestones/v0.3.3-phases/](milestones/v0.3.3-phases/) |
| v0.4.0 | Open-Source Release | 5 (Phase 7-11) | feature-complete (formal closeout pending) | [v0.4.0-ROADMAP.md](milestones/v0.4.0-ROADMAP.md) · [v0.4.0-REQUIREMENTS.md](milestones/v0.4.0-REQUIREMENTS.md) |
| v0.3.0 | AgentLinux Plugin (Ubuntu) | 6 + 1 inserted (Phase 1-6, 5.1) | shipped 2026-04-20 | [v0.3.0-ROADMAP.md](milestones/v0.3.0-ROADMAP.md) · [v0.3.0-REQUIREMENTS.md](milestones/v0.3.0-REQUIREMENTS.md) |
| v0.2.0 | First Distro Image | 4 (Phase 1-4) | retired 2026-04-18 (pivot) | [v0.2.0-ROADMAP.md](milestones/v0.2.0-ROADMAP.md) · [v0.2.0-REQUIREMENTS.md](milestones/v0.2.0-REQUIREMENTS.md) |
| v0.1.0 | (initial) | — | — | [v0.1.0-ROADMAP.md](milestones/v0.1.0-ROADMAP.md) · [v0.1.0-REQUIREMENTS.md](milestones/v0.1.0-REQUIREMENTS.md) |

> **Phase-numbering note (parallel-milestone overlap).** v0.3.3 (Agenda Redefinition, phases **13–17**) and v0.3.4 (Aware Installation, phases **12–17**) were developed concurrently on separate branches and **reused phase numbers** — both number sets are frozen in immutable git commit prefixes (`feat(13-…)` etc.) on their respective lineages, so renumbering is not possible without rewriting shipped history. Reconciliation: v0.3.3's completed phase dirs are **archived** under `milestones/v0.3.3-phases/`, leaving the active `phases/` dir to v0.3.4's 12–17. One residual number reuse remains in the active dir — **phase 12** is both v0.3.4's `12-detection-layer` and v0.4.0's AL-22 addendum `12-developer-documentation-…`; both are completed and distinguished by dir-slug. This mirrors the project's existing cross-milestone number reuse (v0.2.0's archived 1–4 vs v0.3.0's 1–6). **v0.3.5 avoids the overlap entirely by continuing past the highest used integer — it starts at Phase 18.**
