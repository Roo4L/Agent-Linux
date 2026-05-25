# tests/bats/helpers/secrets.bash — AL-53 test-secrets contract.
#
# Provides `require_secret <VAR>` for bats tests that need a live secret
# (e.g. AL-54 interactive Claude Code tests). When the named var is unset
# or empty, the helper calls bats's `skip` builtin to yellow-skip the test
# rather than red-fail it. This keeps per-PR Docker CI green when the
# release-gate-only sandbox key isn't available, while the nightly QEMU
# release-gate job (which DOES receive the key from repo Actions secrets)
# exercises the same tests through to completion.
#
# Design invariants (mirror helpers/assertions.bash):
#   - No `set -euo pipefail` at top: this file is SOURCED by bats via
#     `load 'helpers/secrets'`; strict mode inside a sourced library
#     breaks TAP output on the first non-zero command.
#   - require_secret references the named var via bash indirect expansion
#     `${!var_name-}` (NOT eval, NOT `${!var_name}` without default —
#     the dash form returns empty under `set -u` if the var is unset).
#   - The variable name comes from `$1` only; no `$@` concatenation, no
#     command substitution. Indirect expansion is a pure parameter
#     lookup — a malicious name like `$(rm -rf /)` is a literal lookup
#     of a parameter with that name, returning empty.
#
# Usage in a @test:
#   load 'helpers/secrets'
#   @test "AL-54: claude --version reports a version" {
#     require_secret ANTHROPIC_API_KEY
#     # ... test body uses $ANTHROPIC_API_KEY ...
#   }
#
# Refs: docs/internals/test-secrets.md (end-to-end pipeline + add-a-secret
# checklist + rotation + leak response).

require_secret() {
  local var_name=$1
  if [[ -z ${!var_name-} ]]; then
    skip "${var_name} not provisioned; see docs/internals/test-secrets.md"
  fi
  return 0
}
