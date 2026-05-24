---
phase: 04-agent-tool-packages
verified: 2026-03-18T15:25:10Z
status: human_needed
score: 7/7 must-haves verified
re_verification: false
human_verification:
  - test: "Run `packer build packer/` and observe provisioner output from 03-nodejs.sh"
    expected: "fpm builds three .deb files; dpkg-scanpackages creates Packages index; apt-cache show confirms all three packages visible; no script exits non-zero"
    why_human: "Cannot run a live Packer build in this environment. Script logic is correct but build-time npm network access, fpm gem install, and dpkg-scanpackages output can only be confirmed by executing the build."
  - test: "After packer build completes, boot the QCOW2 and run: apt install agentlinux-claude-code agentlinux-gsd agentlinux-chrome-devtools-mcp"
    expected: "All three packages install without errors; postinst scripts run; `which claude` returns a path; `npm list -g @anthropic-ai/claude-code` shows the package; `npm list -g get-shit-done-cc` shows the package; `npm list -g chrome-devtools-mcp` shows the package"
    why_human: "The postinst scripts run at apt install time inside the image. Their success depends on npm network access during the Packer build — cannot verify statically."
  - test: "After package install, inspect /etc/skel/.claude.json"
    expected: "File exists and contains `\"chrome-devtools\"` key under `mcpServers`. jq merge did not corrupt the JSON."
    why_human: "MCP config is written by the chrome-devtools-mcp postinst at install time. Static analysis confirms the jq command is correct, but actual file creation requires a running build."
  - test: "After package install, create a new user and log in; verify GSD integration files are present"
    expected: "/home/newuser/.claude/get-shit-done exists; /home/newuser/.claude/commands/gsd exists; /home/newuser/.claude/settings.json exists and contains /usr/bin/node (not a tmp path)"
    why_human: "The /etc/skel copy behavior and path-fixup sed logic need a real user creation to validate the full lifecycle."
  - test: "Launch Claude Code as the agent user and check MCP server availability"
    expected: "Chrome DevTools MCP server appears in Claude Code's MCP server list; launching it with --headless --no-sandbox does not error"
    why_human: "MCP-03 (agent user can use the Chrome DevTools MCP) requires a running Claude Code session with display/headless Chrome. Cannot verify programmatically."
---

# Phase 4: Agent Tool Packages — Verification Report

**Phase Goal:** Claude Code, GSD framework, and Chrome DevTools MCP server are each packaged as .debs with fpm, stored in a local apt repository within the image, and install cleanly via `apt install`
**Verified:** 2026-03-18T15:25:10Z
**Status:** human_needed (all automated checks PASS; 5 human tests required for build-time and runtime behavior)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from Phase 4 Success Criteria and Plan must_haves)

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | Node.js 22 LTS is installed from NodeSource and available as shared runtime | VERIFIED | `03-nodejs.sh` line 8: `curl -fsSL https://deb.nodesource.com/setup_22.x | bash -`; line 9: `apt-get install -y nodejs` |
| 2  | fpm is installed and can build .deb packages | VERIFIED | `03-nodejs.sh` line 17: `gem install fpm`; fpm invoked 3 times with `-s dir -t deb` |
| 3  | Three .deb packages are built: agentlinux-claude-code, agentlinux-gsd, agentlinux-chrome-devtools-mcp | VERIFIED | `03-nodejs.sh` lines 41-52, 125-137, 195-208: all three fpm build commands present with correct names, versions, and dependencies |
| 4  | A local apt repo at /opt/agentlinux/apt-repo serves all three .debs via [trusted=yes] file:// source | VERIFIED | `03-nodejs.sh` lines 214-219: `mkdir -p /opt/agentlinux/apt-repo`, `cp /tmp/agentlinux-*.deb`, `dpkg-scanpackages -m . /dev/null > Packages`, `gzip -9c Packages > Packages.gz`, apt source written with `[trusted=yes] file:///opt/agentlinux/apt-repo` |
| 5  | Google Chrome is installed, its apt repo removed, version held, Xvfb installed | VERIFIED | `04-chrome.sh`: Chrome downloaded from `dl.google.com/linux/direct/`, installed, Xvfb installed, `apt-mark hold google-chrome-stable`, Google repo and GPG keys removed |
| 6  | `apt install` of all three packages is scripted and smoke-tested | VERIFIED | `05-agent-tools.sh` lines 11-13: explicit `apt-get install -y` for each package; lines 17-41: comprehensive smoke tests including `which claude`, `npm list -g`, `/etc/skel` checks, MCP config check |
| 7  | Packer template references all 6 scripts in correct order | VERIFIED | `packer/agentlinux.pkr.hcl` lines 71-78: scripts array contains 01-base through 06-cleanup in order; `packer validate -syntax-only` passes; old `03-cleanup.sh` reference removed |

**Score: 7/7 truths verified**

---

## Required Artifacts

| Artifact | Expected | Exists | Substantive | Wired | Status |
|----------|----------|--------|-------------|-------|--------|
| `packer/scripts/03-nodejs.sh` | Node.js 22, fpm, 3 .deb builds, local apt repo | Yes | Yes (234 lines, all sections implemented) | Wired (in Packer template line 74) | VERIFIED |
| `packer/scripts/04-chrome.sh` | Chrome install, Xvfb, version hold, repo removal | Yes | Yes (35 lines, all steps present) | Wired (in Packer template line 75) | VERIFIED |
| `packer/scripts/05-agent-tools.sh` | apt install of 3 packages with smoke tests | Yes | Yes (44 lines, apt installs + smoke tests) | Wired (in Packer template line 76) | VERIFIED |
| `packer/scripts/06-cleanup.sh` | fpm/ruby removal, systemd packer-user cleanup, apt clean, zero free space | Yes | Yes (52 lines, all original cleanup + fpm removal) | Wired (in Packer template line 77, last script) | VERIFIED |
| `packer/agentlinux.pkr.hcl` | Updated Packer template with all 6 scripts | Yes | Yes (6-script array, syntax valid) | Self-contained (no external dependency) | VERIFIED |

**Note:** `packer/scripts/03-cleanup.sh` is confirmed deleted (replaced by 06-cleanup.sh). The 03 slot is now occupied by 03-nodejs.sh as intended.

---

## Key Link Verification

### Plan 04-01 Key Links

| From | To | Via | Pattern Found | Status |
|------|----|-----|--------------|--------|
| `packer/scripts/03-nodejs.sh` | `/opt/agentlinux/apt-repo` | `dpkg-scanpackages` creates Packages index | Line 217: `dpkg-scanpackages -m . /dev/null > Packages` | WIRED |
| `packer/scripts/03-nodejs.sh` | `/etc/apt/sources.list.d/agentlinux.list` | apt source file points to local repo | Line 219: `echo "deb [trusted=yes] file:///opt/agentlinux/apt-repo ./"` | WIRED |

### Plan 04-02 Key Links

| From | To | Via | Pattern Found | Status |
|------|----|-----|--------------|--------|
| `packer/agentlinux.pkr.hcl` | `packer/scripts/05-agent-tools.sh` | scripts array in shell provisioner | Line 76: `"scripts/05-agent-tools.sh"` | WIRED |
| `packer/scripts/05-agent-tools.sh` | `/opt/agentlinux/apt-repo` | apt-get install reads from local repo | Lines 11-13: `apt-get install -y agentlinux-*` | WIRED |
| `packer/agentlinux.pkr.hcl` | `packer/scripts/06-cleanup.sh` | scripts array — must be last | Line 77: `"scripts/06-cleanup.sh"` (last entry) | WIRED |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| PKG-01 | 04-01 | Claude Code is packaged as a .deb via fpm | SATISFIED | `03-nodejs.sh`: fpm builds `agentlinux-claude-code_1.0.0_amd64.deb`; postinst runs `npm install -g @anthropic-ai/claude-code` |
| PKG-02 | 04-01 | GSD framework is packaged as a .deb via fpm | SATISFIED | `03-nodejs.sh`: fpm builds `agentlinux-gsd_1.0.0_amd64.deb`; postinst runs `npm install -g get-shit-done-cc`, installs GSD files to `/etc/skel/.claude/` |
| PKG-03 | 04-01 | Node.js 22 LTS from NodeSource is installed as shared runtime | SATISFIED | `03-nodejs.sh` lines 7-11: NodeSource setup_22.x, `apt-get install -y nodejs` |
| PKG-04 | 04-01 | Local apt repository configured in image; packages install via `apt install` | SATISFIED | `03-nodejs.sh` lines 213-220: repo created with dpkg-scanpackages; `05-agent-tools.sh` lines 11-13: `apt-get install -y` for all three packages |
| MCP-01 | 04-01 | Chrome DevTools MCP server packaged as a .deb with Chrome as dependency | SATISFIED | `03-nodejs.sh`: fpm builds `agentlinux-chrome-devtools-mcp_1.0.0_amd64.deb` with `--depends "google-chrome-stable"` and `--depends "jq"` |
| MCP-02 | 04-02 | MCP server pre-configured in agent user's Claude Code settings (via /etc/skel) | SATISFIED (static) | `03-nodejs.sh` postinst: `merge_mcp_config /etc/skel/.claude.json` with chrome-devtools entry via `jq -s` merge. Runtime confirmation needed (human test 3). |
| MCP-03 | 04-02 | Agent user can launch Claude Code and use the Chrome DevTools MCP server | NEEDS HUMAN | Config path is correct; actual MCP invocation requires a running Claude Code session inside the built image |

**No orphaned requirements.** All 7 Phase 4 requirements (PKG-01 through PKG-04, MCP-01 through MCP-03) appear in plan frontmatter and are accounted for.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `03-nodejs.sh` | 77, 96 | `USER_PLACEHOLDER` string in sed commands | Info | This is intentional design: a two-pass sed strategy (write placeholder, replace with real path per-user). Not a stub. |

No blocker or warning anti-patterns found. The `USER_PLACEHOLDER` string is a deliberate sed sentinel, used correctly in a two-step path-replacement strategy in the GSD postinst.

---

## Commit Verification

All four documented commits exist and contain the expected file changes:

| Commit | Task | Files Changed |
|--------|------|---------------|
| `cd41c79` | Create 03-nodejs.sh | `packer/scripts/03-nodejs.sh` (233 lines added) |
| `6bc8cbe` | Create 04-chrome.sh | `packer/scripts/04-chrome.sh` (35 lines added) |
| `d0ae7b1` | Create 05-agent-tools.sh, rename cleanup | `packer/scripts/05-agent-tools.sh` (created), `packer/scripts/03-cleanup.sh -> 06-cleanup.sh` (renamed + 5 lines added) |
| `3a3aed0` | Wire Packer template | `packer/agentlinux.pkr.hcl` (7 changes: 5 insertions, 2 deletions) |

---

## Human Verification Required

All automated checks passed. The following 5 items require a live Packer build and running image to confirm.

### 1. fpm builds all three .deb packages during Packer provisioning

**Test:** Run `packer build packer/` (or `packer build -only=qemu.agentlinux packer/`); observe output of `03-nodejs.sh`
**Expected:** fpm produces `agentlinux-claude-code_1.0.0_amd64.deb`, `agentlinux-gsd_1.0.0_amd64.deb`, `agentlinux-chrome-devtools-mcp_1.0.0_amd64.deb` in `/tmp/`; `dpkg-scanpackages` creates the Packages index; `apt-cache show agentlinux-claude-code` succeeds
**Why human:** npm network access and gem install during build cannot be verified statically

### 2. `apt install` of all three packages succeeds from the local repo

**Test:** Boot the built QCOW2; run `sudo apt install agentlinux-claude-code agentlinux-gsd agentlinux-chrome-devtools-mcp`
**Expected:** All three packages install without errors; postinst scripts run successfully; `which claude` returns `/usr/bin/claude` or `/usr/local/bin/claude`
**Why human:** Postinst scripts depend on npm network access at build time; dependency resolution requires the live apt system

### 3. MCP config is correctly merged into /etc/skel/.claude.json

**Test:** After package install, run `cat /etc/skel/.claude.json | jq .`
**Expected:** Valid JSON containing `{"mcpServers":{"chrome-devtools":{"command":"npx","args":["-y","chrome-devtools-mcp@latest","--headless","--no-sandbox"]}}}`
**Why human:** The jq merge runs at postinst time; file creation requires a live package install

### 4. New user inherits GSD integration files with correct Node.js path

**Test:** Create a new user (`useradd -m testuser`); check `/home/testuser/.claude/settings.json`
**Expected:** File exists; `grep /usr/bin/node /home/testuser/.claude/settings.json` returns a match; no `/tmp/gsd-skel-install` path remnants
**Why human:** /etc/skel copy and path fixup require real user creation to validate the full lifecycle

### 5. Claude Code can use Chrome DevTools MCP server (MCP-03)

**Test:** SSH in as agent user; run `claude` and check MCP server list, or invoke: `npx -y chrome-devtools-mcp@latest --headless --no-sandbox`
**Expected:** Chrome DevTools MCP server starts without errors; Claude Code lists it as available
**Why human:** Requires interactive terminal, display/headless Chrome stack, and Claude Code authentication

---

## Summary

Phase 4 goal is **fully implemented in script form**. All 6 provisioner scripts exist, are substantive (not stubs), are wired into the Packer template in correct order, and pass all static verification checks. Every requirement (PKG-01 through PKG-04, MCP-01 through MCP-03) is addressed in code.

The 5 human verification items are all **runtime confirmation** tasks — they verify that the scripts actually succeed when executed during a live Packer build, not that the implementation logic is missing. The implementation itself is complete.

**Roadmap note:** ROADMAP.md shows `04-02-PLAN.md` as `[ ]` (not checked). Based on this verification, the implementation for Plan 02 is complete — the ROADMAP.md status should be updated to reflect completion.

---

_Verified: 2026-03-18T15:25:10Z_
_Verifier: Claude (gsd-verifier)_
