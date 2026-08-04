---
phase: quick
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - /home/claude/.claude/settings.json
autonomous: true
must_haves:
  truths:
    - "Claude Code hooks execute without 'node not found' errors"
    - "SessionStart, PostToolUse, and statusLine all use absolute node path"
  artifacts:
    - path: "/home/claude/.claude/settings.json"
      provides: "Hook configuration with absolute node paths"
      contains: "/home/claude/.local/share/fnm/node-versions/v24.14.0/installation/bin/node"
  key_links: []
---

<objective>
Fix Claude Code hook failures caused by bare `node` command not being on PATH during hook execution.

Purpose: fnm manages node via ephemeral multishell paths that only exist in interactive shells. Claude Code hooks don't source .bashrc, so bare `node` fails. Replace with absolute path to the stable fnm-managed node binary.

Output: Updated settings.json with working hook commands.
</objective>

<context>
Target file: /home/claude/.claude/settings.json
Stable node path: /home/claude/.local/share/fnm/node-versions/v24.14.0/installation/bin/node

Current broken commands (3 occurrences of bare `node`):
1. SessionStart hook: node "/home/claude/.claude/hooks/gsd-check-update.js"
2. PostToolUse hook: node "/home/claude/.claude/hooks/gsd-context-monitor.js"
3. statusLine: node "/home/claude/.claude/hooks/gsd-statusline.js"
</context>

<tasks>

<task type="auto">
  <name>Task 1: Replace bare node with absolute path in settings.json</name>
  <files>/home/claude/.claude/settings.json</files>
  <action>
    Read /home/claude/.claude/settings.json and replace all 3 occurrences of bare `node` command prefix with the absolute path `/home/claude/.local/share/fnm/node-versions/v24.14.0/installation/bin/node`. Preserve all other settings and JSON structure exactly.

    The 3 replacements:
    - SessionStart hook command: `node "/home/claude/.claude/hooks/gsd-check-update.js"` becomes `/home/claude/.local/share/fnm/node-versions/v24.14.0/installation/bin/node "/home/claude/.claude/hooks/gsd-check-update.js"`
    - PostToolUse hook command: `node "/home/claude/.claude/hooks/gsd-context-monitor.js"` becomes `/home/claude/.local/share/fnm/node-versions/v24.14.0/installation/bin/node "/home/claude/.claude/hooks/gsd-context-monitor.js"`
    - statusLine command: `node "/home/claude/.claude/hooks/gsd-statusline.js"` becomes `/home/claude/.local/share/fnm/node-versions/v24.14.0/installation/bin/node "/home/claude/.claude/hooks/gsd-statusline.js"`
  </action>
  <verify>
    <automated>grep -c '/home/claude/.local/share/fnm/node-versions/v24.14.0/installation/bin/node' /home/claude/.claude/settings.json | grep -q '^3$' && echo "PASS: All 3 commands use absolute path" || echo "FAIL: Not all commands updated"</automated>
  </verify>
  <done>All 3 hook/statusLine commands in settings.json use the absolute node path. No bare `node` remains as a command prefix. JSON is valid.</done>
</task>

</tasks>

<verification>
- `grep 'node' /home/claude/.claude/settings.json` shows only absolute paths, no bare `node` command
- `python3 -c "import json; json.load(open('/home/claude/.claude/settings.json'))"` confirms valid JSON
- `/home/claude/.local/share/fnm/node-versions/v24.14.0/installation/bin/node -v` confirms the binary works
</verification>

<success_criteria>
All 3 commands in /home/claude/.claude/settings.json use the absolute node path. Hooks will resolve node correctly regardless of shell environment.
</success_criteria>

<output>
No summary file needed for quick plans.
</output>
