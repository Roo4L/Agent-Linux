---
phase: 04-agent-tool-packages
plan: 01
subsystem: infra
tags: [fpm, deb, nodejs, npm, chrome, xvfb, apt-repo, mcp, dpkg-scanpackages]

# Dependency graph
requires:
  - phase: 03-bootable-image
    provides: "Packer build template, provisioner script pattern, shell execution context"
provides:
  - "03-nodejs.sh: Node.js 22 LTS install, fpm, three .deb packages, local apt repo"
  - "04-chrome.sh: Google Chrome install, Xvfb, repo cleanup, version hold"
  - "Three .deb packages: agentlinux-claude-code, agentlinux-gsd, agentlinux-chrome-devtools-mcp"
  - "Local apt repository at /opt/agentlinux/apt-repo with Packages index"
affects: [04-02-PLAN, 05-end-to-end-validation]

# Tech tracking
tech-stack:
  added: [fpm, dpkg-dev, ruby-dev, nodejs-22-lts, jq, xvfb, google-chrome-stable]
  patterns: [thin-deb-wrapper-over-npm, postinst-npm-install, local-apt-repo, etc-skel-fallback, jq-config-merge]

key-files:
  created:
    - packer/scripts/03-nodejs.sh
    - packer/scripts/04-chrome.sh
  modified: []

key-decisions:
  - "Used npm install -g for all three packages (consistent thin wrapper pattern, system-wide install)"
  - "MCP config merged into ~/.claude.json via jq (not managed-mcp.json which takes exclusive control)"
  - "GSD integration files installed via temp HOME trick, then copied to /etc/skel with path fixup"
  - "Chrome downloaded as direct .deb from Google, repo removed after install for self-contained image"

patterns-established:
  - "Thin .deb wrapper: postinst runs npm install -g, postrm runs npm uninstall -g"
  - "/etc/skel fallback: all config files written to /etc/skel for users created after package install"
  - "jq merge pattern for JSON config lifecycle in postinst/postrm"
  - "Provisioner script sections: install, build, verify (each script ends with verification block)"

requirements-completed: [PKG-01, PKG-02, PKG-03, PKG-04, MCP-01]

# Metrics
duration: 3min
completed: 2026-03-18
---

# Phase 4 Plan 1: Agent Tool Packages - Build Scripts Summary

**Three .deb packages built with fpm (claude-code, gsd, chrome-devtools-mcp), local apt repo at /opt/agentlinux/apt-repo, Chrome + Xvfb installed with repo cleanup**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-18T15:13:23Z
- **Completed:** 2026-03-18T15:16:07Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created 03-nodejs.sh that installs Node.js 22 LTS, fpm, builds all three .deb packages with proper dependency chains, and creates a local apt repository with dpkg-scanpackages
- Created 04-chrome.sh that installs Google Chrome from direct .deb, Xvfb for headed mode, locks Chrome version, and removes Google apt repo for self-contained image
- All postinst/postrm scripts handle lifecycle correctly: npm install/uninstall, MCP config merge/removal via jq, GSD integration file setup/teardown, /etc/skel fallback for future users

## Task Commits

Each task was committed atomically:

1. **Task 1: Create 03-nodejs.sh** - `cd41c79` (feat)
2. **Task 2: Create 04-chrome.sh** - `6bc8cbe` (feat)

**Plan metadata:** TBD (docs: complete plan)

## Files Created/Modified
- `packer/scripts/03-nodejs.sh` - Provisioner script: Node.js 22 LTS, fpm, three .deb packages (agentlinux-claude-code, agentlinux-gsd, agentlinux-chrome-devtools-mcp), local apt repo at /opt/agentlinux/apt-repo
- `packer/scripts/04-chrome.sh` - Provisioner script: Google Chrome install, Xvfb, version hold, Google repo removal

## Decisions Made
- Used `npm install -g` for all three packages (consistent with CONTEXT.md thin wrapper pattern, provides system-wide install vs native installer which is per-user)
- MCP config targets `~/.claude.json` (research correction from CONTEXT.md's `~/.claude/.mcp.json`) using `jq -s` merge to preserve existing entries
- GSD integration installed via temp HOME pointing to /tmp/gsd-skel-install, copied to /etc/skel, paths fixed with sed to use /usr/bin/node
- Chrome installed from direct .deb download (not via apt repo) to avoid adding then removing a repo during the same script -- simpler lifecycle

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Both provisioner scripts are ready to be wired into the Packer template (Plan 04-02)
- Plan 04-02 will: create 05-agent-tools.sh (apt install from local repo), renumber 03-cleanup.sh to 06-cleanup.sh, update agentlinux.pkr.hcl scripts array
- The existing 03-cleanup.sh must be renumbered since 03-nodejs.sh now occupies that slot

## Self-Check: PASSED

All artifacts verified:
- packer/scripts/03-nodejs.sh: FOUND
- packer/scripts/04-chrome.sh: FOUND
- 04-01-SUMMARY.md: FOUND
- Commit cd41c79 (Task 1): FOUND
- Commit 6bc8cbe (Task 2): FOUND

---
*Phase: 04-agent-tool-packages*
*Completed: 2026-03-18*
