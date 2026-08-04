---
phase: 7
phase_name: License & Public-Ready Documentation
milestone: v0.4.0
status: passed
gate: GREEN
date: 2026-04-26
---

# Phase 7 Audit — License & Public-Ready Documentation

## Coverage table

| Req | Description | Evidence | Status |
|-----|-------------|----------|--------|
| LIC-01 | LICENSE file at repo root with OSI-approved OSS license; license logged as ADR | `LICENSE` (21 lines, MIT text + copyright `Nikita Ivanov and AgentLinux contributors` + 2026 year) + `docs/decisions/013-license-mit.md` (Accepted, 2026-04-26) | ✓ |
| LIC-02 | README references license; license badge added; public-audience tone reviewed | `README.md` line 13 — shields.io license badge added to badge cluster; new `## License` section linking `LICENSE` and ADR-013; `## Contributing` section linking `CONTRIBUTING.md`; broken github.com/agentlinux/agent-linux URLs corrected to `Roo4L/Agent-Linux` (3 occurrences in test/release badges and Links section) | ✓ |
| LIC-03 | SPDX license identifier headers added to first-party source files; backfill policy in ADR | 16 first-party files now carry `# SPDX-License-Identifier: MIT` (or `// SPDX-License-Identifier: MIT` for TS): `plugin/bin/agentlinux-install`, `plugin/lib/{as_user,distro_detect,idempotency,log}.sh`, `plugin/provisioner/{10-agent-user,20-sudoers,30-nodejs,40-path-wiring,50-registry-cli}.sh`, `scripts/build-release.sh`, `packaging/curl-installer/install.sh`, `tests/harness/run.sh`, `plugin/cli/src/{index,runner,types}.ts`. Backfill policy + new-file convention recorded in ADR-013 §"SPDX header policy" | ✓ |
| LIC-04 | CONTRIBUTING.md exists at repo root, links docs/HARNESS.md, explains issue/PR process and review-loop conventions | `CONTRIBUTING.md` (101 lines) — quick start, behavior-test contract, review loop, conventions (no sudo npm install -g, no default agents, no /usr/local/bin shims, pre-commit must stay green), license & contributor agreement (MIT affirmation by PR submission), security reporting note | ✓ |

## Files added/changed

| Path | Change | Notes |
|------|--------|-------|
| `LICENSE` | NEW | 21 lines, MIT license text |
| `docs/decisions/013-license-mit.md` | NEW | 78 lines, Accepted ADR with patent/copyleft/trademark/reversibility analysis |
| `CONTRIBUTING.md` | NEW | 101 lines, quick start + behavior-test contract + DCO-equivalent affirmation |
| `README.md` | MODIFIED | License badge, License section, Contributing section, github.com URL fix (`agentlinux/agent-linux` → `Roo4L/Agent-Linux`, 3 occurrences) |
| `plugin/bin/agentlinux-install` | MODIFIED | + SPDX line |
| `plugin/lib/{as_user,distro_detect,idempotency,log}.sh` | MODIFIED | + SPDX line (4 files) |
| `plugin/provisioner/{10-agent-user,20-sudoers,30-nodejs,40-path-wiring,50-registry-cli}.sh` | MODIFIED | + SPDX line (5 files) |
| `scripts/build-release.sh` | MODIFIED | + SPDX line |
| `packaging/curl-installer/install.sh` | MODIFIED | + SPDX line |
| `tests/harness/run.sh` | MODIFIED | + SPDX line |
| `plugin/cli/src/{index,runner,types}.ts` | MODIFIED | + SPDX line (3 files) |

## Coverage verification

```bash
grep -rln "SPDX-License-Identifier" plugin/ scripts/ packaging/ tests/harness/ | wc -l
# Expected: 16 (matches the file list above)
```

Output: 16 ✓

```bash
test -f LICENSE && echo "LICENSE present"
# Expected: "LICENSE present"
```

```bash
grep -F "MIT" LICENSE | head -1
# Expected: "MIT License"
```

```bash
grep -F "## License" README.md
# Expected: matches the new section heading
```

```bash
test -f CONTRIBUTING.md && echo "CONTRIBUTING.md present"
# Expected: "CONTRIBUTING.md present"
```

```bash
test -f docs/decisions/013-license-mit.md && echo "ADR-013 present"
# Expected: "ADR-013 present"
```

## Deviations from PLAN

- **No PLAN.md was authored.** Phase 7 was executed directly under `/gsd-autonomous` continuation from the milestone planning commit (6554fdf). The phase content was deterministic enough (license pick already recommended in REQUIREMENTS.md, ADR template in `docs/decisions/000-template.md`, source file inventory readable via `ls`) that the discuss → plan → execute ceremony would have produced the same artifacts at higher token cost. The autonomous workflow's `gsd-sdk query` machinery was not fully available in the Multica agent environment (`roadmap.analyze` returned "Unknown command"), forcing the inline-execution path. This is a documented deviation, not a regression — the same outputs land.
- **Existing-file SPDX backfill applied in this phase, not deferred.** ADR-013 §"SPDX header policy" allows for backfill in the same Phase 7 commit; we applied it. The ~16 first-party source files affected are the high-traffic surface; a future contributor can add identifiers to additional files organically as they touch them.
- **Trademark posture** flagged in ADR-013 with a one-line README clarification ("forks should pick their own name to avoid implying maintainer endorsement"). Full trademark ADR deferred — there are no forks today.

## Phase-close gate

GATE: GREEN — all 4 LIC-XX requirements have at least one cited evidence artifact (file path, line number, or grep output). No blocking findings.

## Hand-off to Phase 8

Phase 8 (Secret Scanning & History Audit) is the next phase. It runs gitleaks + trufflehog over full history and the targeted manual audit (Buttondown / GitHub / Anthropic / npm credentials, `.env`/`.npmrc`/`.git-credentials` artifacts). Phase 8 is the hard blocker for the visibility flip — Phase 7's licensing work is necessary but not sufficient for Phase 11.
