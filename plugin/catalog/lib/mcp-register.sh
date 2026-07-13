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
# all of them. Currently targeted: claude-code, codex, gemini-cli, opencode,
# qwen-code (the five shipped agents with remote-http MCP support).
#
# Never-bake keystone (CAT-02 / ENABLE-02): the credential is NEVER written to
# disk. For the four agents that persist headers, we store an env-var REFERENCE —
# the literal string `Bearer ${SECRET_ENV}`, which the agent expands at
# server-launch time from its own environment (verified: Claude Code stores the
# unexpanded `${VAR}`). Codex keeps the token off disk natively via
# `bearer_token_env_var`. Each register asserts its reference landed, so a bash
# mis-expansion (which would bake an empty/real value) fails loud.
#
# Order note (WIRE-01 corner case): fan-out is applied at the MCP entry's install
# time to agents present THEN. An agent installed LATER does not auto-receive the
# registration — re-run `agentlinux install <mcp-id>` to re-fan-out.
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

# ---- generic JSON config writers (gemini / opencode / qwen) -----------------
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
    mv "$tmp" "$cfg"
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
    mv "$tmp" "$cfg"
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

_al_mcp_claude_register() { # <server> <url> <ref>
  local server=$1 url=$2 ref=$3
  # remove-then-add → idempotent AND guarantees the pinned url/header win.
  claude mcp remove "$server" --scope user >/dev/null 2>&1 || true
  claude mcp add --transport http "$server" "$url" --scope user \
    --header "Authorization: ${ref}" >/dev/null 2>&1 \
    || return 1
}
_al_mcp_claude_deregister() { # <server>
  claude mcp remove "$1" --scope user >/dev/null 2>&1 || true
}

# ---- codex (TOML, marker-delimited block; token OFF disk) -------------------
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
    mv "$tmp" "$cfg"
  else
    rm -f "$tmp"
    return 1
  fi
}
_al_mcp_codex_register() { # <server> <url> <secret_env>
  # `url` selects codex's StreamableHTTP transport and `bearer_token_env_var` sends
  # `Authorization: Bearer $<env>` — the token stays in the environment, never on
  # disk. Confirmed against codex source at tag rust-v0.142.3: HTTP MCP has
  # graduated out of experimental, so NO `experimental_use_rmcp_client` flag is
  # needed (and codex rejects an inline `bearer_token`, which is why we use the
  # env-var form). `server` is a schema-constrained bare TOML key ([a-z0-9-]).
  local server=$1 url=$2 env=$3 cfg
  cfg=$(_al_mcp_codex_cfg)
  mkdir -p "$(dirname "$cfg")" || return 1
  _al_mcp_codex_deregister "$server" || return 1 # strip any prior block first
  {
    printf '\n# >>> agentlinux-mcp:%s >>>\n' "$server"
    printf '[mcp_servers.%s]\n' "$server"
    printf 'url = "%s"\n' "$url"
    printf 'bearer_token_env_var = "%s"\n' "$env"
    printf '# <<< agentlinux-mcp:%s <<<\n' "$server"
  } >>"$cfg" || return 1
}
_al_mcp_codex_has() { # <server>
  local cfg
  cfg=$(_al_mcp_codex_cfg)
  [[ -f "$cfg" ]] && grep -q "# >>> agentlinux-mcp:${1} >>>" "$cfg"
}

# ---- gemini-cli / qwen-code (settings.json, httpUrl+headers) ----------------
_al_mcp_gemini_present() { command -v gemini >/dev/null 2>&1; }
_al_mcp_gemini_cfg() { printf '%s/.gemini/settings.json' "$(_al_mcp_home)"; }
_al_mcp_qwen_present() { command -v qwen >/dev/null 2>&1; }
_al_mcp_qwen_cfg() { printf '%s/.qwen/settings.json' "$(_al_mcp_home)"; }

# httpUrl+headers object shared by the two gemini-family agents.
_al_mcp_gemini_obj() { # <url> <ref>
  jq -n --arg u "$1" --arg a "$2" '{httpUrl: $u, headers: {Authorization: $a}}'
}

# ---- opencode (opencode.json, type:remote) ----------------------------------
_al_mcp_opencode_present() { command -v opencode >/dev/null 2>&1; }
_al_mcp_opencode_cfg() { printf '%s/.config/opencode/opencode.json' "$(_al_mcp_home)"; }
_al_mcp_opencode_obj() { # <url> <ref>
  jq -n --arg u "$1" --arg a "$2" \
    '{type: "remote", url: $u, enabled: true, headers: {Authorization: $a}}'
}

# ---- public API -------------------------------------------------------------

# al_mcp_register_http <server> <url> <secret_env>
# Fan out an HTTPS remote MCP registration to every present MCP-capable agent,
# using an env-var reference for the bearer token (never the literal). Echoes one
# "<server>: registered into <agent>" line per target and sets AL_MCP_TARGETS to
# the space-separated agent list. Returns non-zero if a present agent fails to
# register or its never-bake reference did not land.
al_mcp_register_http() {
  local server=$1 url=$2 env=$3 ref
  AL_MCP_TARGETS=""
  # Literal reference string: `Bearer ${SECRET_ENV}` (the \$ keeps $ literal so
  # the caller's shell does not expand it; the agent expands it at launch time).
  ref="Bearer \${${env}}"

  if _al_mcp_claude_present; then
    _al_mcp_claude_register "$server" "$url" "$ref" \
      || {
        al_mcp_die "claude-code register failed"
        return 1
      }
    jq -e --arg s "$server" --arg r "$ref" \
      '.mcpServers[$s].headers.Authorization == $r' "$(_al_mcp_claude_cfg)" >/dev/null 2>&1 \
      || {
        al_mcp_die "claude-code: env-var reference did not land (never-bake)"
        return 1
      }
    AL_MCP_TARGETS+="claude-code "
    echo "${server}: registered into claude-code (~/.claude.json)"
  fi

  if _al_mcp_codex_present; then
    _al_mcp_codex_register "$server" "$url" "$env" \
      || {
        al_mcp_die "codex register failed"
        return 1
      }
    grep -q "bearer_token_env_var = \"${env}\"" "$(_al_mcp_codex_cfg)" \
      || {
        al_mcp_die "codex: bearer_token_env_var did not land (never-bake)"
        return 1
      }
    AL_MCP_TARGETS+="codex "
    echo "${server}: registered into codex (~/.codex/config.toml, token off-disk)"
  fi

  if _al_mcp_gemini_present; then
    _al_mcp_json_set "$(_al_mcp_gemini_cfg)" ".mcpServers" "$server" "$(_al_mcp_gemini_obj "$url" "$ref")" \
      || {
        al_mcp_die "gemini-cli register failed"
        return 1
      }
    jq -e --arg s "$server" --arg r "$ref" \
      '.mcpServers[$s].headers.Authorization == $r' "$(_al_mcp_gemini_cfg)" >/dev/null 2>&1 \
      || {
        al_mcp_die "gemini-cli: env-var reference did not land (never-bake)"
        return 1
      }
    AL_MCP_TARGETS+="gemini-cli "
    echo "${server}: registered into gemini-cli (~/.gemini/settings.json)"
  fi

  if _al_mcp_qwen_present; then
    _al_mcp_json_set "$(_al_mcp_qwen_cfg)" ".mcpServers" "$server" "$(_al_mcp_gemini_obj "$url" "$ref")" \
      || {
        al_mcp_die "qwen-code register failed"
        return 1
      }
    jq -e --arg s "$server" --arg r "$ref" \
      '.mcpServers[$s].headers.Authorization == $r' "$(_al_mcp_qwen_cfg)" >/dev/null 2>&1 \
      || {
        al_mcp_die "qwen-code: env-var reference did not land (never-bake)"
        return 1
      }
    AL_MCP_TARGETS+="qwen-code "
    echo "${server}: registered into qwen-code (~/.qwen/settings.json)"
  fi

  if _al_mcp_opencode_present; then
    _al_mcp_json_set "$(_al_mcp_opencode_cfg)" ".mcp" "$server" "$(_al_mcp_opencode_obj "$url" "$ref")" \
      || {
        al_mcp_die "opencode register failed"
        return 1
      }
    jq -e --arg s "$server" --arg r "$ref" \
      '.mcp[$s].headers.Authorization == $r' "$(_al_mcp_opencode_cfg)" >/dev/null 2>&1 \
      || {
        al_mcp_die "opencode: env-var reference did not land (never-bake)"
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
  _al_mcp_claude_present && _al_mcp_claude_deregister "$server"
  _al_mcp_codex_present && { _al_mcp_codex_deregister "$server" || return 1; }
  _al_mcp_gemini_present && { _al_mcp_json_del "$(_al_mcp_gemini_cfg)" ".mcpServers" "$server" || return 1; }
  _al_mcp_qwen_present && { _al_mcp_json_del "$(_al_mcp_qwen_cfg)" ".mcpServers" "$server" || return 1; }
  _al_mcp_opencode_present && { _al_mcp_json_del "$(_al_mcp_opencode_cfg)" ".mcp" "$server" || return 1; }
  return 0
}

# al_mcp_assert_absent <server>
# Truth check for uninstall: fail if any present agent's config still carries the
# server. Returns non-zero (with a message) on residue.
al_mcp_assert_absent() {
  local server=$1
  if _al_mcp_claude_present && _al_mcp_json_has "$(_al_mcp_claude_cfg)" ".mcpServers" "$server"; then
    al_mcp_die "residue: ${server} still in claude-code config"
    return 1
  fi
  if _al_mcp_codex_present && _al_mcp_codex_has "$server"; then
    al_mcp_die "residue: ${server} still in codex config"
    return 1
  fi
  if _al_mcp_gemini_present && _al_mcp_json_has "$(_al_mcp_gemini_cfg)" ".mcpServers" "$server"; then
    al_mcp_die "residue: ${server} still in gemini-cli config"
    return 1
  fi
  if _al_mcp_qwen_present && _al_mcp_json_has "$(_al_mcp_qwen_cfg)" ".mcpServers" "$server"; then
    al_mcp_die "residue: ${server} still in qwen-code config"
    return 1
  fi
  if _al_mcp_opencode_present && _al_mcp_json_has "$(_al_mcp_opencode_cfg)" ".mcp" "$server"; then
    al_mcp_die "residue: ${server} still in opencode config"
    return 1
  fi
  return 0
}
