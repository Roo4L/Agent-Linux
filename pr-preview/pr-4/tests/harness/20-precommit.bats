#!/usr/bin/env bats
# HRN-02: .pre-commit-config.yaml covers shellcheck, shfmt, biome, catalog-schema-validate

@test "HRN-02: .pre-commit-config.yaml exists" {
  [ -f .pre-commit-config.yaml ]
}

@test "HRN-02: .pre-commit-config.yaml is valid YAML" {
  run python3 -c "import yaml; yaml.safe_load(open('.pre-commit-config.yaml'))"
  [ "$status" -eq 0 ]
}

@test "HRN-02: shellcheck hook present" {
  grep -q "shellcheck" .pre-commit-config.yaml
}

@test "HRN-02: shfmt hook present" {
  grep -q "shfmt" .pre-commit-config.yaml
}

@test "HRN-02: biome hook present" {
  grep -q "biome" .pre-commit-config.yaml
}

@test "HRN-02: catalog-schema-validate hook present" {
  grep -q "catalog-schema-validate" .pre-commit-config.yaml
}

@test "HRN-02: validate-catalog.mjs exists and is executable" {
  [ -x plugin/cli/scripts/validate-catalog.mjs ]
}

@test "HRN-02: validate-catalog.mjs passes on empty-plugin skeleton" {
  run node plugin/cli/scripts/validate-catalog.mjs
  [ "$status" -eq 0 ]
}
