#!/usr/bin/env bats
# HRN-02: .pre-commit-config.yaml covers the post-cutover hook set — shellcheck,
# shfmt, gitleaks, catalog-schema-validate (jq-based) + the catalog↔Cargo version
# lockstep. The TS biome hook and the node ajv validate-catalog.mjs were removed
# with plugin/cli/ at the Rust cutover.

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

@test "HRN-02: gitleaks hook present" {
  grep -q "gitleaks" .pre-commit-config.yaml
}

@test "HRN-02: catalog-schema-validate hook present" {
  grep -q "catalog-schema-validate" .pre-commit-config.yaml
}

@test "HRN-02: catalog-schema check script exists and is executable" {
  [ -x scripts/check-catalog-schema.sh ]
}

@test "HRN-02: catalog-schema check passes on the current catalog" {
  run scripts/check-catalog-schema.sh
  [ "$status" -eq 0 ]
}

@test "HRN-02: catalog↔Cargo version-lockstep hook present" {
  grep -q "check-version-lockstep" .pre-commit-config.yaml
  [ -x scripts/check-version-lockstep.sh ]
}
