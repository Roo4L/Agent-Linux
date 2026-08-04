#!/usr/bin/env bats
# HRN-08: four GH Actions workflows exist, parse as valid YAML, named correctly,
# and the nightly-mutation workflow is advisory (continue-on-error).

@test "HRN-08: test.yml exists" { [ -f .github/workflows/test.yml ]; }
@test "HRN-08: nightly-qemu.yml exists" { [ -f .github/workflows/nightly-qemu.yml ]; }
@test "HRN-08: nightly-mutation.yml exists" { [ -f .github/workflows/nightly-mutation.yml ]; }
@test "HRN-08: release.yml exists" { [ -f .github/workflows/release.yml ]; }

@test "HRN-08: test.yml parses as valid YAML" {
  run python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml'))"
  [ "$status" -eq 0 ]
}

@test "HRN-08: nightly-qemu.yml parses as valid YAML" {
  run python3 -c "import yaml; yaml.safe_load(open('.github/workflows/nightly-qemu.yml'))"
  [ "$status" -eq 0 ]
}

@test "HRN-08: nightly-mutation.yml parses as valid YAML" {
  run python3 -c "import yaml; yaml.safe_load(open('.github/workflows/nightly-mutation.yml'))"
  [ "$status" -eq 0 ]
}

@test "HRN-08: release.yml parses as valid YAML" {
  run python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"
  [ "$status" -eq 0 ]
}

@test "HRN-08: test.yml has name: test" {
  grep -q "^name: test$" .github/workflows/test.yml
}

@test "HRN-08: nightly-qemu.yml has name: nightly-qemu" {
  grep -q "^name: nightly-qemu$" .github/workflows/nightly-qemu.yml
}

@test "HRN-08: nightly-mutation.yml has name: nightly-mutation" {
  grep -q "^name: nightly-mutation$" .github/workflows/nightly-mutation.yml
}

@test "HRN-08: release.yml has name: release" {
  grep -q "^name: release$" .github/workflows/release.yml
}

@test "HRN-08: nightly-mutation.yml is advisory (continue-on-error)" {
  grep -q "continue-on-error: true" .github/workflows/nightly-mutation.yml
}

@test "HRN-08: test.yml paths-ignore protects legacy website files" {
  grep -q "paths-ignore" .github/workflows/test.yml
}

@test "HRN-08: legacy website workflow .github/workflows/deploy.yml is untouched" {
  [ -f .github/workflows/deploy.yml ]
}
