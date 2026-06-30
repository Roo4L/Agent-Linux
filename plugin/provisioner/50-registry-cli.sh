#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/provisioner/50-registry-cli.sh — stage agentlinux CLI + catalog snapshot.
#
# Sourced by plugin/bin/agentlinux-install. Inherits strict-mode (errexit /
# nounset / pipefail), ERR trap, and the tee redirect to the install log from
# the entrypoint; this fragment therefore MUST NOT set its own strict-mode
# flags.
#
# Requirements satisfied:
#   CLI-01 — `agentlinux` on agent's PATH (symlink into .npm-global/bin/)
#   CAT-01 / CAT-03 — catalog + recipes staged under /opt/agentlinux/catalog/
#   CAT-02 — state/installed.d/ created empty; no agents installed here
#   INST-02 — re-runnable (ensure_dir idempotent; cp is byte-stable when src
#             unchanged; ln -sfn is idempotent when target is already correct)
#
# Ordering: runs AFTER 30-nodejs.sh + 40-path-wiring.sh — numeric dispatch
# 10 -> 30 -> 40 -> 50. The .npm-global/bin directory must exist (Phase 3)
# before we drop the symlink; /etc/agentlinux.env must exist (Phase 2) as
# the recipe-env source of truth that runner.ts mirrors.
#
# Idempotency invariants (INST-02):
#   - ensure_dir creates OR re-asserts mode+ownership on re-run
#   - cp -R then chmod re-run produces byte-identical /opt/agentlinux/ tree
#     when src is byte-identical (images build dist/ once per release)
#   - ln -sfn (force + no-deref) is a no-op when the symlink already points
#     at the target; overwrites without chasing existing symlinks

log_info "50-registry-cli: starting"

# Resolved install user + home (AL-50/AL-59). The CLI symlink, .npm-global/bin
# dir, and state-dir ownership all derive from the resolved user so an alternate
# install user (INSTALL_USER != agent) gets a working `agentlinux` on its PATH.
_AL_USER="${INSTALL_USER:-agent}"
_AL_HOME="/home/${_AL_USER}"

readonly CLI_STAGE_DIR="/opt/agentlinux/cli/${AGENTLINUX_VERSION}"
readonly CATALOG_STAGE_DIR="/opt/agentlinux/catalog/${AGENTLINUX_VERSION}"
readonly STATE_DIR="/opt/agentlinux/state"
readonly SYMLINK="${_AL_HOME}/.npm-global/bin/agentlinux"

# Source directories: the installer was unpacked to a sibling of BIN_DIR
# (BIN_DIR=plugin/bin, so plugin/ is its parent; cli/ and catalog/ are
# siblings of bin/). SC2155 split so cmdsub failures propagate to ERR trap.
#
# We stage three things from plugin/cli/:
#   dist/         — tsc output (runtime JS)
#   node_modules/ — production deps (ajv, commander, semver, ...)
#   package.json  — ESM loader needs "type": "module"; also declares deps so
#                   Node's resolver finds node_modules in a sibling dir.
# All three MUST be present before the provisioner runs; builds (Docker
# multi-stage / release tarball) are responsible for producing the bundle.
CLI_BUNDLE_SRC="$(cd "$BIN_DIR/../cli" && pwd)"
readonly CLI_BUNDLE_SRC
CATALOG_SRC="$(cd "$BIN_DIR/../catalog" && pwd)"
readonly CATALOG_SRC

# Sanity: the build pipeline (Docker image build; release tarball pipeline)
# must have populated plugin/cli/{dist,node_modules,package.json} and
# plugin/catalog/. If not, fail clearly so operators know the release
# artifact is malformed, not a runtime bug.
if [[ ! -f "$CLI_BUNDLE_SRC/dist/index.js" ]]; then
  log_error "CLI dist/index.js missing at ${CLI_BUNDLE_SRC}/dist — release tarball malformed?"
  return 1
fi
if [[ ! -d "$CLI_BUNDLE_SRC/node_modules" ]]; then
  log_error "CLI node_modules missing at ${CLI_BUNDLE_SRC}/node_modules — release tarball malformed?"
  return 1
fi
if [[ ! -f "$CLI_BUNDLE_SRC/package.json" ]]; then
  log_error "CLI package.json missing at ${CLI_BUNDLE_SRC}/package.json — release tarball malformed?"
  return 1
fi
if [[ ! -f "$CATALOG_SRC/catalog.json" ]]; then
  log_error "catalog.json missing at ${CATALOG_SRC} — release tarball malformed?"
  return 1
fi

# Stage CLI under versioned dir (multiple versions can coexist at runtime).
# Layout: /opt/agentlinux/cli/<ver>/{dist/,node_modules/,package.json}
# Node ESM resolver starts at dist/index.js, walks up to find sibling
# node_modules/, then resolves 'commander' etc. package.json's "type":
# "module" at the versioned-dir level makes the *.js files in dist/ ESM.
ensure_dir /opt/agentlinux 0755 root:root
ensure_dir "$(dirname "$CLI_STAGE_DIR")" 0755 root:root
ensure_dir "$CLI_STAGE_DIR" 0755 root:root
# cp -R followed by chmod is simpler than rsync for our size class.
# cp dist/. and node_modules/. targeting specific subdirs avoids copying
# stray top-level files (tsconfig.test.json, biome.json, etc.).
ensure_dir "$CLI_STAGE_DIR/dist" 0755 root:root
ensure_dir "$CLI_STAGE_DIR/node_modules" 0755 root:root
cp -R "$CLI_BUNDLE_SRC/dist"/. "$CLI_STAGE_DIR/dist"/
cp -R "$CLI_BUNDLE_SRC/node_modules"/. "$CLI_STAGE_DIR/node_modules"/
install -m 0644 -o root -g root "$CLI_BUNDLE_SRC/package.json" "$CLI_STAGE_DIR/package.json"
chmod -R u=rwX,go=rX "$CLI_STAGE_DIR"
# The entrypoint needs exec for all users; shebang handles node invocation.
chmod 0755 "$CLI_STAGE_DIR/dist/index.js"

# Stage catalog snapshot. In Phase 6 the release pipeline publishes
# catalog-<version>.json as a sibling of the tarball (CAT-05) and the
# installer may point us at that sibling; Phase 4 stages from the tree
# shipped inside the tarball.
ensure_dir "$CATALOG_STAGE_DIR" 0755 root:root
cp -R "$CATALOG_SRC"/. "$CATALOG_STAGE_DIR"/
chmod -R u=rwX,go=rX "$CATALOG_STAGE_DIR"
# install.sh / uninstall.sh must be executable for the CLI dispatcher.
find "$CATALOG_STAGE_DIR/agents" -name '*.sh' -exec chmod 0755 {} +

# State directory — owned by the install user (the CLI runs as that user) so it
# can write sentinels to installed.d/<id>.json via atomic rename. CAT-02
# invariant: installed.d/ is created EMPTY — no provisioner in this phase or
# prior calls `agentlinux install`. A fresh install has zero agents.
ensure_dir "$STATE_DIR" 0755 "${_AL_USER}:${_AL_USER}"
ensure_dir "$STATE_DIR/installed.d" 0755 "${_AL_USER}:${_AL_USER}"

# Symlink `agentlinux` into the agent's PATH.
# - ln -sfn = force + no-deref: atomic replacement of existing symlink;
#   does NOT chase through an existing symlink to the target (important
#   when upgrading over an old 0.2.x install where symlink may exist).
# - chown -h = change the symlink itself, not its target.
# The install user's .npm-global/bin dir was created by Phase 3's 30-nodejs.sh.
# Its presence on PATH was wired by Phase 3's 40-path-wiring.sh extension.
ensure_dir "${_AL_HOME}/.npm-global/bin" 0755 "${_AL_USER}:${_AL_USER}"
ln -sfn "$CLI_STAGE_DIR/dist/index.js" "$SYMLINK"
chown -h "${_AL_USER}:${_AL_USER}" "$SYMLINK"
log_info "symlinked ${SYMLINK} -> ${CLI_STAGE_DIR}/dist/index.js"

# Sanity: confirm the symlink resolves and is executable AS THE INSTALL USER
# (T-04-15 mitigation: a broken symlink here would silently break CLI-01 and
# every downstream AGT-XX test in Phase 5).
#
# NOTE on as_user invocation shape: plugin/lib/as_user.sh builds the sudo line
# `sudo -u "$user" -H -E -- "$@"` — the `--` terminator is built in. Callers
# MUST pass the command + args verbatim without prepending their own `--`;
# a double-dash (`as_user "$u" -- test …`) resolves to `sudo … -- -- test …`,
# which sudo parses as "command = --" → "command not found" exit 1.
if ! as_user "$_AL_USER" test -x "$SYMLINK"; then
  log_error "agentlinux symlink not executable as install user '${_AL_USER}' (CLI-01 regression)"
  return 1
fi

log_info "50-registry-cli: done (CLI-01 + CAT-01..04 + INST-02 staging complete)"
