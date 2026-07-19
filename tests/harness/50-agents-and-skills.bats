#!/usr/bin/env bats
# HRN-06: project-scoped portable reviewer roles under .claude/agents/
# HRN-07: /review skill at .claude/skills/review/SKILL.md
#         (+ Codex reviewer-role projection under .codex/agents/)
# HRN-09: four project-scoped skill skeletons under .claude/skills/
# TST-07 (scaffold): behavior-coverage-auditor exists + names itself as end-of-phase gate

# ---- HRN-06: subagents --------------------------------------------------------

@test "HRN-06: bash-engineer subagent exists" {
  [ -f .claude/agents/bash-engineer.md ]
}

@test "HRN-06: node-engineer subagent exists" {
  [ -f .claude/agents/node-engineer.md ]
}

@test "HRN-06: security-engineer subagent exists" {
  [ -f .claude/agents/security-engineer.md ]
}

@test "HRN-06: qa-engineer subagent exists" {
  [ -f .claude/agents/qa-engineer.md ]
}

@test "HRN-06: behavior-coverage-auditor subagent exists" {
  [ -f .claude/agents/behavior-coverage-auditor.md ]
}

@test "HRN-06: catalog-auditor subagent exists" {
  [ -f .claude/agents/catalog-auditor.md ]
}

@test "HRN-06: each subagent has matching frontmatter name" {
  for a in bash-engineer node-engineer security-engineer qa-engineer behavior-coverage-auditor catalog-auditor; do
    grep -q "^name: $a$" ".claude/agents/$a.md" \
      || { echo "# HRN-06: .claude/agents/$a.md missing or mismatched 'name:'"; return 1; }
  done
}

@test "HRN-06: each subagent has a description field" {
  for a in bash-engineer node-engineer security-engineer qa-engineer behavior-coverage-auditor catalog-auditor; do
    grep -q "^description:" ".claude/agents/$a.md" \
      || { echo "# HRN-06: .claude/agents/$a.md missing 'description:'"; return 1; }
  done
}

@test "HRN-06: each subagent has a tools field" {
  for a in bash-engineer node-engineer security-engineer qa-engineer behavior-coverage-auditor catalog-auditor; do
    grep -q "^tools:" ".claude/agents/$a.md" \
      || { echo "# HRN-06: .claude/agents/$a.md missing 'tools:'"; return 1; }
  done
}

@test "HRN-06: every portable reviewer role has matching frontmatter" {
  for a in bash-engineer node-engineer security-engineer qa-engineer behavior-coverage-auditor catalog-auditor ai-deslop dev-docs-auditor technical-writer fact-checker external-audience-auditor; do
    [ -f ".claude/agents/$a.md" ] \
      || { echo "# HRN-06: missing portable reviewer role $a"; return 1; }
    grep -q "^name: $a$" ".claude/agents/$a.md" \
      || { echo "# HRN-06: $a has mismatched 'name:'"; return 1; }
    grep -q "^description:" ".claude/agents/$a.md" \
      || { echo "# HRN-06: $a is missing 'description:'"; return 1; }
  done
}

@test "HRN-06: bash-engineer rubric mentions shellcheck" {
  grep -qi "shellcheck" .claude/agents/bash-engineer.md
}

@test "HRN-06: security-engineer rubric mentions sudoers mode 0440" {
  grep -qEi "0440|sudoers" .claude/agents/security-engineer.md
}

@test "TST-07 (scaffold): behavior-coverage-auditor names the end-of-phase gate" {
  grep -qEi "TST-07|end.of.every.phase|end-of-phase|every phase" .claude/agents/behavior-coverage-auditor.md
}

# ---- HRN-07: /review skill ----------------------------------------------------

@test "HRN-07: /review skill file exists" {
  [ -f .claude/skills/review/SKILL.md ]
}

@test "HRN-07: /review skill has name: review and a description" {
  grep -q "^name: review$" .claude/skills/review/SKILL.md
  grep -q "^description:" .claude/skills/review/SKILL.md
}

@test "HRN-07: /review skill references all portable reviewer roles" {
  for a in bash-engineer node-engineer security-engineer qa-engineer behavior-coverage-auditor catalog-auditor ai-deslop dev-docs-auditor technical-writer fact-checker external-audience-auditor; do
    grep -qi "$a" .claude/skills/review/SKILL.md \
      || { echo "# HRN-07: /review SKILL.md does not reference $a"; return 1; }
  done
}

@test "HRN-07: /review skill documents the host-neutral trigger and dispatch" {
  grep -qEi "agent-neutral|native subagent|host agent" .claude/skills/review/SKILL.md
  grep -q "Do not invoke the Claude CLI" .claude/skills/review/SKILL.md
  grep -qi "do not substitute the built-in.*codex review" .claude/skills/review/SKILL.md
  grep -q "read-only capability profile" .claude/skills/review/SKILL.md
  grep -q "changed-file allowlist" .claude/skills/review/SKILL.md
}

@test "HRN-07: Codex sees the shared review skill" {
  [ -L .codex/skills/review ]
  [ "$(readlink -f .codex/skills/review)" = "$(readlink -f .claude/skills/review)" ]
  # Codex dispatch is documented as the native multi-agent spawn_agent path.
  grep -qEi "spawn_agent|multi_agent" docs/codex.md
}

@test "HRN-07: Claude review reminder is a one-shot native-subagent nudge" {
  run bash .claude/hooks/review-reminder.sh <<< '{"stop_hook_active":false}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *'shared project $review skill'* ]]
  [[ "$output" == *'built-in codex review command'* ]]

  run bash .claude/hooks/review-reminder.sh <<< '{"stop_hook_active":true}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "HRN-07: Codex review reminder is a one-shot native-subagent nudge" {
  run bash .codex/hooks/review-reminder.sh <<< '{"stop_hook_active":false}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *'spawn_agent'* ]]
  [[ "$output" == *'built-in `codex review` command'* ]]

  run bash .codex/hooks/review-reminder.sh <<< '{"stop_hook_active":true}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---- HRN-07: Codex reviewer-role projection (.codex/agents/) ------------------

@test "HRN-07: every reviewer role has a Codex agent projection" {
  # Enumerate the canonical source dir so a newly added role is covered
  # automatically — no hardcoded list to fall out of sync.
  for f in .claude/agents/*.md; do
    a="$(basename "$f" .md)"
    [ -f ".codex/agents/$a.toml" ] \
      || { echo "# HRN-07: missing Codex agent projection .codex/agents/$a.toml"; return 1; }
    grep -q "^name = \"$a\"$" ".codex/agents/$a.toml" \
      || { echo "# HRN-07: .codex/agents/$a.toml has mismatched 'name'"; return 1; }
    grep -q '^sandbox_mode = "read-only"$' ".codex/agents/$a.toml" \
      || { echo "# HRN-07: .codex/agents/$a.toml is not sandboxed read-only"; return 1; }
    grep -qi "$a" .claude/skills/review/SKILL.md \
      || { echo "# HRN-07: /review SKILL.md does not reference role $a"; return 1; }
  done
}

@test "HRN-07: .codex/agents/ is in sync with .claude/agents/" {
  run bash scripts/sync-codex-agents.sh --check
  [ "$status" -eq 0 ] || { echo "# $output"; return 1; }
}

# ---- HRN-09: four project-scoped skill skeletons -----------------------------

@test "HRN-09: agentlinux-installer skill skeleton exists" {
  [ -f .claude/skills/agentlinux-installer/SKILL.md ]
}

@test "HRN-09: behavior-test-contract skill skeleton exists" {
  [ -f .claude/skills/behavior-test-contract/SKILL.md ]
}

@test "HRN-09: catalog-schema skill skeleton exists" {
  [ -f .claude/skills/catalog-schema/SKILL.md ]
}

@test "HRN-09: qemu-harness skill skeleton exists" {
  [ -f .claude/skills/qemu-harness/SKILL.md ]
}

@test "HRN-09: each skill has matching frontmatter name" {
  for s in agentlinux-installer behavior-test-contract catalog-schema qemu-harness; do
    grep -q "^name: $s$" ".claude/skills/$s/SKILL.md" \
      || { echo "# HRN-09: .claude/skills/$s/SKILL.md missing or mismatched 'name:'"; return 1; }
  done
}

@test "HRN-09: each skill has a description field" {
  for s in agentlinux-installer behavior-test-contract catalog-schema qemu-harness; do
    grep -q "^description:" ".claude/skills/$s/SKILL.md" \
      || { echo "# HRN-09: .claude/skills/$s/SKILL.md missing 'description:'"; return 1; }
  done
}

@test "HRN-09: agentlinux-installer documents set -euo pipefail" {
  grep -qi "set -euo pipefail" .claude/skills/agentlinux-installer/SKILL.md
}

@test "HRN-09: behavior-test-contract enumerates invocation modes" {
  grep -qEi "cron|systemd|sudo -u|non-interactive SSH" .claude/skills/behavior-test-contract/SKILL.md
}

@test "HRN-09: qemu-harness links ADR-007 or Docker-only rationale" {
  grep -qEi "ADR-007|Docker-only" .claude/skills/qemu-harness/SKILL.md
}
