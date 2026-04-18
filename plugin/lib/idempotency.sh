#!/usr/bin/env bash
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

# ensure_line_in_file <line> <file>
# Append <line> to <file> only if not already present (fixed-string
# whole-line match). `-F` = literal string, `-x` = whole-line, `-q` = quiet,
# `--` = terminate options so <line> can start with `-`.
ensure_line_in_file() {
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
  local file=$1
  if ! visudo -cf "$file" >/dev/null; then
    log_error "sudoers syntax check failed for ${file} (visudo -cf rejected)"
    return 1
  fi
  log_info "sudoers syntax OK: ${file}"
}
