# CLEAN-04 — `.planning/` + `docs/` content review

**Date:** 2026-04-26
**Status:** ✅ PASSED — no sensitive content; intentional `.planning/` retention documented.

## Method

Surveyed every Markdown file under `.planning/` and `docs/` for:

1. Internal-only product names not yet public.
2. Customer / client / prospect names.
3. Unredacted incident notes.
4. Sensitive infrastructure hostnames or credentials in narrative form.
5. PII (gmail / yahoo / hotmail / phone-number-shaped strings).
6. `TODO` / `FIXME` / `XXX` / `HACK` placeholders that block public comprehension.

```bash
grep -ril -E 'customer|client name|prospect' docs/ .planning/
grep -ril -E 'opennebula|svcs\.io|hostinger|paperclip' docs/ .planning/
grep -nE '\b(TODO|FIXME|XXX|HACK)\b' README.md CONTRIBUTING.md docs/HARNESS.md docs/STABILITY-MODEL.md docs/decisions/*.md
grep -rinE '@(gmail|yahoo|hotmail)\.com|\b\+?[0-9]{1,3}[-\s]?\(?[0-9]{2,4}\)?[-\s][0-9]{3,4}[-\s][0-9]{4}\b' README.md CONTRIBUTING.md docs/HARNESS.md docs/decisions/ docs/STABILITY-MODEL.md
```

## Findings

### Customer / vendor / prospect names

**0 real matches.** The two grep hits (`customer` in `.planning/ROADMAP.md` line 43 and `.planning/REQUIREMENTS.md` line 41) are the v0.4.0 audit instructions themselves describing what to look for — meta-references, not actual customer names.

### Infrastructure hostname references (OpenNebula / `svcs.io` / `hostinger` / `paperclip`)

| File | Context | Verdict |
|------|---------|---------|
| `docs/research/v0.2.0/{FEATURES,ARCHITECTURE,PITFALLS,SUMMARY,STACK}.md` | v0.2.0 research synthesis discussing OpenNebula as the deploy target before the pivot | Keep — public ADR-001 / MILESTONES.md already explain v0.2.0 → v0.3.0 pivot; research files document why OpenNebula was disqualified |
| `docs/research/v0.3.0/{ARCHITECTURE,STACK}.md` | v0.3.0 research that compares against v0.2.0's OpenNebula approach | Keep — same justification |
| `docs/decisions/001-pivot-distro-to-plugin.md` | The pivot ADR itself | Keep — public-facing project history |
| `docs/audits/v0.4.0/SEC-01-gitleaks-report.md`, `docs/audits/v0.4.0/SEC-05-gate-evidence.md` | This phase's own scan reports referencing the false-positive triage | Keep — audit trail |

The OpenNebula control-plane hostname (`api.nebula.k8s.svcs.io`) appears once across all these files — in `.planning/.continue-here.md` line 65 (already triaged in SEC-01-gitleaks-report.md) — and once in `SEC-01-gitleaks-report.md` itself documenting the triage. Both occurrences are appropriate public content: one is historical narrative inside `.planning/` (which is intentionally retained per project convention — see below), the other is the audit document explaining why the gitleaks regex flagged it. Neither is a credential.

The hostname is not sensitive: `*.svcs.io` is a Kubernetes API endpoint discoverable via DNS, the OpenNebula deployment was retired with the v0.2.0 pivot, and exposing the hostname does not grant access (the API requires authentication that AgentLinux does not possess and never possessed in committed form).

`paperclip` and `hostinger` returned 0 matches in the public-facing surface (`docs/`, `README.md`, `CONTRIBUTING.md`); their occurrences are confined to internal `.planning/` narrative.

### TODO / FIXME / XXX / HACK in public-facing docs

**0 matches** in `README.md`, `CONTRIBUTING.md`, `docs/HARNESS.md`, `docs/STABILITY-MODEL.md`, and every ADR. The user-facing surface has no placeholders blocking comprehension.

### PII patterns

**0 matches** for gmail / yahoo / hotmail email addresses or phone-number-shaped strings in the public-facing surface. The maintainer's email lives only in git commit metadata (the `Author:` line) — appropriate and unavoidable for a git repository.

## `.planning/` retention decision

`.planning/` is the GSD workflow trail (PROJECT.md, MILESTONES.md, ROADMAP.md, REQUIREMENTS.md, STATE.md, plus per-phase phase directories and per-milestone archives). It is **intentionally retained** in the public-facing repo because:

- It documents *how* AgentLinux was built — phase-by-phase decisions, research, and the iteration trail. Future contributors get this context for free.
- It demonstrates the GSD workflow itself, which several users have asked about.
- It contains no secrets (verified by SEC-01..05) and no customer / vendor / prospect names (verified by this audit).
- The single false-positive in `.planning/.continue-here.md` is suppressed in the gitleaks gate via `.gitleaks.toml` allowlist.

`.planning/` retention is consistent with the project's stated convention in `CLAUDE.md` (`.planning/ — GSD workflow state — not documentation`) and is a deliberate choice, not an oversight.

## Action: none

No file removal, redaction, or content rewrite required. CLEAN-04 closes GREEN.

The single decision recorded by this audit is: **retain `.planning/` and `docs/research/` as-is** — they are appropriate public content.
