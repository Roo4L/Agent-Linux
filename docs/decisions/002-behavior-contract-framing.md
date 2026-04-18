# 002: Behavior-contract framing — requirements are BHV-XX, not INST-XX; tests are the spec

**Status:** Accepted
**Date:** 2026-04-18

## Context

Earlier drafts framed requirements as implementation steps ("installer shall run
apt-get", "provisioner shall write `/etc/sudoers.d/agent`"). This pins the
implementation and prevents refactoring without rewriting the spec. The
AgentLinux bug class is about observable behavior (agent user can `npm install -g`
without sudo, Claude Code self-updates without EACCES) — not about which bash
script or package manager runs when.

## Decision

Express requirements as observable behaviors (BHV-XX / RT-XX / AGT-XX / CLI-XX /
CAT-XX / INST-XX) that a bats test suite can assert against a running installed
system. The bats suite in `tests/bats/` is the spec; implementation in `plugin/`
may change freely while the suite stays green.

## Consequences

- Each requirement maps to ≥1 bats test (enforced by the `behavior-coverage-auditor`
  review subagent at every phase transition).
- Implementation choices (curl vs apt, sudo vs no-sudo, npm vs native) are not
  requirements — they are free variables bounded only by the behavior contract.
- Test-authoring convention and helpers (`assert_agent_can_run`,
  `assert_no_eacces_in_log`) are codified in the `behavior-test-contract` skill.
