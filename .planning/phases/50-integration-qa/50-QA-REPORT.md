# Phase 50 Integration QA Report

Date: 2026-07-18
Status: partial — human follow-up required

## Scope

This sweep exercised the restored Phase 50 contract against the current
catalog-expanded tree. The disposable install used Ubuntu 24.04, the real
curl-pipe-bash installer, the staged release artifact `v0.3.5-qa1`, and the
agent-owned install user. The selected combinations were:

- GSD + Codex, followed by Claude Code installation.
- GitHub MCP before and after the second coding agent, verifying fan-out and
  removal without credential material.
- RTK binary + npm-installed coding agents, including reverse-trigger wiring.
- RTK cleanup across Gemini CLI and OpenCode, including consumer-before-provider removal.
- OpenClaw npm/daemon-class installation, with the Docker systemd limitation
  recorded explicitly.
- Provider/consumer removal order: Codex removed before RTK.

The sweep used direct scope for the restored skill and adjacent scope for
installer, catalog, CLI, wiring, and harness interactions. The bounded session
used two quiet rounds after fixes; each repeated the skill self-check, shell
syntax check, and diff check with no new finding.

## Results

| Surface | Result | Evidence |
| --- | --- | --- |
| Reusable QA skill | PASS | `verify-skill.sh` passed in both quiet rounds; registered in `CLAUDE.md` and `.codex/skills/qa-testing`. |
| Real PTY | PASS | `tests/bats/helpers/tty-driver.py` reported `pty-columns=80`, `TERM=xterm-256color`, and live ANSI output. |
| CLI unit tests | 201/202 pass | One file-level failure is caused by the host's existing `/home/agent/.local/bin/claude`, which invalidates a fixture's clean-host assumption. |
| Harness meta-tests | 112/113 pass | Pre-commit smoke passed. The remaining failure is the legacy `.planning/research/SUMMARY.md` path expected by HRN-05. |
| Docker behavior suite | 336/337 pass | Latest `bash tests/docker/run.sh ubuntu-24.04`; AGT-06 is the only failure, and WIRE-02 tests 334–337 all pass. |
| Fresh RC install | PASS | SHA256 verification, extraction, provisioning, CLI staging, and 25-entry catalog sanity check passed. |
| GSD + Codex | PASS | Both version checks passed; GSD wired Claude/OpenCode/Gemini/Qwen and deliberately left Codex config loadable. |
| MCP fan-out | PASS | GitHub MCP registered in Codex, then Claude after Claude installation; removal left no registration residue. |
| RTK ordering | PASS after fix | Removing Codex before RTK now removes the preserved Codex RTK hook. |
| RTK Gemini/OpenCode ordering | PASS after fix | Fresh RC sandbox preserved both consumer artifacts after agent removal, then RTK removed both. |
| Binary + npm + daemon | PASS within Docker limits | RTK and OpenClaw installed in agent-owned paths; OpenClaw config froze updates and preserved state. |
| QEMU/systemd-user | NOT RUN | `qemu-system-x86_64` is not installed in this environment. |

## Findings and disposition

### Fixed in this phase

1. `plugin/cli/src/runner.ts` dispatched every recipe as `agent`, ignoring the
   configured install user. The dispatcher now uses the resolved user. The
   configured-user behavior test passed in the full Docker suite.
2. `plugin/catalog/lib/rtk-wire.sh` only unwired targets whose agent binary was
   still present. Removing a consumer first therefore left RTK-owned files in
   the preserved consumer config. Unwire now also recognizes RTK-owned Codex,
   Gemini CLI, and OpenCode artifacts; the WIRE-02 behavior test covers the
   ordering contract, and the disposable RC sandbox confirms the Gemini/OpenCode
   path against the rebuilt release artifact.

### Open follow-ups

1. AGT-06 remains red in the Docker suite: Playwright Chromium reports missing
   shared libraries (`libglib-2.0.so.0`, `libnss3.so`, X11/GTK/ALSA-related
   libraries, and others). This is a release-gate environment/package issue,
   not a Phase 50 harness false positive.
2. The host-only `plugin/cli/test/install.test.ts` brownfield fixture is not
   isolated from a real `/home/agent/.local/bin/claude`. Run it in a clean
   environment or make the canonical-path probe injectable before calling the
   local unit suite green.
3. Re-running the installed RC over a populated sandbox registered a GSD
   path-mismatch bail and exited 65 without remediation consent. This is an
   adjacent rerun/convergence issue and needs a deliberate installer decision.
4. The harness still expects the pre-archive `.planning/research/SUMMARY.md`
   location, while the durable copy now lives under
   `.planning/milestones/v0.3.0-research/SUMMARY.md`.
5. Docker correctly skipped OpenClaw's per-user systemd daemon; QEMU is still
   required for the daemon liveness and real systemd-user acceptance criteria.

## Coverage limits

The Docker run covered the six invocation modes and full catalog behavior, but
it cannot prove per-user systemd services. No provider credentials were used,
so model-backed creative/interactive agent prompts remain out of scope. The
QEMU release-gate sweep, Chromium shared-library remediation, and the legacy
planning-source path are the remaining human follow-up items.
