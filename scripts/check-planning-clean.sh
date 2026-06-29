#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# scripts/check-planning-clean.sh — AL-63 .planning/ hygiene gate.
#
# Asserts that the tracked contents of .planning/ are in the clean
# "between-milestones" state master requires: only the durable record (the
# GSD ledger + per-milestone archive + project memory) may be tracked, and
# STATE.md must report status: complete.
#
# Intermediate GSD working state — loose phase directories, quick-task
# directories, in-flight REQUIREMENTS.md, and transient session files — lives
# on a feature branch and is stripped before merge (see the planning-workflow
# skill). This gate is the backstop that keeps that state off master: any
# tracked entry under .planning/ outside the allowlist fails the check.
#
# Scope: the allowlist check inspects `git ls-files .planning/` (the tracked
# tree) — gitignored transient files never appear, and a force-added one is
# caught because it becomes tracked. It matches only the first path component,
# so it trusts the internal hygiene of the durable dirs (milestones/, research/,
# todos/) rather than recursing into them. The STATE.md status check reads the
# working-tree file (identical to the tracked blob in a clean CI checkout).
#
# Refs: AL-63 (this gate); .claude/skills/planning-workflow/SKILL.md (policy).

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

readonly STATE_FILE=.planning/STATE.md

# Durable top-level entries master's .planning/ may carry. Everything else is
# branch-only (phases/, quick/, quick-archive/, in-flight REQUIREMENTS.md,
# stray top-level *-MILESTONE-AUDIT.md) or transient (session files) and must
# not reach master.
readonly -a ALLOWED=(
  MILESTONES.md
  PROJECT.md
  ROADMAP.md
  RETROSPECTIVE.md
  STATE.md
  config.json
  milestones
  research
  todos
)

is_allowed() {
  local entry=$1 ok
  for ok in "${ALLOWED[@]}"; do
    [[ $entry == "$ok" ]] && return 0
  done
  return 1
}

fail=0

# Distinct first path components tracked under .planning/.
violations=$(
  git ls-files .planning/ \
    | sed -E 's#^\.planning/([^/]+).*#\1#' \
    | sort -u \
    | while IFS= read -r entry; do
      is_allowed "$entry" || printf '%s\n' "$entry"
    done
)

if [[ -n $violations ]]; then
  fail=1
  {
    printf 'check-planning-clean: intermediate GSD state is tracked under .planning/ on a branch targeting master:\n'
    while IFS= read -r v; do
      printf '  - .planning/%s\n' "$v"
    done <<<"$violations"
    printf '\n'
    printf 'master carries only the durable record. Strip the loose phases/ + quick/\n'
    printf 'working dirs (or run /gsd-complete-milestone) before merging.\n'
    printf 'See .claude/skills/planning-workflow/SKILL.md.\n'
  } >&2
fi

# STATE.md must report a closed, between-milestones cursor. Read only the
# leading YAML frontmatter (between the first two `---` fences).
if [[ -r $STATE_FILE ]]; then
  state_status=$(
    awk '
      { sub(/\r$/, "") }
      NR == 1 && $0 == "---" { in_fm = 1; next }
      in_fm && $0 == "---" { exit }
      in_fm && sub(/^status:[[:space:]]*/, "") {
        sub(/[[:space:]]+$/, "")
        gsub(/^"|"$/, "")
        print
        exit
      }
    ' "$STATE_FILE"
  )
  if [[ $state_status != "complete" ]]; then
    fail=1
    printf 'check-planning-clean: %s frontmatter status=%q, expected "complete" (between milestones)\n' \
      "$STATE_FILE" "$state_status" >&2
  fi
else
  fail=1
  printf 'check-planning-clean: %s missing or unreadable\n' "$STATE_FILE" >&2
fi

((fail == 0)) || exit 1
exit 0
