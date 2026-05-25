#!/usr/bin/env bats
# tests/bats/00-secrets-smoke.bats
# TST-08 convention example: end-to-end smoke for `.env.local` -> docker
# `-e VAR` -> bats `require_secret` with the no-real-secret marker variable
# FOO=bar. Future secret-bearing tests copy this shape — but they MUST NOT
# echo the secret value on failure (see expected/observed lines below).
#
# The `00-` filename prefix is intentional: bats discovers test files in
# lexical order, so this convention example surfaces first in TAP output.
# 00- files MUST NOT depend on installer state — they precede the installer
# suites and run before any installer fixture is in place.

load 'helpers/assertions'
load 'helpers/secrets'

@test "TST-08: require_secret skips yellow when FOO unset, asserts FOO=bar when set" {
  require_secret FOO
  # If we reach here, FOO is set (per .env.local + tests/docker/run.sh
  # SECRET_ALLOWLIST). Assert the documented value so the test fails loud
  # if the allowlist forwards a different value than expected.
  #
  # Template-hygiene note for AL-54 + future secret-bearing tests: this
  # smoke uses the public marker FOO=bar so printing its value on failure
  # is safe. For REAL secrets (ANTHROPIC_API_KEY, etc.) the observed
  # field MUST stay redacted — print "<set>" / "<unset>" / "<wrong-length>",
  # never the value itself. bats's $output capture surfaces in CI logs.
  [ "$FOO" = "bar" ] || __fail "TST-08" \
    "FOO=bar (forwarded via SECRET_ALLOWLIST)" \
    "FOO=${FOO}" \
    "docs/internals/test-secrets.md"
}
