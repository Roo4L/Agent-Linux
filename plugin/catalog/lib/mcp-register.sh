#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/catalog/lib/mcp-register.sh — ENABLE-02 shared cross-agent MCP helper.
#
# SOURCED, NOT EXECUTED. A remote-http MCP recipe (agents/<id>/install.sh) sources
# this file via:
#
#   source "${AGENTLINUX_CATALOG_DIR}/lib/mcp-register.sh"
#
# then calls al_mcp_register_http (install) / al_mcp_deregister (uninstall). The
# provisioner stages this whole `lib/` subdir to /opt/agentlinux/catalog/<ver>/lib/
# automatically (50-registry-cli.sh copies the catalog tree with `cp -R`).
#
# Purpose (WIRE-01 for MCP servers): a Model Context Protocol server is a
# cross-agent resource — every installed coding agent that speaks MCP can use it.
# So registration fans OUT to each MCP-capable agent that is present, writing that
# agent's native config format, and `remove` tears the registration down across
# all of them. Currently targeted: claude-code, codex, antigravity-cli, opencode,
# qwen-code (the five shipped agents with remote-http MCP support).
#
# Thin-installer keystone (ADR-017 / CAT-02): an MCP entry registers the BARE
# server (URL only) into each client and bakes NO credential — no literal token,
# no env-var reference, no auth header. The user authenticates IN-CLIENT afterwards
# (the client's own OAuth prompt on first use for a remote server). There is thus
# no secret to leak by construction; `remove` deregisters symmetrically.
#
# Order note (WIRE-02): fan-out is applied at the MCP entry's install time to
# agents present then. When a coding agent is installed later, the CLI re-runs
# each installed provider's idempotent rewire recipe to converge the new target.
#
# Deliberately NOT `set -euo pipefail` at file top: sourced into recipes that own
# their own shell options. Each function is individually robust and returns
# non-zero on failure so the sourcing recipe can abort cleanly.

# One-line failure helper. Single-quoted format keeps any '%' in "$*" inert.
al_mcp_die() {
  printf 'mcp-register: %s\n' "$*" >&2
  return 1
}

# Home dir the agent configs live under (agent-owned; never root).
_al_mcp_home() {
  printf '%s' "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"
}

# ---- generic JSON config writers (antigravity / opencode / qwen) ------------
# SECURITY INVARIANT: the <parent-jq-path> argument is spliced into the jq PROGRAM
# text (not passed as data), so it MUST be a code-literal from a call site inside
# this file (`.mcpServers`, `.mcp`) — NEVER a catalog field or any external value.
# `server` is always passed via `--arg` (data), so it carries no injection risk.
# _al_mcp_json_set <cfg> <parent-jq-path> <server> <value-json>
# Idempotent, atomic (mktemp+mv), preserves the rest of the file. Creates a
# minimal {} document when the config is absent/empty.
_al_mcp_json_set() {
  local cfg=$1 parent=$2 server=$3 val=$4 tmp
  mkdir -p "$(dirname "$cfg")" || return 1
  [[ -s "$cfg" ]] || printf '{}\n' >"$cfg"
  tmp=$(mktemp "${cfg}.tmp.XXXXXX") || return 1
  if jq --arg s "$server" --argjson v "$val" \
    "$parent = (($parent // {}) | .[\$s] = \$v)" "$cfg" >"$tmp" 2>/dev/null; then
    if mv "$tmp" "$cfg"; then
      :
    else
      rm -f "$tmp"
      return 1
    fi
  else
    rm -f "$tmp"
    return 1
  fi
}

# _al_mcp_json_del <cfg> <parent-jq-path> <server>
_al_mcp_json_del() {
  local cfg=$1 parent=$2 server=$3 tmp
  [[ -f "$cfg" ]] || return 0
  tmp=$(mktemp "${cfg}.tmp.XXXXXX") || return 1
  if jq --arg s "$server" \
    "if ($parent | type) == \"object\" then $parent |= del(.[\$s]) else . end" \
    "$cfg" >"$tmp" 2>/dev/null; then
    if mv "$tmp" "$cfg"; then
      :
    else
      rm -f "$tmp"
      return 1
    fi
  else
    rm -f "$tmp"
    return 1
  fi
}

# _al_mcp_json_has <cfg> <parent-jq-path> <server>  → 0 if the key is present.
_al_mcp_json_has() {
  local cfg=$1 parent=$2 server=$3
  [[ -f "$cfg" ]] || return 1
  jq -e --arg s "$server" "($parent // {}) | has(\$s)" "$cfg" >/dev/null 2>&1
}

# ---- claude-code ------------------------------------------------------------
_al_mcp_claude_present() { command -v claude >/dev/null 2>&1; }
_al_mcp_claude_cfg() { printf '%s/.claude.json' "$(_al_mcp_home)"; }

_al_mcp_claude_register() { # <server> <url>
  local server=$1 url=$2
  # remove-then-add → idempotent AND guarantees the pinned url wins. Bare URL, no
  # --header (ADR-017): the user completes OAuth in-client on first use.
  claude mcp remove "$server" --scope user >/dev/null 2>&1 || true
  claude mcp add --transport http "$server" "$url" --scope user >/dev/null 2>&1 \
    || return 1
}
_al_mcp_claude_deregister() { # <server>
  claude mcp remove "$1" --scope user >/dev/null 2>&1 || true
}

# ---- codex (TOML, marker-delimited block; bare url, no token) ---------------
_al_mcp_codex_present() { command -v codex >/dev/null 2>&1; }
_al_mcp_codex_cfg() { printf '%s/.codex/config.toml' "$(_al_mcp_home)"; }

_al_mcp_codex_deregister() { # <server>
  local server=$1 cfg tmp
  cfg=$(_al_mcp_codex_cfg)
  [[ -f "$cfg" ]] || return 0
  tmp=$(mktemp "${cfg}.tmp.XXXXXX") || return 1
  # Delete the inclusive marker block. server is a bare TOML key (a-z0-9-), so it
  # carries no sed-address metacharacters.
  if sed "/# >>> agentlinux-mcp:${server} >>>/,/# <<< agentlinux-mcp:${server} <<</d" \
    "$cfg" >"$tmp" 2>/dev/null; then
    if mv "$tmp" "$cfg"; then
      :
    else
      rm -f "$tmp"
      return 1
    fi
  else
    rm -f "$tmp"
    return 1
  fi
}
_al_mcp_codex_register() { # <server> <url>
  # `url` selects codex's StreamableHTTP transport. Thin installer (ADR-017): we
  # register only the bare URL — no token/bearer field. The user authenticates
  # in-client (codex `codex mcp login`, or the browser OAuth the server drives).
  # Confirmed against codex source at tag rust-v0.142.3: HTTP MCP has graduated
  # out of experimental (no `experimental_use_rmcp_client` flag needed). `server`
  # is a schema-constrained bare TOML key ([a-z0-9-]).
  local server=$1 url=$2 cfg
  cfg=$(_al_mcp_codex_cfg)
  mkdir -p "$(dirname "$cfg")" || return 1
  _al_mcp_codex_deregister "$server" || return 1 # strip any prior block first
  {
    printf '\n# >>> agentlinux-mcp:%s >>>\n' "$server"
    printf '[mcp_servers.%s]\n' "$server"
    printf 'url = "%s"\n' "$url"
    printf '# <<< agentlinux-mcp:%s <<<\n' "$server"
  } >>"$cfg" || return 1
}
_al_mcp_codex_has() { # <server>
  local cfg
  cfg=$(_al_mcp_codex_cfg)
  [[ -f "$cfg" ]] && grep -q "# >>> agentlinux-mcp:${1} >>>" "$cfg"
}

# ---- antigravity-cli / qwen-code (JSON, bare remote URL) --------------------
_al_mcp_antigravity_present() { command -v agy >/dev/null 2>&1; }
_al_mcp_antigravity_cfg() { printf '%s/.gemini/config/mcp_config.json' "$(_al_mcp_home)"; }
_al_mcp_qwen_present() { command -v qwen >/dev/null 2>&1; }
_al_mcp_qwen_cfg() { printf '%s/.qwen/settings.json' "$(_al_mcp_home)"; }

# Antigravity's modern remote-MCP schema uses serverUrl (no auth — ADR-017).
_al_mcp_antigravity_obj() { # <url>
  jq -n --arg u "$1" '{serverUrl: $u}'
}

# Qwen retains its legacy settings schema and uses httpUrl.
_al_mcp_qwen_obj() { # <url>
  jq -n --arg u "$1" '{httpUrl: $u}'
}

# ---- opencode (opencode.json, type:remote) ----------------------------------
_al_mcp_opencode_present() { command -v opencode >/dev/null 2>&1; }
_al_mcp_opencode_cfg() { printf '%s/.config/opencode/opencode.json' "$(_al_mcp_home)"; }
_al_mcp_opencode_obj() { # <url>
  jq -n --arg u "$1" '{type: "remote", url: $u, enabled: true}'
}

# ---- public API -------------------------------------------------------------

# al_mcp_register_http <server> <url>
# Fan out a BARE remote MCP registration (URL only, NO credential — ADR-017 thin
# installer) to every present MCP-capable agent. The user authenticates in-client
# afterwards. Echoes one "<server>: registered into <agent>" line per target and
# sets AL_MCP_TARGETS to the space-separated agent list. Returns non-zero if a
# present agent fails to register or the entry did not land.
al_mcp_register_http() {
  local server=$1 url=$2
  AL_MCP_TARGETS=""

  if _al_mcp_claude_present; then
    _al_mcp_claude_register "$server" "$url" \
      || {
        al_mcp_die "claude-code register failed"
        return 1
      }
    _al_mcp_json_has "$(_al_mcp_claude_cfg)" ".mcpServers" "$server" \
      || {
        al_mcp_die "claude-code: entry did not land"
        return 1
      }
    AL_MCP_TARGETS+="claude-code "
    echo "${server}: registered into claude-code (~/.claude.json)"
  fi

  if _al_mcp_codex_present; then
    _al_mcp_codex_register "$server" "$url" \
      || {
        al_mcp_die "codex register failed"
        return 1
      }
    _al_mcp_codex_has "$server" \
      || {
        al_mcp_die "codex: entry did not land"
        return 1
      }
    AL_MCP_TARGETS+="codex "
    echo "${server}: registered into codex (~/.codex/config.toml)"
  fi

  if _al_mcp_antigravity_present; then
    _al_mcp_json_set "$(_al_mcp_antigravity_cfg)" ".mcpServers" "$server" "$(_al_mcp_antigravity_obj "$url")" \
      || {
        al_mcp_die "antigravity-cli register failed"
        return 1
      }
    AL_MCP_TARGETS+="antigravity-cli "
    echo "${server}: registered into antigravity-cli (~/.gemini/config/mcp_config.json)"
  fi

  if _al_mcp_qwen_present; then
    _al_mcp_json_set "$(_al_mcp_qwen_cfg)" ".mcpServers" "$server" "$(_al_mcp_qwen_obj "$url")" \
      || {
        al_mcp_die "qwen-code register failed"
        return 1
      }
    AL_MCP_TARGETS+="qwen-code "
    echo "${server}: registered into qwen-code (~/.qwen/settings.json)"
  fi

  if _al_mcp_opencode_present; then
    _al_mcp_json_set "$(_al_mcp_opencode_cfg)" ".mcp" "$server" "$(_al_mcp_opencode_obj "$url")" \
      || {
        al_mcp_die "opencode register failed"
        return 1
      }
    AL_MCP_TARGETS+="opencode "
    echo "${server}: registered into opencode (~/.config/opencode/opencode.json)"
  fi

  # space-separated token list consumed by the caller; drop the trailing separator.
  AL_MCP_TARGETS="${AL_MCP_TARGETS% }"
  [[ -n "$AL_MCP_TARGETS" ]]
}

# al_mcp_deregister <server>
# Remove the registration from every present agent's config. Idempotent (a no-op
# where the entry is absent). Returns non-zero only if a removal write fails;
# after it returns 0, al_mcp_assert_absent verifies no residue.
al_mcp_deregister() {
  local server=$1
  if _al_mcp_claude_present; then
    _al_mcp_claude_deregister "$server"
  elif [[ -f "$(_al_mcp_claude_cfg)" ]]; then
    _al_mcp_json_del "$(_al_mcp_claude_cfg)" ".mcpServers" "$server" || return 1
  fi
  [[ -f "$(_al_mcp_codex_cfg)" ]] && { _al_mcp_codex_deregister "$server" || return 1; }
  if _al_mcp_json_has "$(_al_mcp_antigravity_cfg)" ".mcpServers" "$server"; then
    _al_mcp_json_del "$(_al_mcp_antigravity_cfg)" ".mcpServers" "$server" || return 1
  fi
  if _al_mcp_json_has "$(_al_mcp_qwen_cfg)" ".mcpServers" "$server"; then
    _al_mcp_json_del "$(_al_mcp_qwen_cfg)" ".mcpServers" "$server" || return 1
  fi
  if _al_mcp_json_has "$(_al_mcp_opencode_cfg)" ".mcp" "$server"; then
    _al_mcp_json_del "$(_al_mcp_opencode_cfg)" ".mcp" "$server" || return 1
  fi
  return 0
}

# al_mcp_assert_absent <server>
# Truth check for uninstall: fail if any present agent's config still carries the
# server. Returns non-zero (with a message) on residue.
al_mcp_assert_absent() {
  local server=$1
  if _al_mcp_json_has "$(_al_mcp_claude_cfg)" ".mcpServers" "$server"; then
    al_mcp_die "residue: ${server} still in claude-code config"
    return 1
  fi
  if _al_mcp_codex_has "$server"; then
    al_mcp_die "residue: ${server} still in codex config"
    return 1
  fi
  if _al_mcp_json_has "$(_al_mcp_antigravity_cfg)" ".mcpServers" "$server"; then
    al_mcp_die "residue: ${server} still in antigravity-cli config"
    return 1
  fi
  if _al_mcp_json_has "$(_al_mcp_qwen_cfg)" ".mcpServers" "$server"; then
    al_mcp_die "residue: ${server} still in qwen-code config"
    return 1
  fi
  if _al_mcp_json_has "$(_al_mcp_opencode_cfg)" ".mcp" "$server"; then
    al_mcp_die "residue: ${server} still in opencode config"
    return 1
  fi
  return 0
}
