#!/usr/bin/env bats
# HRN-06: six project-scoped review subagents under .claude/agents/
# HRN-07: /review skill at .claude/skills/review/SKILL.md
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

@test "HRN-07: /review skill references all six subagents" {
  for a in bash-engineer node-engineer security-engineer qa-engineer behavior-coverage-auditor catalog-auditor; do
    grep -qi "$a" .claude/skills/review/SKILL.md \
      || { echo "# HRN-07: /review SKILL.md does not reference $a"; return 1; }
  done
}

@test "HRN-07: /review skill documents ADR-010 trigger mechanism" {
  grep -qEi "ADR-010|Stop hook|CLAUDE.md instruction" .claude/skills/review/SKILL.md
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
