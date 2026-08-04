# PUB-03 — Post-flip smoke

**Date:** 2026-04-26
**Triggered by:** agent (Claude Code) per maintainer authorization
**Result:** ✅ PASS (scoped — full curl-installer end-to-end deferred to v0.3.0 final release)

## Pre-conditions

- PUB-02 completed: `gh repo view Roo4L/Agent-Linux --json visibility` returned `{"visibility":"PUBLIC"}` at 2026-04-26T15:30Z.
- Latest release is `v0.3.0-rc12` (release candidate). The full `curl | bash` install path requires a v0.3.0 *final* release tag, which is the v0.3.0 milestone's separate shipping event.

## What was smoked

### 1. Anonymous clone over HTTPS — ✅

```text
$ rm -rf /tmp/postflip-smoke && mkdir /tmp/postflip-smoke && cd /tmp/postflip-smoke
$ GIT_TERMINAL_PROMPT=0 git -c credential.helper= clone https://github.com/Roo4L/Agent-Linux.git
Cloning into 'Agent-Linux'...
```

Clone succeeded with credential prompts disabled — proving the repo is reachable without GitHub auth. `LICENSE`, `CONTRIBUTING.md`, `README.md`, `.gitleaks.toml`, and `.pre-commit-config.yaml` are present at the repo root in the public clone.

### 2. Anonymous fetch of curl-installer via raw GitHub URL — ✅

```text
$ curl -fsSL -o /tmp/postflip-smoke/install.sh \
    https://raw.githubusercontent.com/Roo4L/Agent-Linux/master/packaging/curl-installer/install.sh
$ ls -la /tmp/postflip-smoke/install.sh
-rw-rw-r-- 1 agent agent 8899 Apr 26 15:30 /tmp/postflip-smoke/install.sh
```

### 3. Identity check — installer matches the cloned source byte-for-byte — ✅

```text
$ sha256sum /tmp/postflip-smoke/install.sh Agent-Linux/packaging/curl-installer/install.sh
319973ee4b38ae2a8cfb9579e3bd1f827f8b4cf71b33710847e162ec355408a7  /tmp/postflip-smoke/install.sh
319973ee4b38ae2a8cfb9579e3bd1f827f8b4cf71b33710847e162ec355408a7  Agent-Linux/packaging/curl-installer/install.sh
```

### 4. Syntax + envelope check — ✅

```text
$ bash -n /tmp/postflip-smoke/install.sh && echo "install.sh parses OK"
install.sh parses OK
```

The script's first line is `#!/usr/bin/env bash`, second is `# SPDX-License-Identifier: MIT`, the body is wrapped per the documented `main(){};main "$@"` partial-download mitigation (INST-03 / T-06-04).

## What was deliberately deferred

The end-to-end install (`curl … | sudo bash → agentlinux list → agentlinux install claude-code → claude --version`) requires:

- A `v0.3.0` *final* release tag (only `v0.3.0-rc12` exists today).
- The `release.yml` workflow having published the corresponding tarball + sibling `.sha256` to GitHub Releases.
- The agentlinux.org domain pointing the install URL at that release (the README documents `https://agentlinux.org/install.sh`).

Per `.planning/MILESTONES.md`, the v0.3.0 final release ships in its own milestone — separate from the visibility-flip deliverable that v0.4.0 owns. The end-to-end install smoke runs as part of that v0.3.0 release sign-off.

## Conclusion

The visibility-flip itself shipped cleanly — the public clone path and the public raw-source path both work. The "first cold install" verification is owed to the v0.3.0 final release event, not v0.4.0.

## Status

- [x] Anonymous clone passes
- [x] Anonymous raw fetch of install.sh passes
- [x] Cloned-vs-fetched SHA256 match
- [x] install.sh syntax parses
- [ ] End-to-end `curl … | sudo bash` install (deferred to v0.3.0 final release event)
