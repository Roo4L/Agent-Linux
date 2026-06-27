#!/usr/bin/env bats
# AL-63: self-test for scripts/check-planning-clean.sh — the .planning/ hygiene
# gate (policy: .claude/skills/planning-workflow/SKILL.md). Builds a throwaway
# git fixture and asserts the gate's exit code + diagnostic for the clean state
# and for each intermediate / transient artifact the policy bans. Gives the
# merge-gate the same "the test is the spec" coverage as the rest of the suite.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FIXTURE="$(mktemp -d)"
  cd "$FIXTURE" || return 1
  git init -q
  git config user.email gate-test@example.com
  git config user.name gate-test
  cp "$REPO_ROOT/scripts/check-planning-clean.sh" "$FIXTURE/check.sh"
  mkdir -p .planning/milestones .planning/research .planning/todos
  printf -- '---\nstatus: complete\n---\n' >.planning/STATE.md
  : >.planning/MILESTONES.md
  : >.planning/milestones/v0.1.0-ROADMAP.md
  : >.planning/research/SUMMARY.md
  : >.planning/todos/.gitkeep
  git add -A
  git commit -qm fixture
}

teardown() {
  cd / || return 1
  rm -rf "$FIXTURE"
}

@test "AL-63 gate: clean between-milestones tree passes" {
  run bash "$FIXTURE/check.sh"
  [ "$status" -eq 0 ]
}

@test "AL-63 gate: loose phases/ fails with diagnostic" {
  mkdir -p .planning/phases/01-x
  : >.planning/phases/01-x/01-PLAN.md
  git add -A
  run bash "$FIXTURE/check.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"phases"* ]]
}

@test "AL-63 gate: quick/ fails" {
  mkdir -p .planning/quick/260601-x
  : >.planning/quick/260601-x/PLAN.md
  git add -A
  run bash "$FIXTURE/check.sh"
  [ "$status" -ne 0 ]
}

@test "AL-63 gate: quick-archive/ fails" {
  mkdir -p .planning/quick-archive/old-x
  : >.planning/quick-archive/old-x/SUMMARY.md
  git add -A
  run bash "$FIXTURE/check.sh"
  [ "$status" -ne 0 ]
}

@test "AL-63 gate: stray top-level *-MILESTONE-AUDIT.md fails" {
  : >.planning/v0.5.0-MILESTONE-AUDIT.md
  git add -A
  run bash "$FIXTURE/check.sh"
  [ "$status" -ne 0 ]
}

@test "AL-63 gate: in-flight top-level REQUIREMENTS.md fails" {
  : >.planning/REQUIREMENTS.md
  git add -A
  run bash "$FIXTURE/check.sh"
  [ "$status" -ne 0 ]
}

@test "AL-63 gate: STATE.md status != complete fails naming STATE.md" {
  printf -- '---\nstatus: in-progress\n---\n' >.planning/STATE.md
  git add -A
  run bash "$FIXTURE/check.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"STATE.md"* ]]
}

@test "AL-63 gate: tolerates trailing whitespace + quotes on status" {
  printf -- '---\nstatus: "complete"  \n---\n' >.planning/STATE.md
  git add -A
  run bash "$FIXTURE/check.sh"
  [ "$status" -eq 0 ]
}

@test "AL-63 gate: missing STATE.md fails" {
  git rm -q .planning/STATE.md
  run bash "$FIXTURE/check.sh"
  [ "$status" -ne 0 ]
}
