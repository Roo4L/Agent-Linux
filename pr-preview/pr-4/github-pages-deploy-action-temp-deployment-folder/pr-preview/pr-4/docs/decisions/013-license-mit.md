# 013: MIT license for AgentLinux

**Status:** Accepted
**Date:** 2026-04-26
**Drives:** v0.4.0 LIC-01, LIC-02, LIC-03

## Context

v0.4.0 (Open-Source Release) flips the AgentLinux repository from private to public — issue AGE-6. A licensing decision is a hard prerequisite: an unlicensed public repo defaults to "all rights reserved" under copyright law and is effectively unusable by anyone who would otherwise install or contribute to it.

Three OSI-approved options were on the table:

| License | Permissiveness | Patent grant | Copyleft | Primary cost |
|---------|----------------|--------------|----------|--------------|
| MIT | Maximum | None (implicit, narrow) | None | Future patent disputes are not pre-resolved |
| Apache-2.0 | High | Explicit | None | Slightly more friction (NOTICE file + boilerplate) and license text is longer |
| GPL-3.0 | Lower | Explicit | Strong | Downstream consumers must also be GPL-licensed; chills closed-source adoption |

## Decision

**MIT.**

Rationale, in priority order:

1. **Maximum adoption surface.** AgentLinux is infrastructure — a one-command installer that other agents and toolchains will be installed *into*, then bundled / scripted / shipped by third parties (managed-cloud vendors, internal-dev-platform teams, agent-as-a-service operators). MIT removes every legal speed bump from that path. GPL would chill it; Apache-2.0's NOTICE / patent boilerplate, while harmless to most, adds friction without buying us anything we materially need.
2. **Dependency compatibility.** Our runtime and dev dependencies (Node.js, npm, Commander, ajv, semver, gitleaks, etc.) are MIT or MIT-compatible. MIT keeps the inbound license stack uniform and avoids the case where a future GPL-licensed dependency forces a license-cascade conversation.
3. **No pending patent strategy.** AgentLinux's value is operational (provisioner shape, ownership invariants, behavior-test contract) — not patentable subject matter. Apache-2.0's explicit patent grant is most valuable when contributors might hold patents that read on the contribution; we don't realistically face that exposure today, and if we do later, an MIT → Apache-2.0 relicense is doable while contributors are still few.
4. **Community recognition.** MIT is the dominant license in the JavaScript / Node.js / Linux-tooling adjacent ecosystem AgentLinux ships into. Familiarity reduces the "what is this license, can my company use it?" friction for first-time installers.

## Consequences

### Files & content

- A `LICENSE` file at repo root contains the MIT license text with copyright line `Copyright (c) 2026 Nikita Ivanov and AgentLinux contributors`. (Maintainer name reflects the current sole copyright holder; "and AgentLinux contributors" anticipates community contributions post-flip.)
- The `README.md` gains a `## License` section linking `LICENSE`. A shields.io license badge is included in the badge cluster near the top of the README.
- A new `CONTRIBUTING.md` at repo root states that contributions are accepted under the MIT license terms — submitting a PR is the contributor's affirmation that their work may be incorporated under MIT (developer-certificate-of-origin-equivalent, by reference).

### SPDX header policy

- **New files going forward** (post-2026-04-26) include an SPDX identifier line as the first non-shebang comment line. For bash: `# SPDX-License-Identifier: MIT`; for TypeScript: `// SPDX-License-Identifier: MIT`; for JSON files: skipped (JSON has no comment syntax — license is documented at repo level only).
- **Existing source files**: get the SPDX identifier added in a one-time backfill commit during Phase 7 for files that are clearly first-party AgentLinux source (`plugin/bin/*`, `plugin/lib/*`, `plugin/cli/src/*`, `scripts/*`, `tests/bats/*`, `tests/harness/run.sh`). Existing third-party content (vendored dependencies, generated files like `plugin/cli/dist/*`, anything under `node_modules/`) is **not** retrofitted — those carry their own upstream licenses.
- **Generated files** (`dist/`, `*.lock`, `package.json`'s ephemeral fields) carry no SPDX identifier; the repo-level LICENSE applies and adding identifiers to lockfiles would be churn.

### Patent posture

MIT does not include an explicit patent grant. AgentLinux maintainers accept the MIT-default narrow-implicit grant. If a future contribution materially incorporates patentable subject matter (none anticipated), the maintainer reserves the right to revisit the license — an MIT → Apache-2.0 relicense remains feasible while the contributor pool is small. This is documented here so a future revisit is a deliberate decision, not a surprise.

### Copyleft posture

MIT is explicitly non-copyleft. Downstream consumers may distribute AgentLinux (whole or in derivative form) under any license they choose. This is the intended outcome — operating-environment infrastructure should not impose downstream license obligations.

### Trademark posture

The "AgentLinux" name and the crab mascot SVG are **not** licensed under MIT. They remain controlled by the project maintainer for naming-clarity reasons (forks should pick their own name to avoid implying maintainer endorsement). This is a future ADR if/when forks materially exist; for v0.4.0 we note it here and add a one-line clarification in CONTRIBUTING.md.

### Reversibility

- **Forward-compatible relicenses** (MIT → MIT-OR-Apache-2.0 dual; MIT → Apache-2.0 sole) are feasible while contributor count is small. After meaningful third-party contributions land, relicensing requires unanimous (or majority, depending on chosen mechanism) contributor consent, which is a real ask.
- A move *from* MIT *to* GPL would require unanimous re-licensing because GPL is more restrictive than MIT — practically infeasible at scale. Do not adopt MIT as a placeholder for "we'll figure it out later."

## References

- OSI MIT license text: https://opensource.org/licenses/MIT
- SPDX identifier convention: https://spdx.dev/learn/handling-license-info/
- ADR-006 — curl-pipe-bash + .deb (the public install path; LICENSE must ride along on the release tarball so installed copies carry their license too — handled in `scripts/build-release.sh`).
