#!/usr/bin/env bats
# TST-06: mutation-testing harness scaffolded, advisory-only
# Verifies stryker (Node) + bash-mutator.sh (bash) are runnable and non-blocking.

@test "TST-06: plugin/cli/stryker.config.json exists" {
  [ -f plugin/cli/stryker.config.json ]
}

@test "TST-06: plugin/cli/stryker.config.json is valid JSON" {
  run node -e "JSON.parse(require('fs').readFileSync('plugin/cli/stryker.config.json','utf8'))"
  [ "$status" -eq 0 ]
}

@test "TST-06: stryker config is advisory (break threshold = 0)" {
  grep -q '"break": 0' plugin/cli/stryker.config.json
}

@test "TST-06: stryker targets plugin/cli/src/**/*.ts" {
  grep -q '"mutate"' plugin/cli/stryker.config.json
  grep -q 'src/\*\*/\*.ts' plugin/cli/stryker.config.json
}

@test "TST-06: tests/mutation/bash-mutator.sh exists and is executable" {
  [ -x tests/mutation/bash-mutator.sh ]
}

@test "TST-06: bash-mutator.sh passes bash -n (valid syntax)" {
  run bash -n tests/mutation/bash-mutator.sh
  [ "$status" -eq 0 ]
}

@test "TST-06: bash-mutator.sh exits 0 on empty-plugin skeleton (advisory)" {
  run bash tests/mutation/bash-mutator.sh
  [ "$status" -eq 0 ]
}

@test "TST-06: tests/mutation/README.md explains advisory status" {
  [ -f tests/mutation/README.md ]
  grep -qi "advisory" tests/mutation/README.md
}

@test "TST-06: nightly-mutation workflow has continue-on-error" {
  grep -q "continue-on-error: true" .github/workflows/nightly-mutation.yml
}
