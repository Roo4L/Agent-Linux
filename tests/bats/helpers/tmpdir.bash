# tests/bats/helpers/tmpdir.bash
# Compatibility shim: guarantee a per-test writable temp dir on every bats.
#
# bats-core only began exporting BATS_TEST_TMPDIR in 1.4.0. Ubuntu 22.04's apt
# ships bats 1.2.1, where the variable is UNSET. A fixture that built a path as
# "${BATS_TEST_TMPDIR}/bin" then expanded it to "/bin" — and because Ubuntu is
# usr-merged (/bin -> /usr/bin), writing a PATH-stub to "/bin/sudo" CLOBBERS the
# real /usr/bin/sudo (and /usr/bin/{rpm,dnf,apt-get,...}) for the REST of the
# suite. Every later `sudo -u agent ...` then runs the stub, which redirects to
# an unset $AGENTLINUX_TEST_CAPTURE and dies with
#   /usr/bin/sudo: line 2: : No such file or directory
# cascading ~40 failures. 24.04 (bats >= 1.4) sets the var, so it never tripped.
#
# al_tmpdir_init sets the test-scope variable AL_TMPDIR to a guaranteed-unique
# writable dir — BATS_TEST_TMPDIR when bats provides one, else a dir minted under
# BATS_TMPDIR (which 1.2.1 DOES set to /tmp) — and REFUSES a system bindir so a
# stub harness can never overwrite a real binary even if this shim regresses.
#
# It assigns a variable rather than printing a path ON PURPOSE: a `$(al_tmpdir)`
# command substitution would mint the dir in a subshell, so the "did we create
# it?" bookkeeping could not reach teardown and the dir would leak. Call
# al_tmpdir_init from setup() (no subshell), reference $AL_TMPDIR, and call
# al_tmpdir_teardown from teardown() to remove a self-minted dir (a no-op when
# bats owns BATS_TEST_TMPDIR, which it cleans itself).

# al_tmpdir_init — set AL_TMPDIR (test scope) to a safe writable temp dir.
al_tmpdir_init() {
  if [[ -n "${BATS_TEST_TMPDIR:-}" ]]; then
    AL_TMPDIR="$BATS_TEST_TMPDIR"
    _AL_TMPDIR_OWNED=
  else
    AL_TMPDIR=$(mktemp -d "${BATS_TMPDIR:-/tmp}/al-bats.XXXXXX") || return 1
    _AL_TMPDIR_OWNED=1
  fi
  # Defense in depth: a writable temp root must never resolve to a system bindir.
  # Guarding the ROOT is sufficient because every consumer hangs its stub bindir
  # off it ("$AL_TMPDIR/bin"); a root that is itself a bindir is the only way a
  # stub could land on a real binary's path. mktemp -d under /tmp never yields
  # one, so this is a regression backstop, not a reachable branch.
  case ":$(readlink -f "$AL_TMPDIR"):" in
    *:/bin:* | *:/usr/bin:* | *:/sbin:* | *:/usr/sbin:* | *:/usr/local/bin:* | *:/usr/local/sbin:*)
      printf 'al_tmpdir_init: refusing unsafe temp dir under a system bindir: %s\n' "$AL_TMPDIR" >&2
      return 1
      ;;
  esac
}

# al_tmpdir_teardown — remove the dir al_tmpdir_init minted (old-bats path only).
al_tmpdir_teardown() {
  if [[ "${_AL_TMPDIR_OWNED:-}" == 1 && -n "${AL_TMPDIR:-}" ]]; then
    rm -rf "$AL_TMPDIR"
  fi
  unset AL_TMPDIR _AL_TMPDIR_OWNED
}
