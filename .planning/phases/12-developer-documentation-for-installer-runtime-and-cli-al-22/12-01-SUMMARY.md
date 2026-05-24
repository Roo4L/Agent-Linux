---
phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22
plan: 01
subsystem: docs
tags: [internals, installer, agent-user, sudoers, nodejs, npm-prefix, path-wiring, AL-22, DOC-01, DOC-02]

# Dependency graph
requires:
  - phase: 02-installer-foundation-agent-user
    provides: agent user provisioner + PATH wiring artifacts (the agent-user.md + nodejs-runtime.md grounding)
  - phase: 03-nodejs-runtime
    provides: 30-nodejs.sh + per-user npm prefix at ~/.npm-global (the nodejs-runtime.md grounding)
  - phase: 05-1-agent-user-sudo-drop-in
    provides: 20-sudoers.sh + ADR-012 (the sudo-drop-in.md grounding)
  - phase: 06-distribution-release-pipeline
    provides: packaging/curl-installer/install.sh + INST-03 SHA256-verified release pipeline (the installer.md grounding)
provides:
  - docs/internals/ tree with index README + 4 install/runtime-layer component docs (installer, agent-user, sudo-drop-in, nodejs-runtime)
  - The four-part component-doc structural contract: lede -> ## The problem -> ## What AgentLinux does -> ## Worked example (optional) -> ## Value vs the naive approach -> ## Related
  - The trade-off / "value vs naive" doc pattern with bold-lead-clause numbered list (excerpt-friendly per CONTEXT §"Reuse signal")
  - TOC scaffold in docs/internals/README.md linking to all 9 eventual component docs (4 from this plan + 5 from Plan 02)
affects:
  - 12-02-PLAN (writes the remaining 5 component docs: claude-code, gsd, playwright, registry-cli, catalog — must follow the same structural contract + tone established here)
  - 12-03-PLAN (dev-docs reviewer agent + dev-docs skill — both reference the docs contract this plan instantiates)
  - 12-04-PLAN (CLAUDE.md wiring of dev-docs-auditor into the Review Loop table)
  - 12-05-PLAN (top-level README.md "Why AgentLinux — concepts" link into docs/internals/)

# Tech tracking
tech-stack:
  added: []  # docs only — no new libraries / runtime tech
  patterns:
    - Component-doc H2 spine "problem -> answer -> value vs naive -> Related" (mapped from STABILITY-MODEL.md "Why pin at all (the trade-off)")
    - Bold-lead-clause numbered-list trade-off pattern (excerpt-friendly for blog/marketing reuse)
    - Cross-link Related footer with no source-line deep links (CONTEXT §"Depth")

key-files:
  created:
    - docs/internals/README.md
    - docs/internals/installer.md
    - docs/internals/agent-user.md
    - docs/internals/sudo-drop-in.md
    - docs/internals/nodejs-runtime.md
  modified: []

key-decisions:
  - One concrete ADR link allowed in sudo-drop-in.md Related footer (link to ADR-012) — closest doc-to-ADR mapping in the set; CONTEXT §"Depth" allows ADR mentions in prose, and linking from the doc most-tightly-bound to that ADR is justified surface area without breaking the no-deep-links rule
  - Mermaid omitted from all four component docs — prose was clearer for installer (sequence) and runtime (topology); no diagram added gratuitously per CONTEXT §"Diagrams" "used sparingly"
  - Worked-example shell sessions used `$ ` prompt prefix throughout for STABILITY-MODEL.md-tone consistency
  - PATH ordering rationale called out explicitly in nodejs-runtime.md ("/home/agent/.npm-global/bin lands first … so a stray wrapper shim at /usr/local/bin/<tool> cannot win") — the security-engineer-rubric Pitfall 4 mitigation made visible at the doc level
  - Counter-example in sudo-drop-in.md Worked example deliberately shows `sudo npm install -g` as something that WOULD succeed but remains a forbidden anti-pattern — the doc enforces the discipline that ADR-012 + ADR-004 together draw

patterns-established:
  - "H2 spine for component docs: # <Title> -> 3-5 line lede -> ## The problem -> ## What AgentLinux does -> ## Worked example (optional) -> ## Value vs the naive approach -> ## Related"
  - "Trade-off list pattern: 'Without X, the naive path is Y. Two problems:' lede + numbered list with **bold lead clause.** explanation + bold one-line resolution sentence"
  - "Related footer: 3-5 bullets, [readable name](path) -- one-sentence what's there; no source-line deep links anywhere"

requirements-completed: [DOC-01, DOC-02]

# Metrics
duration: 5min
completed: 2026-05-10
---

# Phase 12 Plan 01: Internals docs index + installer + agent-user + sudo-drop-in + nodejs-runtime Summary

**5 product-perspective component docs that answer "what value does AgentLinux provide for surface X" for the four foundational install/runtime layers, scaffolding a docs/internals/ tree the next four plans extend.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-10T05:45:32Z
- **Completed:** 2026-05-10T05:50:39Z
- **Tasks:** 2
- **Files created:** 5
- **Files modified:** 0

## Accomplishments

- `docs/internals/` directory created (sibling to `docs/decisions/`, `docs/research/`, `docs/audits/`).
- Index README with What-AgentLinux-is lede + TOC linking all 9 eventual component docs + Audience section stating the reuse signal (excerpt-friendly for blog/marketing copy).
- Four foundational-layer component docs (installer, agent-user, sudo-drop-in, nodejs-runtime), each following the problem -> answer -> value-vs-naive contract from CONTEXT §"Documentation Scope & Format".
- Worked-example shell sessions in installer.md, agent-user.md, sudo-drop-in.md, and nodejs-runtime.md showing concrete observable behavior (curl-pipe-bash output, `claude update` without sudo/EACCES, `sudo -l` output, `which claude` resolving identically across invocation modes).
- Trade-off "Value vs the naive approach" lists in all four component docs written in the bold-lead-clause numbered format that lifts cleanly into blog posts and marketing emails.
- Hard contract upheld: no source-line deep links (`*.sh:NN`, `*.ts:NN`, `*.json:NN`) anywhere; no Mermaid fences; ADR mentions in prose only (sudo-drop-in.md Related footer is the single exception, linking ADR-012 directly per its tight binding to the doc topic).

## Task Commits

Each task was committed atomically (no fix commits, no deviations):

1. **Task 1: Write README.md (index) + installer.md + agent-user.md** — `9c00061` (docs)
2. **Task 2: Write sudo-drop-in.md + nodejs-runtime.md** — `4598b4a` (docs)

**Plan metadata commit (this SUMMARY + STATE/ROADMAP/REQUIREMENTS updates):** committed after this file lands.

## Files Created/Modified

- `docs/internals/README.md` (49 lines) — Index with What-AgentLinux-is lede, `## Components` TOC linking all 9 component docs (4 from this plan + 5 placeholders for Plan 02), `## Audience` section stating the project-owner-first / contributors-second / reuse-signal-for-blog-marketing audience model, trailing cross-links to `../README.md` and `../HARNESS.md`.
- `docs/internals/installer.md` (114 lines) — Component doc on the curl-pipe-bash installer. Lede frames it as "one command turns a clean Ubuntu host into agent-ready environment." Problem covers bespoke shell scripts + unverified curl-pipe-bash + sudo-npm-install poisoning. Answer describes the five-step sequence (HTTPS fetch + SHA256 verify + extract + exec + ordered provisioners) plus the `main(){}; main "$@"` partial-download-safety wrapper. Worked example shows real curl-pipe-bash transcript ending in `agentlinux list` with no agents installed (ADR-003). Trade-off list contrasts tampered/partial downloads vs non-reproducible installs. Related footer links agent-user, sudo-drop-in, nodejs-runtime, top-level README.
- `docs/internals/agent-user.md` (118 lines) — Component doc on the dedicated `agent` user with per-user npm prefix. Lede anchors on "the agent owns its tools so it can update them." Problem section walks through the EACCES + recursive-shim sequence: `sudo npm install -g` -> root-owned tree -> wrapper at `/usr/local/bin/` -> `claude update` fails EACCES -> user reaches for sudo -> permission tax compounds; calls AGT-02 the canonical regression. Answer describes the agent user's shape (UID, home, shell, locale, CLAUDE.md anti-pattern doc) + the per-user prefix at `~/.npm-global/` + PATH wired across six modes via four artifacts + the `as_user agent` discipline. Worked example shows fresh install -> `claude update` succeeding without sudo or EACCES. Trade-off list contrasts EACCES-on-every-non-root-op vs broken self-updaters. Related links installer, nodejs-runtime, sudo-drop-in, claude-code (the canonical case).
- `docs/internals/sudo-drop-in.md` (123 lines) — Component doc on `/etc/sudoers.d/agentlinux`. Lede explains the single-line `agent ALL=(ALL) NOPASSWD: ALL` grant. Problem section frames how autonomous coding agents need root-class operations (apt install, systemctl restart, etc.) and how zero-sudo / shared-root-password / narrow-allowlist all fail in practice; cites ADR-012 explicitly in prose. Answer describes the drop-in mechanics (mode 0440, root:root, visudo -cf gate before atomic install, post-install rehash, byte-stable on re-run) and the deliberate non-effect on the per-user prefix invariant. Worked example shows password-free `sudo apt-get install` PLUS a counter-example showing `sudo npm install -g` would succeed-but-is-still-forbidden — the discipline ADR-004 enforces beyond what ADR-012 grants. Trade-off list contrasts zero-sudo (blocks legitimate work) vs password prompts (stall autonomous loops). Related footer is the **only** doc with a direct ADR link in this plan: `../decisions/012-agent-user-full-sudo.md` — sudo-drop-in.md is the closest doc to ADR-012's content, justifying the explicit cross-link per CONTEXT §"Depth" "may reference an ADR by name in prose."
- `docs/internals/nodejs-runtime.md` (141 lines) — Component doc on the system Node.js + per-user npm prefix + PATH wiring layer. Lede establishes "two pieces, one runtime contract." Problem section covers both naive paths: version-manager-non-interactive (nvm/asdf/fnm shell-init hooks skipped under cron/systemd/ssh -i/sudo) AND sudo-npm-corrupts-ownership (root-owned `/usr/lib/node_modules` -> EACCES -> broken `claude update`). Answer describes both halves: (i) NodeSource apt + LTS line + ADR-005 trade-off; (ii) per-user prefix at `~/.npm-global/{bin,lib}` + `~/.npmrc` + NPM_CONFIG_PREFIX belt-and-braces + PATH wiring across six modes via four artifacts (profile.d, .bashrc-at-top, agentlinux.env, cron.d) + path-ordering rationale (npm-global FIRST, defeats `/usr/local/bin/` shim). Worked example shows `which node` (system) + `npm config get prefix` (agent) + `which claude` resolving the same way under cron, systemd, ssh, and `sudo -u agent bash -c`. Trade-off list contrasts version-manager non-interactive failure vs sudo-npm ownership corruption (with explicit cross-link to agent-user.md for the full bug class). Related links agent-user, installer, claude-code, gsd.

## Decisions Made

- **One concrete ADR link allowed (sudo-drop-in.md → ADR-012).** CONTEXT §"Depth" disallows source-line deep links and says ADR links are optional, not required. Sudo-drop-in.md's content maps almost 1:1 to ADR-012's decision record, so a single Related-footer link to ADR-012 was the most useful surface. installer.md, agent-user.md, and nodejs-runtime.md mention their ADRs (006, 004, 005, 004 respectively) only in prose, no link — preserving the bulk-no-link discipline.
- **No Mermaid diagrams.** All four component docs were prose-clear without diagrams. The plan flagged Mermaid as optional per CONTEXT §"Diagrams" "used sparingly" — I judged each component and concluded prose served. (If Plan 02's catalog or registry-cli docs need a sequence diagram or topology, the plan adds it there.)
- **Worked-example use across all four component docs.** PATTERNS.md lists worked-example as optional; I included one in each because the AL-22 litmus test ("60-second answer for what value AgentLinux adds") is dramatically reinforced by a 5-7-line shell session showing the actual observable behavior. Without the session, "claude update without sudo or EACCES" is abstract; with it, the value lands.
- **Counter-example in sudo-drop-in.md is deliberate.** The plan calls for a counter-example showing `sudo npm install -g` running password-free under ADR-012 but remaining forbidden because ADR-004 + the codebase's `as_user` rule still draw the line. This is the single most subtle teaching moment in the four docs — the docs are excerpt-friendly source material, and "ADR-012 grants sudo, ADR-004 disciplines what to use it for" is exactly the kind of pull-quote the AL-22 ticket is asking for.
- **Counter to PATTERNS.md mapping for STABILITY-MODEL "Worked example: I ran claude update":** STABILITY-MODEL.md uses that worked example to introduce three-state divergence (synced / override-ahead / override-behind). I deliberately did NOT replicate that example in agent-user.md or nodejs-runtime.md — those docs are about the foundational ownership invariant (AGT-02 succeeds without sudo/EACCES), not about the divergence reconciliation surface (which lives in the registry-cli + catalog docs in Plan 02). Splitting the topic this way keeps each doc's argument tight.

## Deviations from Plan

None - plan executed exactly as written.

Both verify-block automated checks pass first try; both `<acceptance_criteria>` lists pass; both `<done>` criteria met. Zero auto-fix commits, zero Rule N deviations to document.

## Issues Encountered

None. The plan's `<read_first>` lists pre-loaded the right context (CONTEXT, PATTERNS, STABILITY-MODEL, source files for each component, ADRs); the H2 spine and bold-lead-clause patterns were copy-pastable from STABILITY-MODEL.md modulo content swap; the no-deep-links + no-mermaid contract was easy to honor because both component docs were short and prose-natural.

The pre-existing `git status` snapshot showed unrelated modifications to `.planning/STATE.md`, `.planning/config.json`, three Plan 12-0[2..5] PLAN.md files, and `docs/audits/v0.4.0/PUB-04-release-notes.md` — these were left strictly untouched. Per the protocol, only `docs/internals/*.md` files were `git add`-ed and committed; no `git add .` / `-A` was used.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `docs/internals/` tree scaffolded; the index README's TOC already enumerates all 9 component docs with `[name](slug.md)` links.
- Plan 02 picks up the remaining 5 component docs (claude-code, gsd, playwright, registry-cli, catalog) — files are referenced as broken links from this plan's `## Related` footers and from the README TOC, which the verifier should expect as known-broken until Plan 02 lands.
- Plan 03 (dev-docs reviewer + dev-docs skill) and Plan 04 (CLAUDE.md wiring) can begin in parallel with Plan 02 — both are about *enforcing* the contract this plan instantiated, not about authoring new docs against it.
- Plan 05 (top-level README pointer into docs/internals/) is trivially unblocked; it just needs the `docs/internals/README.md` target to exist, which this plan delivers.
- The structural contract (problem -> answer -> value -> Related; bold-lead-clause trade-off list; no source-line deep links; ADR mentions in prose without links by default) is now reified in 4 working examples that Plan 02 should pattern-match against — the dev-docs-auditor reviewer (Plan 03) will enforce the same.

## Self-Check: PASSED

- `docs/internals/README.md` — FOUND (49 lines)
- `docs/internals/installer.md` — FOUND (114 lines)
- `docs/internals/agent-user.md` — FOUND (118 lines)
- `docs/internals/sudo-drop-in.md` — FOUND (123 lines)
- `docs/internals/nodejs-runtime.md` — FOUND (141 lines)
- Task 1 commit `9c00061` — FOUND in `git log`
- Task 2 commit `4598b4a` — FOUND in `git log`
- Each component doc has the four mandated H2 sections — VERIFIED via grep
- README has H1 `# AgentLinux Internals` + `## Components` H2 + all 9 TOC links — VERIFIED via grep
- No source-line deep links (`*.sh:NN`, `*.ts:NN`, `*.json:NN`) anywhere in 5 new files — VERIFIED via `grep -nE`
- No Mermaid fences in 5 new files — VERIFIED via `grep '^```mermaid'`
- Both `## Value vs the naive approach` numbered lists across 4 component docs use `**bold lead clause.**` form (count: 2 each) — VERIFIED via `grep -cE '^[0-9]+\. \*\*'`
- `agent-user.md` mentions EACCES + self-update / claude update in `## The problem` — VERIFIED via grep
- `sudo-drop-in.md` mentions NOPASSWD + names ADR-012 — VERIFIED via grep
- `nodejs-runtime.md` mentions `~/.npm-global` + both halves (system Node.js via apt + per-user prefix + PATH wiring across modes) — VERIFIED via grep

---
*Phase: 12-developer-documentation-for-installer-runtime-and-cli-al-22*
*Completed: 2026-05-10*
