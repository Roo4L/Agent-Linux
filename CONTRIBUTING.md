# Contributing to AgentLinux

Thanks for considering a contribution. AgentLinux is small, opinionated, and
behavior-test-driven — that shapes how we accept changes.

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
   which `tests/bats/*.bats` test files cover it.

## Behavior-test contract

`tests/bats/*.bats` is the spec. Implementation may change freely as long as
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
