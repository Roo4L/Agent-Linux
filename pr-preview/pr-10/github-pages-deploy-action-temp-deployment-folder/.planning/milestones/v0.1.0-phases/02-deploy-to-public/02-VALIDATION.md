---
phase: 2
slug: deploy-to-public
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-09
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual validation (deployment verification) |
| **Config file** | none |
| **Quick run command** | `curl -sI https://agentlinux.org` |
| **Full suite command** | Manual checklist (see Per-Task Verification Map) |
| **Estimated runtime** | ~10 seconds (curl checks) |

---

## Sampling Rate

- **After every task commit:** Verify file syntax (YAML lint, HTML validation)
- **After every plan wave:** Full deployment verification after DNS propagation
- **Before `/gsd:verify-work`:** All 4 DEPL requirements verified via curl/dig commands
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | DEPL-04 | smoke | `cat .github/workflows/deploy.yml` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | DEPL-02 | smoke | `cat CNAME` | ❌ W0 | ⬜ pending |
| 02-01-03 | 01 | 1 | DEPL-01 | manual | `curl -sI https://agentlinux.org \| grep "server: github"` | N/A | ⬜ pending |
| 02-01-04 | 01 | 1 | DEPL-02 | manual | `dig agentlinux.org +short` | N/A | ⬜ pending |
| 02-01-05 | 01 | 1 | DEPL-03 | manual | `curl -sI https://agentlinux.org \| grep "HTTP/2 200"` | N/A | ⬜ pending |
| 02-01-06 | 01 | 1 | DEPL-04 | manual | Push change, verify Actions workflow completes | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- No test infrastructure needed — this phase is infrastructure/deployment configuration
- Validation is done via external HTTP checks against the live site after deployment
- File existence checks verify configuration files are created correctly

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Site hosted on GitHub Pages | DEPL-01 | Requires live deployment | Run `curl -sI https://agentlinux.org` and verify `server: GitHub.com` header |
| Custom domain resolves | DEPL-02 | Requires DNS propagation | Run `dig agentlinux.org +short` and verify GitHub Pages IPs (185.199.108-111.153) |
| HTTPS enabled | DEPL-03 | Requires certificate provisioning | Run `curl -sI https://agentlinux.org` and verify HTTP/2 200 response |
| Auto-deploy on push | DEPL-04 | Requires end-to-end workflow | Push a trivial change to main, verify GitHub Actions workflow completes and site updates |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
