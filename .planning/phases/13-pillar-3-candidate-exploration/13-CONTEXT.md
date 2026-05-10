# Phase 13: Pillar 3 Candidate Exploration - Context

**Gathered:** 2026-05-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Decide whether security is a pillar at all in AgentLinux's redefined agenda,
and produce a written verdict (`docs/exploration/PILLAR-3-CANDIDATE-NOTES.md`)
that Phase 14 can lift verbatim into either (a) `docs/STRATEGY.md` Pillar 3,
(b) Pillar 2 sub-concerns, (c) cross-cutting Guiding Principles, or (d) the
`What we're explicitly *not* working on` list — without re-deciding at
authoring time.

The deliverable is *framing*, not new product capability. The verdict's named
commitments (if any) seed downstream roadmap themes (v0.6+) but do not ship
any of them in v0.3.3.

The phase carries the same hard reframe locked in Phase 12: AgentLinux is
*infrastructure*, not an agent product. It provisions the environment in
which agents run. Therefore commitments framed as "AgentLinux defends against
prompt injection" or "AgentLinux benchmarks token consumption" are out — we
do not run, score, isolate, or guardrail agents at the model layer.

</domain>

<decisions>
## Implementation Decisions

### Verdict — security is folded into Pillar 2 as a sub-concern

**Verdict (locked, user direction 2026-05-10):** **(b) No, security is not a
full pillar. The single substantive forward-looking commitment — active
supply-chain monitoring + curated catalog admission — folds into Pillar 2 as
a sub-concern.**

The doc's `## Verdict` heading carries one bolded `**Verdict:**` line so a
downstream `grep -E '\*\*Verdict:'` returns exactly one match. The verdict
text states (b) explicitly and names the consequence: only 2 pillars ship in
`docs/STRATEGY.md`; DOC-05 (ADR-012 forward-reference to Pillar 3) closes as
N/A; "Security Hardening" stays as a v0.6+ opportunistic theme in the
strategy doc's Appendix B, not as a pillar.

### Why (b) and not (a/c/d)

- **(a) Full pillar — rejected.** A full pillar 3 needs ≥2 honest
  already-shipped table-stakes, ≥1 differentiator, ≥2 explicit non-goals.
  The user explicitly rejected stretching ADR-006 (curl-pipe-bash + SHA256)
  and ADR-011 (curated combo + pinned versions) into "security" framing —
  they are stability + installer-integrity mechanisms, not security pillars.
  Without honest table-stakes, verdict (a) would force aspirational drift
  per Pitfall #6 (the very risk the milestone exists to defend against).
- **(c) Cross-cutting Guiding Principle — rejected.** Same substance as (b)
  but in a less prominent location. Pillar 2 already commits to compat-guarded
  version pinning; supply-chain monitoring is a natural extension of the same
  mechanism (curated combo + CI matrix + admission gate). Folding into pillar 2
  keeps the commitment visible in the pillars section, where reviewers actually
  read.
- **(d) Explicit non-goal — rejected.** Contradicts the user's supply-chain
  monitoring commitment. We *are* taking a position on supply-chain hygiene;
  we are not taking a position on agent runtime sandboxing or model-level
  guardrails.

### What folds into Pillar 2 (one forward-looking commitment)

**Active supply-chain monitoring + curated catalog admission** (locked,
user direction 2026-05-10). Our roadmap commits to:

- Monitoring public supply-chain disclosure news (Shai-Hulud-class npm worm
  events, chalk/debug 2FA-phishing class events, TrustFall-class one-click
  RCEs in coding agents, OWASP LLM Top 10 v2025 + Lethal Trifecta + Agents
  Rule of Two as adopted reference frames).
- Refusing to bump pinned versions to releases known to be compromised by
  supply-chain attacks. The compat-guarded version pinning gate already in
  Pillar 2 gains a security check alongside the compatibility check.
- Keeping new / untested / unreviewed projects out of the catalog by
  default. Catalog admission criteria: existing security-research track
  record + behaviour-tested via TST-08 4-gate pipeline + maintainer
  reputation. We do not admit projects sight-unseen.

This is a position **infrastructure** can take that a thin wrapper or a
single-tool installer cannot. It is **not** an upstream-source-code-audit
commitment — we monitor public disclosures, we do not line-by-line review
Claude Code's source.

### Explicit non-goals (drawn from research §5, locked 2026-05-10)

These are restated in `PILLAR-3-CANDIDATE-NOTES.md` so the doc body documents
why specific research-surfaced commitments were *not* taken on:

- **NG-1 — Not providing model-level guardrails.** Llama Guard, ShieldGemma,
  IBM Granite Guardian, Prompt Guard, NeMo Guardrails — properly the agent
  or model vendor's surface. We cite as context, never as deliverable.
- **NG-2 — Not vetting the content of upstream agent code.** We pin and
  monitor; we never audit Claude Code's source line-by-line. Catalog
  acceptance is by behaviour + provenance signals + maintainer reputation +
  the supply-chain monitoring above — not by upstream code review.
- **NG-3 — Not becoming a sandbox runtime.** No commitment to ship an
  `agentlinux harden` profile, capability-scoped sudoers, bubblewrap-based
  recipes, Landlock / seccomp-bpf wrappers, or iptables egress allowlists.
  These primitives exist already in the kernel and elsewhere (Anthropic's
  devcontainer demonstrates the pattern); a user who wants that posture
  composes the off-the-shelf primitives themselves. gVisor, Firecracker,
  Kata Containers exist and we do not compete.

### ADR-012 NOPASSWD ALL — noted but unresolved

The `agent ALL=(ALL) NOPASSWD: ALL` choice (`docs/decisions/012-agent-user-full-sudo.md`)
is a real security debt acknowledged honestly: a single successful prompt
injection on the agent (one bad README in one cloned repo) converts the
agent into an adversary with NOPASSWD root, and the blast radius is the
entire host. Per the post-Shai-Hulud / post-TrustFall / post-Lethal-Trifecta
landscape (late 2025), the "trusted coworker" framing in ADR-012 is harder
to defend than at v0.3.0.

**Position locked under verdict (b):** the tension is documented in
`PILLAR-3-CANDIDATE-NOTES.md` and noted in pillar 2's compat-guarded section
as a known limitation. *Revisiting* it (capability-scoped sudoers + opt-in
sandbox profile) is a v0.6+ **opportunistic** theme in `docs/STRATEGY.md`
Appendix B, not a pillar commitment. DOC-05 (ADR-012 forward-reference to
ADR-015 + STRATEGY.md Pillar 3) closes as N/A in `14-AUDIT.md` since pillar 3
does not exist; the unresolved tension is recorded in pillar 2's section
instead.

### EXPL-02 grep gate — citation strategy

The required regex `(OWASP|Lethal Trifecta|Rule of Two|Shai-Hulud|chalk|TrustFall|Cline|provenance|SLSA|cosign|bubblewrap|ADR-012)`
must return ≥7 hits. The doc body's sections — `## Threat landscape we
considered`, `## Defenses we considered`, `## ADR-012 tension` — cite
these names explicitly to justify the verdict. Verdict (b) does **not**
mean we ignore the threat landscape; it means we acknowledge the landscape
and decline to commit to the substantive defenses (cosign, bubblewrap,
capability-scoped sudoers) as pillar substance.

### Priority tag

Pillar 3 does not exist under verdict (b). The supply-chain monitoring
commitment is a Pillar 2 sub-concern and inherits Pillar 2's `next-milestone`
priority tag. Appendix B's "Security Hardening" theme carries an
**`opportunistic`** tag (consistent with STRAT-04's lock that exactly one
forward-looking pillar carries `next-milestone`; the rest are
`opportunistic`).

### Decision summary structure (per EXPL-02 success criterion 4)

For verdict (b), the `## Decision summary` section at the bottom of the doc
contains:

- **Verdict (single line):** `**Verdict:** (b) Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3.`
- **What folds into Pillar 2 (the one new commitment):** Active supply-chain
  monitoring + curated catalog admission, mechanism-shared with the
  compat-guarded version pinning gate.
- **Table-stakes that the fold subsumes (≥2):** Pillar 2's existing curated
  catalog with pinned versions (ADR-011) — incidentally closes the
  `--all-latest` window for supply-chain attacks. Pillar 2's existing
  curated admission criteria — only claude-code, gsd, playwright-cli admitted
  to date; new projects are not admitted sight-unseen.
- **Differentiators (≥1):** The supply-chain monitoring + compromised-version
  refusal commitment above.
- **Explicit non-goals (≥2):** NG-1, NG-2, NG-3 as detailed above.
- **Recommended priority tag:** Pillar 2's `next-milestone` carries the fold;
  Appendix B "Security Hardening" theme is `opportunistic` for v0.6+.
- **DOC-05 disposition:** Closes as N/A in `14-AUDIT.md`. Single-line
  rationale: pillar 3 does not exist; the ADR-012 tension is recorded in
  pillar 2's section as a known limitation.

### Claude's Discretion

- Section ordering and prose voice for `PILLAR-3-CANDIDATE-NOTES.md` body.
- Specific phrasing of the rejection rationale for each cited research
  artefact (cosign, bubblewrap, capability-scoped sudoers, etc.) — must be
  consistent with verdict (b)'s framing ("we acknowledge the threat
  landscape; we decline to commit to the heavy defenses as pillar substance").
- Whether the body's "Considered and rejected" subsection cites each defense
  as a separate paragraph or as a list — Claude picks the form that hits ≥7
  distinct grep matches naturally.
- Phrasing of the supply-chain monitoring commitment in the doc body,
  provided the substance matches the user direction locked above.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets (no code changes in Phase 13 — doc-only)

- `.planning/research/SUMMARY.md` §5 — pillar-3 substance summary, named
  threat landscape, named defenses, ADR-012 §E recommended phrasing. Source
  raw material.
- `.planning/research/FEATURES.md` Pillar 3 section (lines 97-200) — full
  threat-and-defense inventory with citation links to OWASP, Anthropic,
  Adversa AI, embracethered.com, Unit 42, Wiz, sigstore.dev. Source raw
  material.
- `.planning/research/PITFALLS.md` Pitfall #6 (aspirational drift, highest
  risk) + Pitfall #14 (false-advertising on website) + Pitfall #13
  (rejected-alternatives discipline) — informs the "considered and rejected"
  framing.
- `docs/exploration/PILLAR-2-NOTES.md` (Phase 12 verdict, 2026-05-10) — prior
  phase output. Pillar 2's Decision summary is the lift target Phase 14
  consumes; this phase's verdict (b) extends it.
- `docs/decisions/006-curl-pipe-bash-plus-deb.md` (ADR-006) — installer
  SHA256 verification (cited as installer-integrity mechanism, NOT as a
  security-pillar table-stake under verdict (b)).
- `docs/decisions/011-stability-first-version-pinning.md` (ADR-011) — curated
  combo pinned versions (cited as supply-chain defense-in-depth under the
  fold; closes the `--all-latest` window).
- `docs/decisions/012-agent-user-full-sudo.md` (ADR-012) — NOPASSWD ALL
  tension. Cited explicitly in the doc body to satisfy the EXPL-02 grep gate
  and to make the unresolved tension visible.
- `docs/decisions/014-secret-remediation-noop.md` (ADR-014) — past
  incident-response artefact. Cited briefly for context, not as pillar
  substance.

### Established Patterns

- Voice rule (Pitfall #6, applied here too): every claim about an unshipped
  behaviour MUST appear in a sentence whose grammatical subject is "we" /
  "our roadmap" / an explicit milestone identifier — never "AgentLinux +
  present-tense verb." The supply-chain monitoring commitment uses
  forward-looking voice ("our roadmap commits to monitoring...").
- Phase-close audit convention: `.planning/phases/13-pillar-3-candidate-exploration/13-AUDIT.md`
  cites file path + line range of the `## Verdict` section + line range of
  the `## Decision summary` section + the grep transcripts; gate emits
  GREEN before phase closes. Note: the ROADMAP success criterion 5 line
  references `.planning/phases/13-pillar-3-exploration/...` (without
  "candidate") — typo predating the canonical phase slug. The audit lands
  at the canonical path and the audit file notes the divergence.
- Phase 12 voice-rule and reviewer-pass discipline (fact-checker +
  technical-writer pass after first draft) carries forward.

### Integration Points

- **Phase 14 (Strategy Doc + Downstream Updates):** lifts the Decision
  summary verbatim. STRAT-03 ships 2 pillars (not 3). STRAT-04 has 2 pillar
  priorities. STRAT-09 Appendix B carries "Security Hardening" as a v0.6+
  `opportunistic` theme. DOC-05 closes as N/A in `14-AUDIT.md` with the
  one-line rationale recorded.
- **Phase 15 (Website Refresh):** `#pillars` section ships 2 cards (SITE-02);
  pillar-3 card is omitted; voice-rule grep gate (SITE-06) applies as
  written but the pillar-3 forbidden-verb classes still apply across the
  whole page (no `AgentLinux defends|protects|prevents|hardens` anywhere).
- **AL-7 (Jira epic):** the verdict is recorded as a comment on AL-7 with
  the rationale ("supply-chain monitoring commitment kept; pillar 3 framing
  declined") so the epic's history reflects the agenda redefinition.

</code_context>

<specifics>
## Specific Ideas

- **The doc's verdict line is the only `**Verdict:**` bolded line in the
  file** — single match for the grep anchor. Rest of the body uses regular
  prose; section headings carry the substance.
- **The `## Threat landscape we considered` section cites OWASP LLM Top 10
  v2025 + Lethal Trifecta + Agents Rule of Two + Shai-Hulud + chalk/debug +
  TrustFall + Cline-via-markdown** — at minimum 5 grep tokens from this
  block alone. Plus `## Defenses we considered` adds npm provenance, SLSA,
  cosign, bubblewrap, capability-scoped sudoers — at least 3 more. Plus
  `## ADR-012 tension` adds the ADR-012 token. Total ≥7 distinct matches
  comfortably; the gate doesn't need careful counting.
- **The supply-chain monitoring commitment phrasing should explicitly
  reject "upstream code audit"** — readers of the doc must not infer we are
  signing up for distribution-style maintenance burden. Quote: "We monitor
  public disclosures; we never line-by-line audit Claude Code's source."
- **The ADR-012 tension paragraph adopts research §5E recommended phrasing
  in spirit** — "defensible scope choice at v0.3.0; recognized debt now that
  we acknowledge the late-2025 prompt-injection threat landscape;
  resolution is a v0.6+ opportunistic theme, not a pillar commitment."

</specifics>

<deferred>
## Deferred Ideas

- **`agentlinux harden` profile design** — capability-scoped sudoers,
  bubblewrap recipe wrappers, iptables/ipset egress allowlist, hardened
  CLAUDE.md skel fragment. NG-3 declines pillar commitment; if the
  opportunistic theme matures into a v0.6+ milestone, this is its design
  surface.
- **Cosign-signed catalog releases** — closes the README §Security "GPG
  signatures on the v0.4+ roadmap" gap. Not committed under verdict (b);
  may surface in Appendix B's `opportunistic` Security Hardening theme.
- **`npm audit signatures` CI lint + SBOM emission per release** — research
  §5 differentiator candidates. Not committed under verdict (b); same
  Appendix-B disposition as cosign.
- **`--ignore-scripts` opt-in policy for catalog recipes** — research §5
  differentiator candidate. Not committed under verdict (b).
- **Capability-scoped sudoers replacing ADR-012 NOPASSWD ALL** — same
  bucket; the opportunistic theme.
- **Specific catalog admission criteria language** — the supply-chain
  monitoring commitment names admission criteria in spirit ("existing
  security-research track record + TST-08 behaviour-tested + maintainer
  reputation"). The exact codified policy locks in the milestone where the
  catalog admission framework ships.
- **Bidirectional ADR back-references** — ADR-012 forward-reference to
  ADR-015 / STRATEGY.md is dropped (DOC-05 N/A). If pillar 3 ever revives
  the back-reference reactivates.

</deferred>
