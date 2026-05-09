#!/usr/bin/env bats
# HRN-01: project layout matches docs/HARNESS.md §1.1
# Every @test asserts one directory / file the harness spec requires.

@test "HRN-01: plugin/bin/agentlinux-install exists and is executable" {
  [ -x plugin/bin/agentlinux-install ]
}

@test "HRN-01: plugin/lib directory exists" {
  [ -d plugin/lib ]
}

@test "HRN-01: plugin/provisioner directory exists" {
  [ -d plugin/provisioner ]
}

@test "HRN-01: plugin/cli/package.json is valid JSON" {
  run node -e "JSON.parse(require('fs').readFileSync('plugin/cli/package.json','utf8'))"
  [ "$status" -eq 0 ]
}

@test "HRN-01: plugin/cli/tsconfig.json is valid JSON" {
  run node -e "JSON.parse(require('fs').readFileSync('plugin/cli/tsconfig.json','utf8'))"
  [ "$status" -eq 0 ]
}

@test "HRN-01: plugin/cli/biome.json is valid JSON" {
  run node -e "JSON.parse(require('fs').readFileSync('plugin/cli/biome.json','utf8'))"
  [ "$status" -eq 0 ]
}

@test "HRN-01: plugin/catalog/schema.json is valid JSON" {
  run node -e "JSON.parse(require('fs').readFileSync('plugin/catalog/schema.json','utf8'))"
  [ "$status" -eq 0 ]
}

@test "HRN-01: plugin/catalog/agents directory exists" {
  [ -d plugin/catalog/agents ]
}

@test "HRN-01: packaging/curl-installer directory exists" {
  [ -d packaging/curl-installer ]
}

@test "HRN-01: packaging/deb directory exists" {
  [ -d packaging/deb ]
}

@test "HRN-01: tests/bats/helpers directory exists" {
  [ -d tests/bats/helpers ]
}

@test "HRN-01: tests/docker directory exists" {
  [ -d tests/docker ]
}

@test "HRN-01: tests/qemu/cloud-init directory exists" {
  [ -d tests/qemu/cloud-init ]
}

@test "HRN-01: tests/mutation directory exists" {
  [ -d tests/mutation ]
}

@test "HRN-01: docs/decisions directory exists" {
  [ -d docs/decisions ]
}

@test "HRN-01: docs/research/v0.3.0 directory exists" {
  [ -d docs/research/v0.3.0 ]
}

@test "HRN-01: docs/research/v0.2.0 directory exists" {
  [ -d docs/research/v0.2.0 ]
}

@test "HRN-01: docs/proposals, docs/analysis, docs/reviews exist" {
  [ -d docs/proposals ]
  [ -d docs/analysis ]
  [ -d docs/reviews ]
}

@test "HRN-01: legacy v0.1.0 site (index.html) untouched" {
  [ -f index.html ]
}

@test "HRN-01: legacy packer/ directory untouched" {
  [ -d packer ]
}
