#!/usr/bin/env bats
# HRN-01: project layout matches docs/HARNESS.md §1.1
# Every @test asserts one directory / file the harness spec requires.
#
# Post-cutover (v0.4.0): the registry CLI + provisioner are the Rust workspace
# under rust/ (the legacy plugin/cli TS + plugin/lib + plugin/provisioner Bash
# were deleted). plugin/catalog/ (the Bash recipes) and packaging/curl-installer
# remain. JSON validity is checked with jq (no Node prerequisite).

@test "HRN-01: rust/Cargo.toml (cargo workspace root) exists" {
  [ -f rust/Cargo.toml ]
}

@test "HRN-01: rust/crates/agentlinux (the bin crate) exists" {
  [ -d rust/crates/agentlinux ]
}

@test "HRN-01: rust/crates/agentlinux-core (the pure-logic crate) exists" {
  [ -d rust/crates/agentlinux-core ]
}

@test "HRN-01: plugin/catalog/catalog.json is valid JSON" {
  run jq empty plugin/catalog/catalog.json
  [ "$status" -eq 0 ]
}

@test "HRN-01: plugin/catalog/schema.json is valid JSON" {
  run jq empty plugin/catalog/schema.json
  [ "$status" -eq 0 ]
}

@test "HRN-01: plugin/catalog/agents directory exists" {
  [ -d plugin/catalog/agents ]
}

@test "HRN-01: packaging/curl-installer directory exists" {
  [ -d packaging/curl-installer ]
}

# HRN-01: packaging/deb was removed in Phase 58 (DIST-02) — the optional fpm .deb
# channel is superseded by the reproducible musl tarball + .sha256 (the sole
# channel). The layout contract no longer enumerates packaging/deb.

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
