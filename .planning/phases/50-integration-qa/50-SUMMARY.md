# Phase 50 Summary

**Status:** Complete (2026-07-19). The available-scope QA gate was met, all
residual blocked/excluded paths are documented honestly, and the findings and
known/boundary issues are routed to unified Phase 51 remediation.

Phase 50 restored the lost integration-QA specification and executed an
observation-only black-box campaign against all 23 included catalog entries.
The campaign used a fresh Ubuntu 24.04 release-candidate container plus
targeted Ubuntu 22.04 and 26.04 checks, realistic package operations, PTY
checks, co-install workflows, provider/consumer ordering, and removal
preservation checks.

The earlier F-006 stop claim was invalidated by a saved Gemini run that was
mistakenly classified clean despite a visible invalid-stream error. Three
confirmed new findings, one unconfirmed Gemini observation, two known-issue
reproductions, and two expected prerequisite blocks are now recorded:
Firecrawl's keyless live behavior, OpenCode GitHub MCP OAuth compatibility, and
Playwright's zero exit status for invalid targets; Gemini's invalid stream
observation; the documented Spec Kit `git` prerequisite and Chrome prerequisite;
and the known Playwright browser-library and GSD/Codex configuration issues.
The expected prerequisite blocks and known issues were neither new nor clean.
The Gemini observation was not reproduced in two later authorized retries and
did not reset the gate. The available-scope stop gate was re-earned
after the observation with 33 minutes 12 seconds of listed productive activity
and 10 distinct clean ideas.
No product fixes were made during this observation-only phase. Findings,
known issues, and prerequisite boundaries are routed to the approved unified
Phase 51 remediation phase.

Qwen's real prompt is paused until `OPENAI_BASE_URL` and `OPENAI_MODEL` are
provided. GitLab, Sentry, and in-client GitHub/Slack/Linear/Atlassian OAuth
operations are also explicitly blocked, while openclaw and hermes-agent are
excluded because Docker lacks their required systemd services. See
`50-QA-REPORT.md`, `50-SCENARIO-LEDGER.md`, and `50-VERIFICATION.md` for the
evidence and exact residual scope.
