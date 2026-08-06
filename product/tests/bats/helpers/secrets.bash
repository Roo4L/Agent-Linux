# tests/bats/helpers/secrets.bash
# TST-08 contract: `require_secret <VAR>` skips the current test (yellow,
# bats `skip` builtin) when the named env var is unset OR empty. When the
# var is set to a non-empty value, the helper is a no-op.
#
# Design invariants (mirror helpers/assertions.bash):
#   - No `set -euo pipefail` at top: sourced by bats via `load 'helpers/secrets'`.
#   - require_secret uses `${!var_name-}` (dash form returns empty under
#     `set -u`); no eval, no command substitution on the var name.
#   - Empty string is treated identically to unset — a contributor who exports
#     `VAR=""` in `.env.local` sees a skip, not a confusing pass-then-fail.
#
# Usage in a @test:
#   load 'helpers/secrets'
#   @test "TST-NN: <behavior>" {
#     require_secret ANTHROPIC_API_KEY
#     # ... test body uses $ANTHROPIC_API_KEY ...
#   }
#
# Refs: docs/internals/test-secrets.md (pipeline + add-a-secret checklist
# + rotation + leak response).

require_secret() {
  local var_name=$1
  if [[ -z ${!var_name-} ]]; then
    skip "${var_name} not provisioned; see docs/internals/test-secrets.md"
  fi
  return 0
}
