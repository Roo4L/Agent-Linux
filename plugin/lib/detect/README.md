# plugin/lib/detect/ — read-only host discovery probes (Phase 12 / D-04).

Allowed read-only probes: dpkg-query (read-only DB query), apt list --installed,
id, getent, stat, sha256sum, grep -Fxq, find -printf, readlink -f,
node --version, npm config get prefix, command -v, &lt;agent&gt; --version,
&lt;agent&gt; --help. Always invoke install-user-scoped commands via
plugin/lib/as_user.sh — root's view of PATH and ~/.npmrc is wrong.

NEVER call from this directory: apt-get update / apt-get install,
npm install, source ~/.nvm/nvm.sh, eval "$(fnm env)", any write to /etc,
/home, /usr/local/bin, /opt. Memoization writes to /run/agentlinux-detect.json
only (tmpfs; not in the no-op snapshot scope). If you add a probe, verify
it does not write to /etc /home /usr/local/bin /opt — the bats no-op test
in Plan 12-03's tests/bats/15-detection.bats will catch you if it does.
