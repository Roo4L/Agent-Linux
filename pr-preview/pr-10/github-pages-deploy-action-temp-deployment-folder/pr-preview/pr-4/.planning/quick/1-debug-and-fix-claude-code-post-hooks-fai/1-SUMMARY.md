---
phase: quick
plan: 1
subsystem: tooling
tags: [hooks, node, fnm, claude-code]
key-files:
  modified:
    - /home/claude/.claude/settings.json
decisions:
  - Use absolute fnm-managed node path instead of bare `node` for hook reliability
metrics:
  duration: 18s
  completed: 2026-03-09T11:41:46Z
---

# Quick Plan 1: Debug and Fix Claude Code Post-Hooks Failure Summary

**One-liner:** Replaced bare `node` with absolute fnm-managed path in all 3 Claude Code hook commands to fix execution in non-interactive shells.

## What Was Done

### Task 1: Replace bare node with absolute path in settings.json

Replaced all 3 occurrences of bare `node` command prefix in `/home/claude/.claude/settings.json` with the absolute path `/home/claude/.local/share/fnm/node-versions/v24.14.0/installation/bin/node`.

**Commands updated:**
- SessionStart hook: `gsd-check-update.js`
- PostToolUse hook: `gsd-context-monitor.js`
- statusLine: `gsd-statusline.js`

**Verification:**
- All 3 commands confirmed using absolute path (grep count = 3)
- JSON validated via python3 json.load
- Node binary confirmed working (v24.14.0)

**Note:** No git commit for this task because `/home/claude/.claude/settings.json` is a user-level config file outside the project repository.

## Deviations from Plan

None -- plan executed exactly as written.

## Self-Check: PASSED

- [x] /home/claude/.claude/settings.json modified with absolute paths (verified)
- [x] All 3 hook commands updated (verified via grep count)
- [x] JSON remains valid (verified via python3)
- [x] Node binary works at absolute path (verified v24.14.0)
- [ ] Git commit -- N/A (file outside repository)
