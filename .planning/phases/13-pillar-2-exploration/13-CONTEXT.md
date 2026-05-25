# Phase 13: Pillar 2 Exploration - Context

**Gathered:** 2026-05-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Decide what AgentLinux's pillar 2 actually commits to, and produce a written
verdict (`docs/exploration/PILLAR-2-NOTES.md`) that Phase 15 lifts verbatim into
`docs/STRATEGY.md` Pillar 2 without re-deciding. The deliverable is *framing*,
not new product capability — the pillar's named commitments seed downstream
roadmap themes (v0.6+) but do not ship any of them in v0.3.3.

The pillar name is locked at milestone-open: **stability + time-to-productive**.
Phase 13 decides the *content* under that name.

</domain>

<decisions>
## Implementation Decisions

### Pillar Framing — Hard Reframe vs Research SUMMARY §4

The research SUMMARY.md §4 framed pillar 2 around "agent-focused benchmarks"
(terminal-bench, Multi-Docker-Eval, τ-bench `pass^k`, SWE-bench Verified) +
opt-in observability (Helicone / Langfuse). That framing is **rejected** as
load-bearing pillar substance.

**Reframe rationale (locked):** AgentLinux is *infrastructure*, not an agent
product. It provisions the environment in which agents run. It does not run,
score, or compare agents. Therefore agent-focused benchmarks measure the wrong
thing for our pillar — they measure the agents that would run on top of us, not
the value we deliver. The benchmark suites stay in the doc as **considered and
rejected** raw material (satisfies the EXPL-01 grep gate while honestly
documenting the trade-off per Pitfall #13).

What pillar 2 actually commits to (user direction, 2026-05-10):

- The *value to the user* is what AgentLinux gives them automatically — a
  vetted, opinionated environment where the agents they run are more reliable
  and more productive than they would be on a hand-rolled `npm install -g`
  setup.
- The mechanism is **curated default version sets + compat-guarded updates +
  opinionated bundles** — three concrete positions an infrastructure product
  can take that a thin wrapper or a single-tool installer cannot.

### Table-Stakes Commitments (≥2 required by EXPL-01)

- **T-1 — AGT-02 zero-EACCES self-update.** Curated `claude` self-updates
  against the live Anthropic CDN with zero EACCES and zero sudo prompts.
  Already shipped in v0.3.0; release-gated via TST-08. Cite the AGT-02 bats
  test and the `claude-code/install.sh` recipe.
- **T-2 — ADR-011 stability model.** `pinned_version` per catalog agent +
  curated combo + TST-08 4-gate release pipeline (pre-commit → docker matrix
  → QEMU matrix → pinned-combo). Already shipped in v0.3.0. Cite
  `docs/STABILITY-MODEL.md` and ADR-011.

### Differentiator Commitments (≥1 required by EXPL-01) — three named, all real positions

- **D-1 — Compat-guarded default version set.** When an upstream package
  update breaks the curated combo (e.g. a Claude Code update breaks GSD), the
  default version set *holds* at the last-known-good combo. AgentLinux
  monitors for the upstream fix, verifies compatibility on the new combo via
  CI, and only advances the default set when a verified-compatible combo
  emerges. The user gets a stable environment without tracking upstream
  issues themselves. (Side-effect, not a commitment: AgentLinux's CI matrix
  may surface upstream breakage first and we may file the upstream issue —
  good citizenship, not a pillar promise.) Position: most `npm install -g`
  paths give the user the latest immediately, even when "latest" is broken
  with the rest of the toolchain. AgentLinux takes the opposite position.
- **D-2 — Preset framework.** Three presets selectable at install time:
  - `bare` — nothing installed (preserves the "no agents installed by default"
    invariant from ADR-003).
  - `must-haves` — canonical universal coding-agent tools (e.g. Claude Code,
    Codex). Specific list locks when the preset framework ships; v0.3.3
    commits to the *concept* and names canonical members illustratively.
  - `optimum` — `must-haves` plus opinionated, well-tested extras that improve
    the agent experience without the user having to know about each one
    individually. RTK (Rust Token Killer — token-efficiency proxy) is the
    canonical example; specific list locks when the preset framework ships.
- **D-3 — Profile framework.** Orthogonal axis to presets: use-case-specific
  bundles like `web-development` (playwright-cli + browser deps). Composable
  with presets, e.g. `agentlinux install --preset optimum --profile web-development`.
  Specific profile list locks when the framework ships; v0.3.3 commits to the
  shape.

### Explicit Non-Goals (≥2 required by EXPL-01) — four named

- **NG-1 — Not running, scoring, or comparing agents.** Agent-focused
  benchmarks (terminal-bench, Multi-Docker-Eval, τ-bench `pass^k`, SWE-bench
  Verified, SWE-bench Live, Aider polyglot) measure agents; AgentLinux is
  infrastructure that runs agents. We cite these as landscape and explicitly
  reject them as pillar-2 substance.
- **NG-2 — Not maintaining backports, forks, or downstream patches of
  upstream packages.** We pin, hold, and wait for upstream fixes. We do not
  carry patches downstream. (This is a deliberate scope-shrink — we are not
  signing up to become a Linux-distribution-style maintenance burden.)
- **NG-3 — Not publishing per-model performance scores.** Stronger
  restatement of NG-1's specific case for clarity.
- **NG-4 — Not becoming an agent observability product.** Helicone / Langfuse
  remain *opt-in catalog entries* (per ADR-003's no-default-agents rule),
  not pillar commitments. If a user wants observability, the catalog makes it
  one command away — but AgentLinux does not bundle, brand, or compete on
  observability.

### Today / Direction Content Seeds (required by EXPL-01)

- **Today (v0.3.0 reality):** AGT-02 zero-EACCES self-update release-gate
  green; ADR-011 `pinned_version` + TST-08 4-gate release pipeline; curated
  combo (claude-code + gsd + playwright + agentlinux-cli) tested in QEMU on
  Ubuntu 22.04 + 24.04 every release. No preset framework yet; no profile
  framework yet; no formal compat-guarded update flow beyond TST-08 manual
  gate.
- **Direction (`next-milestone` priority):** Preset framework
  (`bare` / `must-haves` / `optimum`); profile framework (orthogonal use-case
  bundles); compat-guarded update flow (hold default set on upstream breakage,
  roll forward only after CI-verified fix). The literal string
  `next-milestone` appears in the Decision summary section to satisfy the
  EXPL-01 grep anchor.

### Priority Tag

Pillar 2 carries the `next-milestone` priority tag — locked per user
direction at milestone-open (2026-05-09) and reaffirmed in this exploration
(2026-05-10). The tag text appears literally in the Decision summary.

### EXPL-01 Grep Gate — Citation Strategy

The required regex hits (`terminal-bench|Multi-Docker-Eval|tau-bench|pass\^k|time-to-productive|SWE-bench|Helicone|Langfuse`)
are satisfied by citing each in a "Considered and rejected — agent benchmarks"
subsection of the body. The doc honestly documents that these were the
research raw material and explains why each was rejected as pillar-2
substance. This satisfies the gate (≥5 distinct hits) while honoring the
hard-reframe.

### Claude's Discretion

- Section ordering and prose voice for `PILLAR-2-NOTES.md` body.
- Specific phrasing of the rejection rationale for each cited benchmark suite
  (terminal-bench, Multi-Docker-Eval, etc.) as long as the reason
  ("infrastructure, not agent product") is consistent.
- Whether the body's "Considered and rejected" subsection cites each suite as
  a separate paragraph or as a list — Claude picks the form that hits ≥5
  distinct grep matches naturally.
- Inclusion of optional T-3 (default-set compat verification as additional
  table-stakes) — recommended omitted; D-1 carries the position more
  cleanly as a differentiator.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (no code changes in Phase 13 — doc-only)

- `.planning/research/SUMMARY.md` §4 — pillar-2 substance summary, named eval
  suites, named precedents. Source raw material.
- `.planning/research/FEATURES.md` — full eval-suite landscape (terminal-bench,
  Multi-Docker-Eval, τ-bench, SWE-bench variants, Aider polyglot, observability
  vendors). Source raw material.
- `.planning/research/PITFALLS.md` — voice rule, Pitfall #13 (rejected
  alternatives discipline) — informs the "considered and rejected" framing.
- `docs/STABILITY-MODEL.md` (5.4 KB) — ADR-011 user companion; the existing
  pillar-2 seed surface. T-2 cites this directly.
- ADR-011 (`docs/decisions/011-stability-model.md`) — the curated-combo
  pinned-version stability decision.
- AGT-02 bats test + `plugin/catalog/agents/claude-code/install.sh` — T-1
  evidence.

### Established Patterns

- Voice rule (Pitfall, applied here too): every claim about an unshipped
  behaviour MUST appear in a sentence whose grammatical subject is "we" /
  "our roadmap" / an explicit milestone identifier — never "AgentLinux +
  present-tense verb." Direction subsection of the Decision summary applies
  this rigorously.
- Phase-close audit convention: `.planning/phases/13-pillar-2-exploration/13-AUDIT.md`
  cites file path + line range of Decision summary + grep transcript; gate
  emits GREEN before phase closes.

### Integration Points

- Phase 15 (Strategy Doc) lifts the Decision summary verbatim into
  `docs/STRATEGY.md` Pillar 2. The Decision summary section heading
  (`## Decision summary`) is Phase 15's grep anchor — must be exact.
- Phase 14 (Pillar 3 Candidate Exploration) reads this CONTEXT.md as prior
  context to avoid re-deciding pillar boundaries.
- Phase 16 (Website Refresh) consumes the Today / Direction split for the
  pillar 2 card (SITE-02, SITE-03).

</code_context>

<specifics>
## Specific Ideas

- **RTK is named as the canonical `optimum` preset example** (token-efficiency
  proxy that improves any agent run on AgentLinux without configuration).
  Naming RTK in the Decision summary makes the differentiator concrete; the
  full `optimum` contents lock in a future milestone.
- **Profile example: `web-development`** — playwright-cli + browser deps.
  Names the orthogonal-axis concept concretely without locking the full list.
- **Compat-guarded update flow language:** "AgentLinux holds the default
  version set at last-known-good when upstream breaks a curated combo, and
  rolls forward only after a verified-compatible upstream fix lands in CI."
  This phrasing should appear (in spirit, not necessarily verbatim) in the
  Decision summary so D-1 is a falsifiable position.
- **The hard-reframe paragraph should explicitly call out that we are not
  an agent product.** This is the load-bearing claim of the doc and the
  rejection rationale for the entire research SUMMARY §4 framing.

</specifics>

<deferred>
## Deferred Ideas

- **Specific `must-haves` contents** — locks in the milestone where the preset
  framework ships (v0.6+). v0.3.3 names Claude Code + Codex illustratively.
- **Specific `optimum` extras beyond RTK** — locks when the preset framework
  ships. v0.3.3 names RTK as canonical example only.
- **Specific profile contents** — `web-development` is named as the canonical
  example; full profile list and exact tools lock when the profile framework
  ships.
- **Mechanism for compat-guarded update flow** — whether implemented via a
  CI matrix, an `agentlinux upgrade` reconciliation policy, or both. Pillar-2
  direction commits to the *outcome* (hold-and-wait); the mechanism locks in
  the v0.6+ implementation milestone.
- **`agentlinux install --preset` / `--profile` CLI surface details** — flag
  syntax, default-preset choice, interaction with existing `agentlinux install
  <name>` form. Decided in the implementation milestone.
- **Whether to upstream-report breakage as an explicit pillar value** —
  decided as side-effect, not commitment, in this phase. May be revisited if
  the maintenance cadence proves it's a load-bearing trust signal.
- **Pillar-3 substance** — entirely deferred to Phase 14.

</deferred>
