#!/usr/bin/env bats
# tests/bats/00-secrets-smoke.bats — AL-53 convention example.
#
# Purpose: demonstrate the require_secret + .env.local + tests/docker/run.sh
# allowlist flow with a no-real-secret marker variable (FOO=bar). AL-54
# and any future secret-bearing tests follow this shape.
#
# The `00-` filename prefix is intentional: bats discovers test files in
# lexical order, so this convention example surfaces first in TAP output
# and serves as the discoverability beacon for the test-secrets contract.

load 'helpers/secrets'

@test "AL-53: require_secret skips yellow when FOO unset, asserts FOO=bar when set" {
  require_secret FOO
  # If we reach here, FOO is set (per .env.local + tests/docker/run.sh
  # SECRET_ALLOWLIST). Assert the documented value so the test fails
  # loud if the allowlist forwards a different value than expected.
  [ "$FOO" = "bar" ] || {
    echo "# FAIL: AL-53" >&2
    echo "#   expected: FOO=bar" >&2
    echo "#   observed: FOO=${FOO}" >&2
    echo "#   log:      docs/internals/test-secrets.md" >&2
    return 1
  }
}
