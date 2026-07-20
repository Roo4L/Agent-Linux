#!/usr/bin/env bats
# HRN-03: Claude host adapter at repo root, with shared context in AGENTS.md

@test "HRN-03: CLAUDE.md exists at repo root" {
  [ -f CLAUDE.md ]
}

@test "HRN-03: CLAUDE.md is strictly under 150 lines" {
  # Note: avoid the name 'lines' — it collides with bats' magic array.
  local line_count
  line_count=$(wc -l < CLAUDE.md)
  # Fail-loud message if over budget.
  [ "$line_count" -lt 150 ] || { echo "# HRN-03: CLAUDE.md must be < 150 lines; got: $line_count"; return 1; }
}

@test "HRN-03: AGENTS.md carries project identity (AgentLinux v0.3.0)" {
  grep -q "AgentLinux v0.3.0" AGENTS.md
}

@test "HRN-03: AGENTS.md forbids sudo npm install -g" {
  # Must appear in a prohibition context (Never / Avoid / Do not / Don't),
  # not a recommendation. A literal substring grep would pass even if
  # CLAUDE.md recommended the pattern — anchor to the forbidding phrasing.
  grep -qEi "(never|avoid|do not|don't).{0,40}sudo npm install -g" AGENTS.md
}

@test "HRN-03: CLAUDE.md references the review loop" {
  grep -qEi "review.?loop|review.feedback|/review" CLAUDE.md
}

@test "HRN-03: CLAUDE.md points to HARNESS.md" {
  grep -q "HARNESS.md" CLAUDE.md
}

@test "HRN-03: CLAUDE.md points to ROADMAP.md" {
  grep -q "ROADMAP.md" AGENTS.md
}

@test "HRN-03: CLAUDE.md mentions QEMU before release" {
  grep -qi "qemu" AGENTS.md
}
