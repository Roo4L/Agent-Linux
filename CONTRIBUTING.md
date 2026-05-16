# Contributing to AgentLinux

Thanks for considering a contribution. AgentLinux is small, opinionated, and
behavior-test-driven — that shapes how we accept changes.

## Why this project exists

AgentLinux is framed around two pillars: **Time-to-productive** (the
work that gets a user from `curl | bash` to a first useful agent run on
a fresh box) and **Stability** (the curated toolchain holds compatible
across upstream churn). See [docs/VISION.md](docs/VISION.md) for the
full framing. Pillar 1 is what v0.3.0 already shipped — contributions
landing in the agent-user / runtime / catalog surface area are welcome
today. Pillar 2 is early-stage — the supply-chain monitoring + curated
catalog admission sub-concern (Phase 13 verdict, folded into Pillar 2)
locks at v0.3.3, but the mechanism work lands later (v0.6+). Pillar-2
contributions are welcome with the heads-up that the framing locked in
v0.3.3 and the implementation primitives ship in a later milestone.

## Quick start

1. **File an issue first** for anything non-trivial. We avoid surprise PRs that
   land scope we'd have pushed back on. Two-line bug reports and "hey, would
   you accept a PR for X?" issues are great.
2. **Fork the repo, create a feature branch off `master`.** We do not accept
   force-pushes to `master`; branch protection is on.
3. **Run `pre-commit run --all-files` locally** before pushing. CI runs the
   same hooks (shellcheck, shfmt, biome, catalog-schema validation, gitleaks);
   pushing without running them locally just delays the round-trip.
4. **Run the Docker bats matrix** for any change that touches `plugin/`:

   ```bash
   ./tests/docker/run.sh ubuntu-22.04
   ./tests/docker/run.sh ubuntu-24.04
   ```

   Both must pass. The Docker matrix is fast enough (~2-3 minutes per image)
   that there is no reason to skip it.

5. **Open a PR.** Reference the issue. Describe what behavior changed and
   which `BHV-XX` / `RT-XX` / `AGT-XX` / `CLI-XX` / `CAT-XX` / `INST-XX` /
   `HRN-XX` / `TST-XX` / `DOC-XX` requirements are touched.

## Behavior-test contract

`tests/bats/*.bats` is the spec. Implementation may change freely as long as
the suite stays green. PRs that change observable behavior should add or
update a `@test` that cites the relevant requirement ID in its description.

See [`docs/HARNESS.md`](docs/HARNESS.md) §3 (test harness layout), §4 (review
loop), and §5 (skill convention).

## Review loop

Before requesting review, run the project's review loop on changed files per
`docs/HARNESS.md` §4. Reviewers applied by file type:

- Bash → `bash-engineer`, `security-engineer`, `qa-engineer`
- TS/JS → `node-engineer`, `security-engineer`, `qa-engineer`
- Bats → `qa-engineer`, `behavior-coverage-auditor`
- Catalog recipes → `catalog-auditor`, `security-engineer`
- Docs → `technical-writer`, `fact-checker`

You don't have to use the same automated reviewers we do — manual review of
the same dimensions (correctness, security, test coverage, behavior-spec
alignment) is fine.

## Conventions

- **Never `sudo npm install -g` anywhere.** Always `sudo -u agent -H npm
  install -g`. This is the bug class AgentLinux exists to eliminate.
- **No agent is installed by default.** New catalog entries ship as
  *available*; users opt in via `agentlinux install <name>`.
- **Behavior tests are the spec, not the implementation.** Don't pin
  implementation details (`npm` vs native installer, shim layout, etc.) as
  requirements unless behavior depends on it.
- **No wrapper shims at `/usr/local/bin/` pointing at agent-owned binaries.**
  That's the recursive-shim anti-pattern that breaks self-update.
- **Pre-commit must stay green.** If a hook fires on your change, fix the
  underlying issue rather than skipping the hook.

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
