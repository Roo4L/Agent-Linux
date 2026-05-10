# tests/bats/helpers/detection.bash
# Phase 12 fixture helpers.
#
# snapshot_paths — emits one line per inode under the targeted dirs:
#   <path> <mtime-as-epoch.ns> <size-in-bytes>
# Sort -u for stable ordering. Used by Plan 12-03's read-only @test to detect
# any byte change made by the detection pass.
#
# Targeted scope per CONTEXT.md Q2 (D-04 area): /etc, /home, /usr/local/bin, /opt.
# /home/agent is a subtree of /home and naturally covered by `find /home`.
#
# `find -printf '%p %T@ %s\n'`: %p path, %T@ mtime as epoch.ns, %s size in bytes.
# %T@ is what catches a touch; %s catches a same-mtime overwrite. Per RESEARCH
# Assumption A11, this is sufficient for the no-op invariant (deliberately
# adversarial mutations that preserve all three are out of scope for the @test).

snapshot_paths() {
  find /etc /home /usr/local/bin /opt -printf '%p %T@ %s\n' 2>/dev/null | sort -u
}
