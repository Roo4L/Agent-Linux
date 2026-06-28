#!/usr/bin/env bash
# scripts/check-distro-leak.sh
# Phase 20 (PAR-01 / EL-08) cross-suite distro-leak guard.
#
# Fails if any bats behavior-test file (tests/bats/*.bats) or bats helper
# (tests/bats/helpers/*.bash) inlines an EXECUTED Debian-hardcoded package
# operation instead of routing it through the family-dispatch fork point
# tests/bats/helpers/distro.bash. This is the regression guard for the
# brownfield-gate class — a bare `dpkg-query` that ran fine on Ubuntu but died
# with `dpkg-query: command not found` on AlmaLinux 9 because the EL9 row has no
# dpkg.
#
# Coverage: the guard scans the whole bats tree (every tests/bats/*.bats plus
# tests/bats/helpers/*.bash) and is wired into pre-commit (and thus CI), so the
# class cannot regress silently in a sibling file.
#
# SCOPE — what is flagged (an EXECUTED, EL9-breaking package operation):
#   - dpkg-query / dpkg     (Debian package-DB tools; absent on EL9)
#   - deb.nodesource        (Debian NodeSource setup URL; wrong repo on EL9)
#   - apt-get …             (any apt-get invocation incl. flag-first
#                            `apt-get -y install`; absent on EL9)
#   - apt install/update/cache (the apt front-end; absent on EL9)
#   - add-apt-repository     (Debian PPA tool; absent on EL9)
#
# NOT flagged (different class — does not break on EL9, out of this guard's scope):
#   - Full-line comments (stripped before matching).
#   - Bare `/usr/bin/apt-get` string literals in sudoers-drift fixtures
#     (REMEDIATE-03 drift detection is content-based: any non-canonical line
#     reads as drift on BOTH families, so the literal never executes and never
#     breaks EL9). Route these through distro_sudoers_pkg_line when convenient,
#     but they are not a correctness regression.
#
# ALLOWLIST — files that LEGITIMATELY and PERMANENTLY reference these tokens:
#   - tests/bats/helpers/distro.bash      the fork point itself (the debian arm
#                                         IS the verbatim Debian command).
#   - tests/bats/18-pkg-dispatch.bats     the product family-dispatch SPEC: it
#                                         asserts the product emits apt-get /
#                                         dpkg-query / deb.nodesource on debian
#                                         and dnf / rpm / rpm.nodesource on rhel.
#                                         These strings ARE the assertion surface
#                                         and must never be removed.
#   - tests/bats/18-detect-el9.bats       the EL9 detection SPEC (asserts the
#                                         product does NOT probe /usr/bin/apt-get
#                                         on rhel) — same rationale.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# Files that legitimately reference Debian package tokens (see header).
is_allowlisted() {
  case "$1" in
    tests/bats/helpers/distro.bash) return 0 ;;
    tests/bats/18-pkg-dispatch.bats) return 0 ;;
    tests/bats/18-detect-el9.bats) return 0 ;;
    *) return 1 ;;
  esac
}

# Executed, EL9-breaking Debian package operations (NOT bare literals/comments).
# Catches flag-first forms (`apt-get -y install`), bare `dpkg`/`dpkg -l`, the
# `apt` front-end, and add-apt-repository — none of which exist on EL9.
leak_re='dpkg-query|deb\.nodesource|apt-get[[:space:]]|[[:space:]]dpkg([[:space:]]|$)|[[:space:]]apt[[:space:]]+(install|update|cache)|add-apt-repository'

violations=0
while IFS= read -r file; do
  is_allowlisted "$file" && continue
  # Strip full-line comments (leading-# lines) before matching so prose that
  # merely mentions apt-get does not trip the guard, then number the surviving
  # lines so the diagnostic points at the real source line.
  hits=$(
    grep -nvE '^[[:space:]]*#' "$file" \
      | sed -E 's/^([0-9]+):/\1\t/' \
      | grep -E "$leak_re" || true
  )
  if [[ -n "$hits" ]]; then
    if [[ $violations -eq 0 ]]; then
      printf 'check-distro-leak: inline Debian-hardcoded package operation(s) found.\n' >&2
      printf 'Route through tests/bats/helpers/distro.bash (e.g. distro_pkg_is_installed,\n' >&2
      printf 'distro_install_node22, distro_nodesource_repo_paths) so the EL9 row works.\n\n' >&2
    fi
    while IFS= read -r line; do
      printf '  %s:%s\n' "$file" "$line" >&2
    done <<<"$hits"
    violations=1
  fi
done < <(
  {
    find tests/bats -maxdepth 1 -name '*.bats' -type f
    find tests/bats/helpers -maxdepth 1 -name '*.bash' -type f
  } | sort
)

if [[ $violations -ne 0 ]]; then
  exit 1
fi
exit 0
