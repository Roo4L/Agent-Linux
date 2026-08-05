# Contributing to AgentLinux

Thanks for considering a contribution. AgentLinux is small, opinionated, and
behavior-test-driven — that shapes how we accept changes.

## Repository layout

Three concerns share the repo, plus the docs and agent harness they all use:

| Directory | What it is |
|---|---|
| `product/` | **The product** — the installable AgentLinux plugin. Holds `rust/`, `plugin/`, `packaging/`, `tests/` and `scripts/`, all relative to `product/`. |
| `site/` | **The website** — everything served at agentlinux.org |
| `deck/` | **The deck** — presentation design code and its generator |

The site bundle pulls `install.sh` from `product/packaging/` — the site's only
tie to `product/`, so edit the `curl | bash` one-liner there, never under `site/`.

`docs/` is reference documentation and is fair game for PRs. `.planning/` holds
the maintainer's roadmap and planning notes; contributions never need to touch
it. `agents/`, `.claude/` and `.codex/` configure the coding agents we develop
*with* — they are not part of the shipped product. Root `scripts/` holds the
tooling that has nowhere better to live: generators for a directory that is
published verbatim, gates whose own rules forbid them from sitting inside
their subject, and scripts that span two concerns.
(Root `scripts/` vs `product/scripts/`: a tooling script lives with the
concern it serves, so anything gating `product/` — including its tests —
goes under `product/scripts/`.)

A fuller annotated tree is in
[`docs/HARNESS.md` §1.1](docs/HARNESS.md#11-repository-structure) — that
document is mostly about how we run agent-assisted development, but §1.1 is the
canonical layout.

## Quick start

1. **File an issue first** for anything non-trivial. We avoid surprise PRs that
   land scope we'd have pushed back on. Two-line bug reports and "hey, would
   you accept a PR for X?" issues are great.
2. **Fork the repo, create a feature branch off `master`.** We do not accept
   force-pushes to `master`; branch protection is on.
3. **Run `pre-commit run --all-files` locally** before pushing. CI runs the
   same hooks — shellcheck, shfmt, gitleaks, the catalog-schema and
   version-lockstep gates, and several repo-hygiene checks; run the command
   rather than guessing which apply. Pushing without running them locally just
   delays the round-trip.
4. **Run the Docker bats matrix** for any change that touches `product/plugin/`:

   ```bash
   ./product/tests/docker/run.sh ubuntu-24.04
   ./product/tests/docker/run.sh almalinux-9
   ```

   Both must pass — they are the two arms CI gates every PR on. The Docker
   matrix is fast enough (~2-3 minutes per image) that there is no reason to
   skip it.

5. **Open a PR.** Reference the issue. Describe what behavior changed and
   which `product/tests/bats/*.bats` test files cover it.

## Behavior-test contract

`product/tests/bats/*.bats` is the spec. Implementation may change freely as long as
the suite stays green. PRs that change observable behavior should add or
update a `@test` that names the behavior it pins.

See [`docs/HARNESS.md`](docs/HARNESS.md) §3 (test harness layout), §4 (review
loop), and §5 (skill convention).

## Review loop

Before requesting review, run the project's review loop on changed files per
the shared [`$review` skill](.claude/skills/review/SKILL.md). It maps changed
file types to portable reviewer roles; use your coding-agent host's native
subagent mechanism with the skill's read-only contract. Manual review of the
same dimensions (correctness, security, test coverage, behavior-spec
alignment) is an acceptable limited fallback when native subagents are not
available, but do not substitute another agent's CLI.

## License & contributor agreement

AgentLinux is licensed under the MIT License (see [LICENSE](LICENSE) and
[`docs/decisions/013-license-mit.md`](docs/decisions/013-license-mit.md)).

By submitting a pull request, you affirm that:

1. You have the right to contribute the changes (you wrote them, or you have
   permission from the copyright holder to relicense them under MIT), and
2. You agree your contribution may be incorporated into AgentLinux under the
   MIT license terms.

This is a lightweight "developer-certificate-of-origin"-equivalent — we do
not require a signed CLA, but the affirmation above is the same idea.

New source files added in your PR should include the SPDX identifier as the
first non-shebang comment line:

- Bash: `# SPDX-License-Identifier: MIT`
- TypeScript / JavaScript: `// SPDX-License-Identifier: MIT`
- JSON / Markdown / YAML: no SPDX line (no comment syntax / convention varies);
  the repo-level [LICENSE](LICENSE) applies.

## Reporting security issues

Do **not** open a public issue for security vulnerabilities. Use the
repository's Security tab to file a private advisory, or email the maintainer
listed in the `LICENSE` copyright line. We aim to acknowledge within 48 hours.

## Anything else?

Issues and PRs welcome. Pre-ask via an issue if your change is large; merging
small focused PRs is faster than rebasing one big one. Thanks for helping
make AgentLinux better.
