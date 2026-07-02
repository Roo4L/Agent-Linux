#!/usr/bin/env bash
# scripts/check-tty-sentinels.sh
# Guard: the interactive-test TTY driver's prompt sentinels must stay in sync
# with the strings the installer actually prints.
#
# tests/bats/helpers/tty-driver.py only feeds keystrokes AFTER it sees a prompt
# sentinel in the child's output (this is what fixed the flaky pre-prompt race
# on the AlmaLinux 9 row). The sentinels are literal substrings of the prompts
# in plugin/lib/prompt.sh, hardcoded in the driver with no compile-time link to
# their source. If prompt.sh changes a prompt string without updating the
# driver's PROMPT_SENTINELS tuple, the gate never opens: every input-driven
# interactive @test (15-preflight-ux.bats UX-02/UX-04) would hang until the
# driver's 120s TTY_DRIVER_TIMEOUT — ~14 minutes across the suite — instead of
# failing fast. This guard turns that drift into a millisecond lint failure.
#
# Wired into pre-commit (and thus CI). No arguments; scans the two files.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
driver="${repo_root}/tests/bats/helpers/tty-driver.py"
prompt_sh="${repo_root}/plugin/lib/prompt.sh"

for f in "$driver" "$prompt_sh"; do
  if [[ ! -f "$f" ]]; then
    printf 'check-tty-sentinels: expected file not found: %s\n' "$f" >&2
    exit 1
  fi
done

# Extract each b"..." literal from inside the PROMPT_SENTINELS = ( ... ) tuple.
# awk brackets the tuple body; sed pulls the double-quoted payload from each
# entry. Sentinel strings themselves contain no double quote, so the greedy
# capture is unambiguous. A failed/renamed extraction yields zero lines and is
# caught by the empty-array guard below — it never surfaces as a pipeline error
# (mapfile discards the process-substitution exit status by design).
mapfile -t sentinels < <(
  awk '/PROMPT_SENTINELS = \(/{f=1; next} f && /^[[:space:]]*\)/{f=0} f' "$driver" \
    | sed -n 's/.*b"\(.*\)".*/\1/p'
)

if [[ "${#sentinels[@]}" -eq 0 ]]; then
  printf 'check-tty-sentinels: no PROMPT_SENTINELS literals found in %s — did the tuple move or get renamed?\n' \
    "$driver" >&2
  exit 1
fi

rc=0
for s in "${sentinels[@]}"; do
  # -F: the sentinels contain regex metacharacters (e.g. `[Y/n]`); match literally.
  if ! grep -qF -- "$s" "$prompt_sh"; then
    printf 'check-tty-sentinels: sentinel not found in %s:\n  %q\n' "$prompt_sh" "$s" >&2
    printf '  → a prompt string drifted; update tests/bats/helpers/tty-driver.py PROMPT_SENTINELS to match plugin/lib/prompt.sh.\n' >&2
    rc=1
  fi
done

if [[ "$rc" -eq 0 ]]; then
  printf 'check-tty-sentinels: all %d TTY prompt sentinel(s) present in plugin/lib/prompt.sh.\n' \
    "${#sentinels[@]}"
fi
exit "$rc"
