#!/usr/bin/env bats
# tests/bats/61-no-node-prereq.bats — INST-08 (DIST-01: the CLI/provisioner
# needs NO Node prerequisite).
#
# Every @test name starts with the requirement ID (INST-08:) so
# the suite readable; failures route through
# `__fail` for the four-line TST-04 diagnostic (helpers/assertions).
#
# DIST-01's central claim after the Phase-58 musl swap: the shipped `agentlinux`
# CLI + the `provision` provisioner it runs are a SINGLE static-musl binary with
# no runtime dependency on Node/npm/pnpm. The chicken-and-egg the old Bash+TS
# distribution had ("you need Node to run the provisioner that installs Node") is
# gone — the static bin bootstraps a bare host, and `nodejs.rs` (provisioner step
# 30) then installs Node FOR THE RECIPES (the irreducible boundary; 50-agents.bats
# proves the recipes still get Node).
#
# This file proves that with three assertions, mirroring the INST-05
# negative-log-assertion pattern (10-installer.bats:180-216 — grep the tee'd
# transcript for a bad ordering, __fail on presence):
#   1. Static-link proof (RUST-01 re-asserted at the STAGED artifact): the staged
#      `agentlinux` bin has no dynamic interpreter (no PT_INTERP) and no NEEDED
#      shared libraries — it cannot depend on a Node runtime (or any libc) at
#      exec time.
#   2. No-Node-before-the-bin (the runtime ordering proof): the install transcript
#      shows the musl provisioner's own step markers (`agentlinux provision:
#      10-agent-user`, `20-sudoers`) BEFORE its `30-nodejs` marker — i.e. the
#      static bin is already executing multiple provisioner steps before
#      `nodejs.rs` installs Node. The bin ran with no Node present.
#   3. Recipes-still-get-Node (the boundary holds): `node` resolves AFTER provision
#      (nodejs.rs installed it for the recipes) — DIST-01 is scoped to "the
#      CLI/provisioner itself", not the recipes.
#
# Preconditions (set up by tests/docker/run.sh before bats runs): the DEFAULT
# (no-flag) run stages the static musl bin as the `agentlinux` command and runs
# the Rust `provision` as the provisioner, writing /var/log/agentlinux-install.log
# with the per-step markers this file greps. Under the AGENTLINUX_LEGACY_TS=1
# rollback the staged artifact is the TS `dist/index.js` Node script — the no-Node
# claim is specifically about the musl artifact, so the musl-only assertions skip
# with a loud reason in that regime (never a false-red on the rollback path).

load 'helpers/assertions'

LOG=/var/log/agentlinux-install.log

# Resolve the staged `agentlinux` command's real path + the shipped-artifact
# regime (musl vs legacy-TS), mirroring 10-installer.bats:82-95. The Rust
# provisioner (DIST-01, default) stages /opt/agentlinux/cli/<ver>/bin/agentlinux;
# the legacy TS provisioner stages /opt/agentlinux/cli/<ver>/dist/index.js.
__staged_cli_path() {
  local version
  version=${AGENTLINUX_VERSION:-$(jq -r .version /opt/agentlinux-src/plugin/catalog/catalog.json)}
  local staged_bin="/opt/agentlinux/cli/${version}/bin/agentlinux"
  if [[ -f "$staged_bin" ]]; then
    printf '%s' "$staged_bin"
  else
    printf '%s' "/opt/agentlinux/cli/${version}/dist/index.js"
  fi
}

@test "INST-08: staged agentlinux bin is a static executable (no interpreter, no NEEDED libs)" {
  # RUST-01 re-asserted at the STAGED artifact (T-58-08): a musl-static bin has
  # NO PT_INTERP program header and NO DT_NEEDED dynamic entries, so it cannot
  # load a dynamic linker or any shared library (including libc) at exec — there
  # is no path by which a Node runtime could be required to run it. A regression
  # that accidentally links libc (a `.dynamic` NEEDED, an INTERP header) is caught
  # here, not shipped.
  local cli
  cli=$(__staged_cli_path)

  # Legacy-TS rollback: the staged artifact is the dist/index.js Node script, not
  # a static ELF. The no-Node claim is specifically about the musl artifact, so
  # skip loudly in that regime (never a false-red on the GATE-05 rollback path).
  if [[ "$cli" == *dist/index.js ]]; then
    skip "INST-08: legacy-TS rollback regime (staged artifact is dist/index.js; the no-Node claim is scoped to the musl bin)"
  fi

  [[ -x "$cli" ]] \
    || __fail "INST-08" "staged agentlinux bin exists + is executable" "missing: $cli" "$LOG"

  # No PT_INTERP program header (no dynamic loader). `readelf -l` lists program
  # headers; a dynamically-linked ELF carries an INTERP segment naming ld.so.
  local interp_count
  interp_count=$(readelf -l "$cli" 2>/dev/null | grep -c 'INTERP' || true)
  [[ "$interp_count" -eq 0 ]] \
    || __fail "INST-08" "no PT_INTERP (no dynamic loader) in $cli" \
         "readelf -l shows $interp_count INTERP segment(s)" "$cli"

  # No DT_NEEDED dynamic entries (no shared-library dependency). `readelf -d`
  # dumps the .dynamic section; a static bin has none (or the section is absent
  # entirely — grep -c yields 0 either way).
  local needed_count
  needed_count=$(readelf -d "$cli" 2>/dev/null | grep -c 'NEEDED' || true)
  [[ "$needed_count" -eq 0 ]] \
    || __fail "INST-08" "no DT_NEEDED shared libs in $cli" \
         "readelf -d shows $needed_count NEEDED entr(y/ies): $(readelf -d "$cli" 2>/dev/null | grep 'NEEDED' | head -5)" "$cli"

  # Corroborating ldd assertion. glibc-ldd prints "not a dynamic executable";
  # musl's ldd (or a glibc ldd on a musl bin) prints "statically linked". Accept
  # either phrasing — the authoritative check is the readelf pair above; this is
  # the human-legible confirmation the acceptance oracle greps.
  local ldd_out
  ldd_out=$(ldd "$cli" 2>&1 || true)
  printf '%s' "$ldd_out" | grep -Eq 'not a dynamic executable|statically linked' \
    || __fail "INST-08" "ldd reports the bin static (not a dynamic executable / statically linked)" \
         "$ldd_out" "$cli"
}

@test "INST-08: the musl provisioner runs steps BEFORE nodejs.rs installs Node (no Node prerequisite)" {
  # The runtime ordering proof (mirrors the INST-05 log-grep pattern): the static
  # provisioner writes its per-step markers to the transcript AS IT RUNS. Steps
  # 10-agent-user + 20-sudoers appear BEFORE step 30-nodejs — so the bin executed
  # (and completed two full provisioner steps) while Node was still absent. Node
  # exists ONLY after nodejs.rs (step 30) runs the NodeSource install; the bin
  # that drove steps 10/20 therefore needed no Node.
  local cli
  cli=$(__staged_cli_path)
  if [[ "$cli" == *dist/index.js ]]; then
    skip "INST-08: legacy-TS rollback regime (the Bash entrypoint emits different markers; the pre-Node ordering proof is scoped to the musl provisioner)"
  fi

  [[ -f "$LOG" ]] \
    || __fail "INST-08" "$LOG exists (provisioner ran + tee'd its transcript)" "not found" "$LOG"

  # The three ordering markers the musl provisioner emits (cmd/provision.rs
  # run_steps: log::line "agentlinux provision: <NN>-<name>"). grep -n gives the
  # transcript line number so we can assert 10/20 precede 30.
  local ln_agent ln_sudoers ln_nodejs
  ln_agent=$(grep -n 'agentlinux provision: 10-agent-user' "$LOG" | head -1 | cut -d: -f1)
  ln_sudoers=$(grep -n 'agentlinux provision: 20-sudoers' "$LOG" | head -1 | cut -d: -f1)
  ln_nodejs=$(grep -n 'agentlinux provision: 30-nodejs' "$LOG" | head -1 | cut -d: -f1)

  # All three markers must be present — a missing marker means the static bin did
  # NOT drive the provisioner (e.g. a Bash-entrypoint transcript slipped in), so
  # this proof would be a tautology. __fail (not skip) so a broken ordering is
  # loud.
  [[ -n "$ln_agent" && -n "$ln_sudoers" && -n "$ln_nodejs" ]] \
    || __fail "INST-08" \
         "musl provisioner step markers (10-agent-user, 20-sudoers, 30-nodejs) present in transcript" \
         "10=${ln_agent:-MISSING} 20=${ln_sudoers:-MISSING} 30=${ln_nodejs:-MISSING}" \
         "$LOG"

  # The ordering assertion: steps 10 + 20 (the static bin already running) precede
  # step 30 (the point Node gets installed). If 30-nodejs preceded 10/20 the proof
  # would be void.
  [[ "$ln_agent" -lt "$ln_nodejs" && "$ln_sudoers" -lt "$ln_nodejs" ]] \
    || __fail "INST-08" \
         "provisioner steps 10-agent-user + 20-sudoers run BEFORE 30-nodejs (bin ran pre-Node)" \
         "10-agent-user@${ln_agent} 20-sudoers@${ln_sudoers} 30-nodejs@${ln_nodejs}" \
         "$LOG"

  # Negative assertion: no node/npm/pnpm INVOCATION recorded before the first
  # provisioner step marker. The transcript's head (everything above the
  # 10-agent-user line) is the pre-step preamble — it must not show a node/npm/pnpm
  # command having run (which would mean a Node runtime was required to reach the
  # provisioner). This mirrors INST-05's "no bad-string in the log head" negative
  # grep. We scope to a word-boundary command token to avoid matching incidental
  # substrings (e.g. "nodejs" in the 30-nodejs marker further down).
  local preamble hits
  preamble=$(sed -n "1,$((ln_agent - 1))p" "$LOG" 2>/dev/null || true)
  hits=$(printf '%s\n' "$preamble" | grep -nE '(^|[^[:alnum:]_/])(node|npm|pnpm)([^[:alnum:]_]|$)' || true)
  [[ -z "$hits" ]] \
    || __fail "INST-08" \
         "no node/npm/pnpm invocation in the transcript BEFORE the provisioner's first step (no Node prerequisite)" \
         "$hits" \
         "$LOG"
}

@test "INST-08: node is present AFTER provision (recipes still get Node — the irreducible boundary)" {
  # DIST-01 is scoped to "the CLI/provisioner ITSELF" — the ~25 recipes
  # (catalog/agents/*/install.sh) still npm/apt/curl-install their agents, and
  # nodejs.rs provisions Node 22 LTS FOR THEM. This light positive assertion
  # proves the boundary holds: after provision, `node` resolves. (50-agents.bats
  # is the deeper proof that the recipes actually consume it; this file references
  # that boundary rather than re-testing recipe installs.)
  #
  # This assertion is regime-independent: BOTH the musl default and the legacy-TS
  # rollback provision Node for the recipes, so it runs in either harness mode.
  run bash -lc 'command -v node && node --version'
  assert_exit_zero "INST-08"
  printf '%s' "${output:-}" | grep -Eq '^v[0-9]+' \
    || __fail "INST-08" "node --version prints a vN.N.N after provision (recipes get Node)" \
         "${output:-<empty>}" "$LOG"
}
