#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# plugin/lib/idempotency.sh — grep-before-mutate primitives.
#
# Every state change in the installer goes through one of these helpers.
# Blind `echo >> file` is forbidden: it breaks INST-02 (the installer MUST
# converge across re-runs) and produces drift that INST-05 (no EACCES in the
# transcript on second run) will later flag. See 02-RESEARCH.md "Pattern 2"
# for the design rationale and the marker-block awk-replace algorithm.
#
# Source-once guard: safe to `. idempotency.sh` repeatedly.
[[ -n "${AGENTLINUX_IDEMPOTENCY_SH_SOURCED:-}" ]] && return 0
readonly AGENTLINUX_IDEMPOTENCY_SH_SOURCED=1

if ! command -v log_error >/dev/null 2>&1; then
  printf 'idempotency.sh: log.sh must be sourced first\n' >&2
  return 1 2>/dev/null || exit 1
fi

# write_file_atomic <mode> <dest>
# Atomic full-file overwrite from stdin: write the heredoc/pipe body to a
# tmpfile in the same directory as <dest>, then install(1) it into place.
# Same semantics as `install -m <mode> /dev/stdin <dest>` on GNU coreutils,
# but portable to uutils-coreutils 0.7.0 (the Rust rewrite shipped on Ubuntu
# 26.04). uutils' install recursively readlink-chases /dev/stdin →
# /proc/self/fd/0 → "pipe:[NNN]" and then tries to stat the synthetic pipe
# name as a path, ENOENTing with "install: No such file or directory" — but
# only when the destination ALREADY exists (first run succeeds, idempotent
# re-runs fail). Symptom diagnosed via strace on Ubuntu 26.04 during the
# AGE-11 supported-target rollout (see PR #5 / commit fixing INST-02 + BHV-07
# byte-stability on uutils). Keep this helper in the lib so future calls
# cannot regress to /dev/stdin under set -e.
#
# Same-directory tmpfile placement keeps the install(1) rename atomic — a
# cross-filesystem rename would fall back to copy+unlink and lose atomicity.
# The tmpfile is hidden (leading dot) and unlinked unconditionally; on install
# failure the function returns non-zero so the caller's set -euo pipefail trap
# fires and the operator sees the underlying install diagnostic in the log.
write_file_atomic() {
  if [[ $# -lt 2 ]]; then
    log_error "write_file_atomic: missing arguments (usage: write_file_atomic <mode> <dest>)"
    return 64
  fi
  local mode=$1 dest=$2
  local dir base tmp rc=0
  dir=$(dirname -- "$dest")
  base=$(basename -- "$dest")
  tmp=$(mktemp -p "$dir" ".${base}.XXXXXX")
  # shellcheck disable=SC2064
  # Expand $tmp at trap-install time (function-local var); resolving later
  # would re-read a stale binding if the variable were reassigned.
  # Symmetric with ensure_marker_block's RETURN trap — guarantees tmpfile
  # cleanup on any exit path, including a `cat` that aborts mid-write under
  # set -e (ENOSPC, SIGPIPE).
  trap "rm -f -- '$tmp'" RETURN
  cat >"$tmp"
  install -m "$mode" "$tmp" "$dest" || rc=$?
  if [[ $rc -ne 0 ]]; then
    log_error "write_file_atomic: install -m ${mode} failed for ${dest} (rc=${rc})"
    return "$rc"
  fi
}

# ensure_line_in_file <line> <file>
# Append <line> to <file> only if not already present (fixed-string
# whole-line match). `-F` = literal string, `-x` = whole-line, `-q` = quiet,
# `--` = terminate options so <line> can start with `-`.
#
# Arg-count guard precedes $1/$2 reads so `set -u` callers get a friendly
# log_error on misuse instead of a raw `$1: unbound variable`.
ensure_line_in_file() {
  if [[ $# -lt 2 ]]; then
    log_error "ensure_line_in_file: missing arguments (usage: ensure_line_in_file <line> <file>)"
    return 64
  fi
  local line=$1 file=$2
  if ! grep -Fxq -- "$line" "$file" 2>/dev/null; then
    printf '%s\n' "$line" >>"$file"
    log_info "appended line to ${file}"
  fi
}

# ensure_marker_block <file> <tag> [--top|--bottom]
# Replace content between `# >>> <tag> begin >>>` / `# <<< <tag> end <<<`
# markers. Block content is read from stdin. Default placement is --bottom.
# --top is required for /home/agent/.bashrc (02-RESEARCH.md Pitfall 2: the
# Ubuntu skel .bashrc early-returns for non-interactive shells, so any
# agentlinux block that wants to influence `sudo -u agent bash -c ...` must
# appear before the early-return guard).
#
# Algorithm: awk-strip any pre-existing block, then emit the new block at the
# chosen placement. Uses install(1) so the final write is an atomic rename and
# preserves mode 0644. Tmp cleanup via a function-scoped RETURN trap.
ensure_marker_block() {
  if [[ $# -lt 2 ]]; then
    log_error "ensure_marker_block: missing arguments (usage: ensure_marker_block <file> <tag> [--top|--bottom])"
    return 64
  fi
  local file=$1 tag=$2 placement=${3:---bottom}
  local begin="# >>> ${tag} begin >>>"
  local end="# <<< ${tag} end <<<"
  local content tmp
  content=$(cat)
  tmp=$(mktemp)
  # shellcheck disable=SC2064
  # We WANT $tmp expanded at trap-install time (function-local var); resolving
  # later would re-read a stale binding if the variable were reassigned.
  trap "rm -f '$tmp'" RETURN

  case "$placement" in
    --top)
      {
        printf '%s\n' "$begin"
        printf '%s\n' "$content"
        printf '%s\n' "$end"
        if [[ -f $file ]]; then
          awk -v b="$begin" -v e="$end" '
            $0 == b { in_block=1; next }
            $0 == e { in_block=0; next }
            !in_block { print }
          ' "$file"
        fi
      } >"$tmp"
      ;;
    --bottom)
      if [[ -f $file ]]; then
        awk -v b="$begin" -v e="$end" '
          $0 == b { in_block=1; next }
          $0 == e { in_block=0; next }
          !in_block { print }
        ' "$file" >"$tmp"
      fi
      {
        printf '%s\n' "$begin"
        printf '%s\n' "$content"
        printf '%s\n' "$end"
      } >>"$tmp"
      ;;
    *)
      log_error "ensure_marker_block: unknown placement '${placement}' (expected --top or --bottom)"
      return 64
      ;;
  esac

  install -m 0644 "$tmp" "$file"
  log_info "wrote marker block '${tag}' (${placement}) to ${file}"
}

# ensure_user <name>
# useradd only if absent. Creates home, bash shell, matching user-group.
ensure_user() {
  if [[ $# -lt 1 ]]; then
    log_error "ensure_user: missing argument (usage: ensure_user <name>)"
    return 64
  fi
  local user=$1
  if id "$user" >/dev/null 2>&1; then
    log_info "user ${user} already exists (no-op)"
    return 0
  fi
  useradd --create-home --shell /bin/bash --user-group "$user"
  log_info "created user ${user} (home /home/${user}, shell /bin/bash)"
}

# ensure_dir <path> <mode> <user:group>
# Create directory if absent; enforce mode+ownership unconditionally on
# subsequent calls so re-runs correct any drift introduced out-of-band.
ensure_dir() {
  if [[ $# -lt 3 ]]; then
    log_error "ensure_dir: missing arguments (usage: ensure_dir <path> <mode> <user:group>)"
    return 64
  fi
  local path=$1 mode=$2 owner=$3
  if [[ ! -d $path ]]; then
    install -d -m "$mode" -o "${owner%:*}" -g "${owner#*:}" "$path"
    log_info "created directory ${path} (${mode} ${owner})"
  else
    chmod "$mode" "$path"
    chown "$owner" "$path"
  fi
}

# visudo_validate <file>
# `visudo -cf <file>` — safety check before installing a sudoers drop-in.
# Phase 2 ships no drop-in; the helper exists so Phase 3+ callers cannot forget
# it (see agentlinux-installer SKILL §"Sudoers minimalism").
visudo_validate() {
  if [[ $# -lt 1 ]]; then
    log_error "visudo_validate: missing argument (usage: visudo_validate <file>)"
    return 64
  fi
  local file=$1
  if ! visudo -cf "$file" >/dev/null; then
    log_error "sudoers syntax check failed for ${file} (visudo -cf rejected)"
    return 1
  fi
  log_info "sudoers syntax OK: ${file}"
}
