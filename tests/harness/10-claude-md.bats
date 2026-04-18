#!/usr/bin/env bats
# HRN-03: CLAUDE.md at repo root, strictly under 150 lines, HARNESS.md §6 sections present

@test "HRN-03: CLAUDE.md exists at repo root" {
  [ -f CLAUDE.md ]
}

@test "HRN-03: CLAUDE.md is strictly under 150 lines" {
  lines=$(wc -l < CLAUDE.md)
  # Fail-loud message if over budget.
  [ "$lines" -lt 150 ] || { echo "# HRN-03: CLAUDE.md must be < 150 lines; got: $lines"; return 1; }
}

@test "HRN-03: CLAUDE.md mentions project identity (AgentLinux v0.3.0)" {
  grep -q "AgentLinux v0.3.0" CLAUDE.md
}

@test "HRN-03: CLAUDE.md forbids sudo npm install -g" {
  # Must appear in a prohibition context (Never / Avoid / Do not / Don't),
  # not a recommendation. A literal substring grep would pass even if
  # CLAUDE.md recommended the pattern — anchor to the forbidding phrasing.
  grep -qEi "(never|avoid|do not|don't).{0,40}sudo npm install -g" CLAUDE.md
}

@test "HRN-03: CLAUDE.md references the review loop" {
  grep -qEi "review.?loop|review.feedback|/review" CLAUDE.md
}

@test "HRN-03: CLAUDE.md points to HARNESS.md" {
  grep -q "HARNESS.md" CLAUDE.md
}

@test "HRN-03: CLAUDE.md points to ROADMAP.md" {
  grep -q "ROADMAP.md" CLAUDE.md
}

@test "HRN-03: CLAUDE.md mentions QEMU before release" {
  grep -qi "qemu" CLAUDE.md
}
