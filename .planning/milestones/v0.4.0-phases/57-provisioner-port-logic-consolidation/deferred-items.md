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

## Security / reliability review — consciously-accepted risks (RECORD-ONLY, no code)

Surfaced by the post-Phase-57 hardening review. The batch of code fixes it shipped
alongside (H-1 UID<1000 purge gate, M-1 default-path denylist, HIGH-1 pipefail,
M-1/M-3 curl timeouts, M-2 npm timeouts, M-3 log-init warning, L-1 fsync) are in
the git history; the items below are accepted-as-is with rationale and need NO
code change.

### Sec M-2 — `/opt` root-ownership is the load-bearing guard for `remove_dir_all("/opt/agentlinux")`
`cmd/provision.rs` `run_purge` step 2 does a literal `std::fs::remove_dir_all("/opt/agentlinux")`.
The path is a hardcoded LITERAL (never a `$VAR`), and `/opt` is root-owned on a
correctly-provisioned host, so a non-root actor cannot pre-seed a hostile symlink
there to redirect the delete. Safe as-is on a correctly-provisioned host; recorded
so the invariant (`/opt` root-ownership) is explicit rather than implicit.

### Sec M-3 — NodeSource curl-pipe TLS-only integrity (no SHA pin)
`pkg::nodesource_setup` fetches `setup_22.x` over HTTPS with `curl -fsSL` cert
verification and executes it; there is no body-SHA pin. This is the ADR-005
consciously-accepted risk (integrity = HTTPS cert-verify + the GPG-signed repo the
setup installs, T-57-09), faithfully ported from the Bash. The HIGH-1 pipefail +
M-3 curl-timeout fixes harden the *failure* path; the *integrity* model is
unchanged by design.

### Rel L-2 — the sudoers double-write's real guarantee is the post-install `visudo -cf dest` gate
The sudoers drop-in is written then re-validated; the load-bearing correctness
guarantee is the `visudo -cf <dest>` syntax gate that rejects a malformed file, not
the write ordering. Sound as-is — no change needed.
