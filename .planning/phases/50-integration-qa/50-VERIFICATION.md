# Phase 50 Verification

Status: complete — available-scope QA stop gate met after the F-007 observation;
credential/OAuth and systemd/QEMU boundaries remain explicitly blocked or excluded;
all findings are routed to Phase 51

## Acceptance checklist

- [x] Recovered Phase 50 specification is present in `ROADMAP.md` and
  `REQUIREMENTS.md` with TST-08 traceability.
- [x] `.claude/skills/qa-testing/SKILL.md` documents scoped direct/adjacent
  coverage, productive-time/latest-10 clean-by-novelty stopping, real PTY
  behavior, co-install order, credential blocking, and Docker/QEMU limits.
- [x] The skill is registered in `CLAUDE.md` and exposed through the Codex
  skill symlink.
- [x] The deterministic skill self-check passes.
- [x] Fresh Ubuntu 24.04 RC installation and catalog enumeration pass.
- [x] All 23 included catalog entries have recorded lifecycle/operation rows;
  openclaw and hermes-agent are explicitly excluded as requested, and
  test-dummy remains a fixture exclusion.
- [x] Real package operations, PTY behavior, co-install workflows, provider /
  consumer order, removal preservation, and targeted Ubuntu 22.04/26.04
  checks are recorded in the scenario ledger.
- [x] Three confirmed new user-visible findings, one unconfirmed observation,
  two known-issue reproductions, and two expected prerequisite blocks are
  recorded with durable evidence and proposed Phase 50.2–50.5 handoff
  destinations in `50-QA-REPORT.md`; no
  product source, recipe, or behavior-test fixes were made during this
  observation-only campaign.
- [x] Available-scope stop gate is met after the F-007 observation: the listed
  active intervals total 33 minutes 12 seconds and the ledger records 10
  distinct clean ideas; the observation, blocked ideas, and known-issue ideas
  remain excluded from the clean count, and F-006 remains the latest confirmed
  new finding.
- [x] Qwen's real prompt remains blocked pending the user's
  `OPENAI_BASE_URL` and `OPENAI_MODEL` values.
- [x] GitLab, Sentry, and in-client GitHub/Slack/Linear/Atlassian OAuth paths
  remain blocked because the required access is unavailable or requires
  interactive authorization.
- [x] QEMU systemd-user coverage is outside this Docker campaign and remains
  pending a systemd-capable environment.

The available-scope QA gate is complete. The blocked operations and QEMU-only
coverage are recorded as boundaries, never as clean results, and do not prevent
closing TST-08 because the phase contract explicitly permits honest blocked or
excluded coverage. The unified Phase 51 remediation phase is the durable
follow-up handoff for all findings, known issues, and prerequisite boundaries.
