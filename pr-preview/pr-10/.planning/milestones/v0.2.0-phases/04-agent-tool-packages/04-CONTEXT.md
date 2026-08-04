# Phase 4: Agent Tool Packages - Context

**Gathered:** 2026-03-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Package Claude Code, GSD framework, and Chrome DevTools MCP server as .debs built with fpm. Each package uses a thin .deb wrapper over npm global installs (not bundled in /opt). A local apt repository within the image serves all packages. `apt install` resolves dependencies and installs cleanly.

</domain>

<decisions>
## Implementation Decisions

### Packaging pattern (all npm-based packages)
- Thin .deb wrapper pattern: postinst runs `npm install -g <package>`, postrm runs `npm uninstall -g <package>`
- .deb owns: dependency declarations, wrapper scripts on PATH, integration file setup
- Code lives in Node.js global modules, NOT bundled in /opt/agentlinux/
- User can `npm update -g` to get newer versions without rebuilding the .deb
- All packages declare Node.js as a dependency (transitive from NodeSource)

### Chrome browser
- Google Chrome (not Chromium) — maximum MCP server compatibility
- Install from Google's apt repo during Packer build
- Remove Google apt repo after install (self-contained image, no external calls on apt update)
- `apt-mark hold google-chrome-stable` to prevent accidental removal
- Include Xvfb for headed mode support (agents can use `xvfb-run` for visual testing)
- Default to `--no-sandbox` flag (standard for server/agent environments, agent user has sudo)

### API key handling
- No API key configuration in the image at all
- User handles Anthropic API key themselves (Claude Code's default first-run behavior)
- Image ships with zero credentials baked in

### MCP server configuration
- MCP config is a lifecycle concern of the .deb package, NOT /etc/skel
- postinst merges MCP server entry into all users' `.claude/.mcp.json` (iterates /home/*/)
- postrm removes the MCP server entry from all users' `.claude/.mcp.json`
- System-wide approach: any user on the system gets the config when the package is installed

### GSD integration depth
- Full integration: CLI command + .claude/ integration files (workflows, agents, templates, hooks)
- postinst installs integration files AND merges settings.json entries (hooks, slash command registration)
- postrm removes integration files and settings.json entries
- /gsd: slash commands work immediately in Claude Code after install
- agentlinux-gsd hard-depends on agentlinux-claude-code (apt auto-resolves)

### GSD source
- Install from npm (get-shit-done package), not from this repo's local files
- Integration files extracted from the installed npm package

### MCP server install mechanism
- Default assumption: npm global pattern (same as Claude Code and GSD)
- Researcher to confirm exact npm package name and entry point
- If MCP server is not an npm package, planner adjusts approach

### Claude's Discretion
- Exact postinst/postrm script implementation for config merging
- Local apt repo creation approach (dpkg-scanpackages, reprepro, etc.)
- Wrapper script implementation details
- fpm flags and build commands
- Packer provisioner script ordering (new scripts before existing 03-cleanup.sh)
- NodeSource setup script placement

</decisions>

<specifics>
## Specific Ideas

- Package lifecycle matters: `apt install` adds config, `apt remove` removes config — no orphaned dotfiles
- Updatability via npm is a core requirement — .debs are bootstrap + integration, not frozen bundles
- Same thin wrapper pattern for all npm-based packages (consistency)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `packer/agentlinux.pkr.hcl`: Packer template with shell provisioner pattern — new scripts slot into the `scripts` array
- `packer/scripts/01-base.sh`: Already installs gnupg, curl, wget, ca-certificates — dependencies for adding Google Chrome repo
- `packer/scripts/03-cleanup.sh`: Handles apt cache cleanup and image compression — new scripts must run BEFORE this

### Established Patterns
- Shell provisioner runs as root via `sudo -S bash -c`
- Environment vars passed via Packer `environment_vars`
- Scripts are numbered sequentially (01, 02, 03) — new scripts continue the sequence
- Oneshot systemd service for deferred operations (packer user cleanup pattern)

### Integration Points
- New provisioning scripts added to `packer/scripts/` and referenced in `agentlinux.pkr.hcl` build block
- 03-cleanup.sh must remain last (or be renumbered) since it cleans apt cache and zeros free space
- one-context creates the agent user on first boot — postinst scripts iterating /home/*/ may need to handle "no users yet" case via /etc/skel fallback

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-agent-tool-packages*
*Context gathered: 2026-03-16*
