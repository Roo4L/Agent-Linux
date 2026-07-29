# Phase 57 — Deferred Items

Discovered during Wave 5 (57-06) execution. Out of the Wave-5 scope (like-for-like
pre-Node provisioner port + PROV-02 consolidation).

## Pre-existing bats failures (NOT Rust regressions — red on the Bash build too)

### 13-reuse.bats #29 — "REUSE-03: schema.json declares compatibility_window field"
- **Fails on:** BOTH the Rust build (`AGENTLINUX_PROVISION_RUST=1`) and the Bash
  build (flag unset), ubuntu-24.04.
- **Root cause:** Phase 54-02 (commit `d3acbba`, "regenerate schema.json from Rust
  types") produced `.["$defs"].agent.properties.compatibility_window.type =
  ["string","null"]` (a semver-nullable union). The bats @test asserts
  `.type == "string"` exactly, so the union trips it.
- **Evidence it is pre-existing:** `git diff HEAD -- plugin/catalog/schema.json
  tests/bats/13-reuse.bats` is empty for this plan — neither file was touched by
  Wave 5. The failure is identical on the Bash provisioner.
- **Disposition:** Out of scope for the provisioner port. Belongs to a
  schema-vs-bats reconciliation (widen the @test to accept the `["string","null"]`
  union OR narrow the schema back to `"string"`). Not a GATE-01 regression (no
  newly-red / newly-skipped case *relative to the Bash build*).

## Phase-59 QEMU / systemd / cron remainder

The full-surface bats matrix (Task 2) enumerates the systemd_user + cron invocation
modes of 30-runtime / 50-agents, AGT-02 self-update, and the full 4-distro QEMU
gate as the Phase-59 remainder (they are not Docker-runnable). See 57-06-SUMMARY.md
§"Phase-59 Deferred" for the file + @test + gate-reason enumeration.
