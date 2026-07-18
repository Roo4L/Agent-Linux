# Phase 50 Verification

Status: partial — human follow-up required

## Acceptance checklist

- [x] Recovered Phase 50 specification is present in `ROADMAP.md` and
  `REQUIREMENTS.md` with TST-08 traceability.
- [x] `.claude/skills/qa-testing/SKILL.md` documents scoped direct/adjacent
  coverage, regression-to-zero rounds, real PTY behavior, co-install order,
  and Docker/QEMU limits.
- [x] The skill is registered in `CLAUDE.md` and exposed through the Codex
  skill symlink.
- [x] The deterministic skill self-check passes.
- [x] Fresh Ubuntu 24.04 RC installation and catalog enumeration pass.
- [x] GSD + Codex, MCP fan-out, RTK + npm agents, OpenClaw config, and sibling
  removal order were exercised.
- [x] The configured install-user dispatch defect and RTK stale-hook defect
  were fixed and covered by tests.
- [x] QA evidence and triage are recorded in `50-QA-REPORT.md`.
- [ ] Docker behavior suite is fully green: AGT-06 still lacks Chromium shared
  libraries.
- [ ] QEMU systemd-user coverage is pending because QEMU is unavailable here.
- [ ] Local CLI unit suite is fully green; one test file is host-path sensitive.
- [ ] Harness planning-source compatibility is restored for HRN-05.

The phase is intentionally not marked complete while release-gate and
environmental follow-ups remain open.
