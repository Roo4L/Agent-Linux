# Pillar 3 Candidate Exploration — Security Hardening (declined as a pillar)

> Phase 14 verdict. Phase 15 lifts the `## Decision summary` section verbatim
> into `docs/STRATEGY.md` Appendix B's "Security Hardening" theme entry (not
> into a Pillar 3 — verdict (b) means there is no Pillar 3). DOC-05
> (ADR-012 forward-reference to a Pillar 3) closes as N/A in `15-AUDIT.md`;
> the unresolved ADR-012 tension is recorded inside Pillar 2's STRATEGY.md
> section as a known limitation, not via an ADR file edit.
>
> Locked: 2026-05-10. Source: `.planning/research/SUMMARY.md` §5,
> `.planning/research/FEATURES.md` Pillar 3 section (lines 97-200),
> `.planning/research/PITFALLS.md`. Locked decisions:
> `.planning/phases/14-pillar-3-candidate-exploration/14-CONTEXT.md`.

## Verdict

**Verdict:** (b) Fold into Pillar 2 as sub-concern. Security is not a separate pillar in v0.3.3.

The one substantive forward-looking commitment we draw from the security
landscape — active supply-chain monitoring + curated catalog admission — folds
into Pillar 2 as a sub-concern of its compat-guarded version pinning gate.
Only two pillars ship in `docs/STRATEGY.md`. DOC-05 (ADR-012's forward-reference
to a Pillar 3) closes as N/A in `15-AUDIT.md`; the unresolved tension is
recorded inside Pillar 2's section as a known limitation. "Security Hardening"
stays as a v0.6+ `opportunistic` theme in Appendix B, not as a pillar.

## What folds into Pillar 2

The one forward-looking commitment we hold from the security landscape is
**active supply-chain monitoring + curated catalog admission**, mechanism-shared
with Pillar 2's compat-guarded version pinning gate. Three parts:

1. **We monitor public supply-chain disclosures.** Our roadmap commits to
   tracking Shai-Hulud-class npm worm events, chalk/debug-class 2FA-phishing
   events, and TrustFall-class one-click remote-code-execution (RCE) events
   in coding agents. We adopt OWASP LLM Top 10 v2025, the Lethal Trifecta,
   and the Agents Rule of Two as reference frames.
2. **We refuse to bump pinned versions to compromised releases.** Pillar 2's
   compat-guarded gate gains a security check alongside the compatibility
   check. If a pin candidate has known compromise (revoked provenance,
   withdrawn release, public CISA / Unit 42 / Wiz advisory), our roadmap
   holds the prior pin until upstream re-issues the artifact.
3. **We keep new, untested, or unreviewed projects out of the catalog by
   default.** Admission criteria in spirit: existing security-research track
   record + behaviour-tested via the TST-08 4-gate pipeline + maintainer
   reputation. No sight-unseen admission. The codified policy locks at the
   milestone where the catalog admission framework ships.

This is a position **infrastructure** can take that a thin wrapper or a
single-tool installer cannot. The non-commitment side — what we deliberately
do not do (line-by-line upstream code audit, model-level guardrails, sandbox
runtime) — is enumerated under Decision summary's non-goals below.

## Threat landscape we considered

We acknowledge the late-2025 threat landscape and decline to commit to the
heavy defenses below as pillar substance. Verdict (b) means "we know about
this, we have chosen not to make a pillar commitment, and here is the
one-line rationale."

- **OWASP LLM Top 10 v2025.** LLM01 prompt injection (direct + indirect)
  remains the dominant agent-security risk regardless of vendor. We adopt
  OWASP's taxonomy as the reference frame in our supply-chain monitoring
  commitment; we do not commit to model-level mitigations (NG-1).
- **Simon Willison's Lethal Trifecta + Meta AI's Agents Rule of Two.** A
  coding agent with untrusted input + sensitive data access + external
  communication is fundamentally exploitable; the deployable framing is
  "hold ≤2 or operate under human-in-the-loop." We cite both as the framing
  language; we do not enforce the Rule of Two on the agent's behalf.
- **Shai-Hulud npm worm** (CISA AA25, Sept-Nov 2025). Self-replicating worm;
  ~25,000 malicious repositories across ~350 maintainers in the 2.0 wave;
  postinstall harvests credentials and re-publishes from compromised
  accounts. Pillar 2's `pinned_version` (ADR-011) closes the `--all-latest`
  window incidentally; our supply-chain monitoring covers the residual risk
  that a pin candidate is itself compromised.
- **chalk + debug + 16 packages compromise** (Sept 8, 2025). Phished
  maintainer 2FA on `npmjs.help`; ~2 hours live with billions of weekly
  downloads. Same attack class as Shai-Hulud; same monitoring response.
- **TrustFall** (Adversa AI disclosure, 2025). One-click RCE in Claude Code,
  Cursor, Gemini CLI, and GitHub Copilot via crafted untrusted source. The
  pattern is cross-vendor; properly the coding-agent vendor's surface.
- **Cline data exfiltration via markdown image** (embracethered.com, Aug
  2025). Agent renders markdown image whose URL contains exfiltrated `.env`
  content; under auto-approve mode this happens with no UI prompt. Same
  vendor-surface disposition as TrustFall.

## Defenses we considered

We considered the published defenses against the above and decline to commit
to any of them as pillar substance under verdict (b). Each lives in Appendix
B of `docs/STRATEGY.md` as a v0.6+ `opportunistic` theme entry, eligible to
mature into a milestone if a future user need justifies it.

Each defense below is declined as pillar substance and lives in Appendix B's
Security Hardening theme, eligible to mature into a milestone if a future
user need justifies it.

- **npm provenance + Sigstore signing.** `npm audit signatures` verifies a
  package's build identity; ~12.6% of popular packages publish provenance as
  of 2025; npm Trusted Publishing (Jul 2025) removes long-lived API tokens.
  Closes the maintainer-account-takeover impact window.
- **SLSA framework + in-toto attestations.** Graded supply-chain integrity
  levels; SLSA L3 is achievable for first-party catalog snapshots. Today we
  ship "SHA256 + maintainer 2FA + branch protection" per README §Security.
- **cosign-signed catalog snapshots.** Signed catalog releases would close
  the gap left by README §Security's "GPG signatures on the v0.4+ roadmap."
- **bubblewrap-based per-recipe sandbox.** Linux-native unprivileged
  sandboxing primitive; Anthropic's devcontainer reference uses it with an
  iptables/ipset egress firewall (default OUTPUT DROP) and a curated
  allowlist. The primitives exist already in the kernel; a user who wants
  this posture composes them themselves.
- **Capability-scoped sudoers replacing ADR-012 NOPASSWD ALL** (passwordless
  sudo to any command). Microsoft SCOM-style allowlists scoped to
  `/usr/bin/apt-get install *`, `/usr/bin/systemctl restart *`, etc.
  Phase 5 showed agents need a long tail of commands and the allowlist is
  its own maintenance burden.

## ADR-012 tension

ADR-012 (`agent ALL=(ALL) NOPASSWD: ALL` — passwordless sudo to any command)
was a defensible scope choice at v0.3.0. The agent was framed as a trusted
coworker; the alternative (capability-scoped sudoers allowlists) was rejected
because Phase 5 showed agents need apt + systemctl + many other things and
an ever-growing allowlist is its own maintenance burden.

After Shai-Hulud, TrustFall, and the Lethal Trifecta framing in late 2025,
that "trusted coworker" framing is harder to defend. A single successful
prompt injection on the agent — one bad README in one cloned repo — converts
the agent into an adversary with NOPASSWD root, and the blast radius is the
entire host. Anthropic shipped Claude Code sandboxing (bubblewrap + network
firewall) in 2025 against the same threat class.

Position: defensible v0.3.0 scope choice, recognized debt now. Resolution
lives in Appendix B's Security Hardening theme as a v0.6+ `opportunistic`
entry, not as a pillar commitment.

## Why verdict (b) and not (a/c/d)

Per Pitfall #13 rejected-alternatives discipline, the three rejected verdicts
each get one paragraph so future readers do not re-open the question.

- **(a) Full pillar — rejected.** A full Pillar 3 needs ≥2 honest
  already-shipped table-stakes, ≥1 differentiator, and ≥2 non-goals. ADR-006
  (curl-pipe-bash + SHA256) and ADR-011 (curated combo with pinned versions)
  are stability and installer-integrity mechanisms, not security pillars;
  stretching them into "security" framing forces aspirational drift per
  Pitfall #6 (the very risk this milestone exists to defend against).
- **(c) Cross-cutting Guiding Principle — rejected.** Same substance as (b)
  in a less prominent location. Pillar 2 already commits to compat-guarded
  version pinning; supply-chain monitoring is a natural extension of the
  same mechanism. Folding into Pillar 2 keeps the commitment visible where
  reviewers actually read.
- **(d) Explicit non-goal — rejected.** Contradicts the supply-chain
  monitoring commitment. We are taking a position on supply-chain hygiene;
  we are not taking a position on agent runtime sandboxing or model-level
  guardrails.

## Decision summary

> Phase 15 lifts this section verbatim into `docs/STRATEGY.md` Appendix B's
> "Security Hardening" theme entry (NOT into a Pillar 3 section).

Verdict: (b) Fold into Pillar 2 as a sub-concern — security is not a separate
pillar in v0.3.3.

**What folds into Pillar 2 (the one new commitment):** Active supply-chain
monitoring + curated catalog admission, mechanism-shared with Pillar 2's
compat-guarded version pinning gate. Three parts: monitor public supply-chain
disclosures (Shai-Hulud-class, chalk/debug-class, TrustFall-class events) and
adopt OWASP LLM Top 10 v2025 + Lethal Trifecta + Agents Rule of Two as
reference frames; refuse to bump pinned versions to releases with known
compromise; keep new, untested, or unreviewed projects out of the catalog
by default (admission requires existing security-research track record +
TST-08 4-gate behaviour-test + maintainer reputation).

**Table-stakes that the fold subsumes (≥2):**

- Pillar 2's existing curated catalog with `pinned_version` per agent
  (ADR-011) — incidentally closes the `--all-latest` window for supply-chain
  attacks; documented as defense-in-depth under the fold.
- Pillar 2's existing curated catalog admission criteria — only `claude-code`,
  `gsd`, and `playwright-cli` admitted to date; no sight-unseen admission.

**Differentiators (≥1):** Active supply-chain monitoring + refusal to bump
pinned versions to compromised releases. Under verdict (b), this lives in
Pillar 2's STRATEGY.md section, not in a separate Pillar 3.

**Explicit non-goals:**

- **NG-1 — Not providing model-level guardrails.** Llama Guard, ShieldGemma,
  IBM Granite Guardian, Prompt Guard, NeMo Guardrails — properly the agent
  or model vendor's surface. We cite as context, never as a deliverable.
- **NG-2 — Not vetting the content of upstream agent code.** We pin and
  monitor; we never line-by-line audit Claude Code's source. Catalog
  acceptance is by behaviour + provenance signals + maintainer reputation +
  active supply-chain monitoring — not by upstream code review.
- **NG-3 — Not becoming a sandbox runtime.** No commitment to ship an
  `agentlinux harden` profile, capability-scoped sudoers, bubblewrap-based
  recipes, Landlock or seccomp-bpf wrappers, or iptables egress allowlists.
  These primitives exist already in the kernel and elsewhere; a user who
  wants that posture composes the off-the-shelf primitives themselves.
  gVisor, Firecracker, and Kata Containers exist and we do not compete.

**Recommended priority tag:**

- The fold inherits Pillar 2's `next-milestone` priority tag. Pillar 3 does
  not exist under verdict (b), so there is no separate pillar-3 tag.
- Appendix B's Security Hardening theme is tagged `opportunistic` for v0.6+
  and contains the declined defenses: capability-scoped sudoers replacing
  ADR-012, cosign-signed catalog releases, npm provenance verification in
  CI, bubblewrap-based per-recipe sandbox profile, iptables egress allowlist.
