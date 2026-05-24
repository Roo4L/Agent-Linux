#!/usr/bin/env bats
# HRN-04: ADR-001..ADR-010 seeded in docs/decisions/
# HRN-05: research migrated to docs/research/v0.{2,3}.0/

@test "HRN-04: ADR template exists" {
  [ -f docs/decisions/000-template.md ]
}

@test "HRN-04: ADR-001 pivot-distro-to-plugin exists" {
  [ -f docs/decisions/001-pivot-distro-to-plugin.md ]
}

@test "HRN-04: ADR-002 behavior-contract-framing exists" {
  [ -f docs/decisions/002-behavior-contract-framing.md ]
}

@test "HRN-04: ADR-003 no-default-agents-installed exists" {
  [ -f docs/decisions/003-no-default-agents-installed.md ]
}

@test "HRN-04: ADR-004 per-user-npm-prefix exists" {
  [ -f docs/decisions/004-per-user-npm-prefix.md ]
}

@test "HRN-04: ADR-005 system-nodejs-over-version-managers exists" {
  [ -f docs/decisions/005-system-nodejs-over-version-managers.md ]
}

@test "HRN-04: ADR-006 curl-pipe-bash-plus-deb exists" {
  [ -f docs/decisions/006-curl-pipe-bash-plus-deb.md ]
}

@test "HRN-04: ADR-007 docker-plus-qemu-harness exists" {
  [ -f docs/decisions/007-docker-plus-qemu-harness.md ]
}

@test "HRN-04: ADR-008 commander-js-for-cli exists" {
  [ -f docs/decisions/008-commander-js-for-cli.md ]
}

@test "HRN-04: ADR-009 snap-disqualified exists" {
  [ -f docs/decisions/009-snap-disqualified.md ]
}

@test "HRN-04: ADR-010 review-loop-via-claude-md exists" {
  [ -f docs/decisions/010-review-loop-via-claude-md.md ]
}

@test "HRN-04: every ADR-001..010 has **Status:** Accepted" {
  for a in 001-pivot-distro-to-plugin \
           002-behavior-contract-framing \
           003-no-default-agents-installed \
           004-per-user-npm-prefix \
           005-system-nodejs-over-version-managers \
           006-curl-pipe-bash-plus-deb \
           007-docker-plus-qemu-harness \
           008-commander-js-for-cli \
           009-snap-disqualified \
           010-review-loop-via-claude-md; do
    grep -q "\*\*Status:\*\* Accepted" "docs/decisions/$a.md" \
      || { echo "# HRN-04: docs/decisions/$a.md missing Accepted status"; return 1; }
  done
}

@test "HRN-04: ADR-005 consequences explain invocation-mode blast radius" {
  grep -qEi "cron|systemd|non-interactive" docs/decisions/005-system-nodejs-over-version-managers.md
}

@test "HRN-04: ADR-010 consequences explain why not a Stop hook" {
  grep -qi "stop hook" docs/decisions/010-review-loop-via-claude-md.md
}

@test "HRN-05: docs/research/v0.3.0 contains the five research files" {
  for f in STACK.md FEATURES.md ARCHITECTURE.md PITFALLS.md SUMMARY.md; do
    [ -f "docs/research/v0.3.0/$f" ] \
      || { echo "# HRN-05: missing docs/research/v0.3.0/$f"; return 1; }
  done
}

@test "HRN-05: docs/research/v0.2.0 contains the five research files" {
  for f in STACK.md FEATURES.md ARCHITECTURE.md PITFALLS.md SUMMARY.md; do
    [ -f "docs/research/v0.2.0/$f" ] \
      || { echo "# HRN-05: missing docs/research/v0.2.0/$f"; return 1; }
  done
}

@test "HRN-05: v0.3.0 SUMMARY.md byte-matches the planning/ source" {
  diff -q .planning/research/SUMMARY.md docs/research/v0.3.0/SUMMARY.md
}

@test "HRN-05: v0.2.0 SUMMARY.md byte-matches the planning/ source" {
  diff -q .planning/milestones/v0.2.0-research/SUMMARY.md docs/research/v0.2.0/SUMMARY.md
}

@test "HRN-05: docs/README.md indexes the docs/ tree" {
  [ -f docs/README.md ]
  grep -q "HARNESS.md" docs/README.md
}
