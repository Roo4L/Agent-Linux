# Mutation Testing — AgentLinux v0.3.0

Mutation testing introduces small intentional faults into the source (mutants) and
verifies the test suite catches each one. Mutation score (mutants killed / mutants
generated) is the **truth-meter** for test quality — it distinguishes tests that
assert real behavior from tests that merely execute lines.

## Scope

| Target | Tool | Score target |
|--------|------|--------------|
| `plugin/cli/src/**/*.ts` (Node.js CLI) | [stryker-mutator](https://stryker-mutator.io/) — config at `plugin/cli/stryker.config.json` | ≥ 75 % |
| `plugin/bin`, `plugin/lib`, `plugin/provisioner` (bash) | In-house `tests/mutation/bash-mutator.sh` | ≥ 60 % |

Targets match `docs/HARNESS.md` §1.3. The CLI target is higher because stryker is
mature and generates many equivalence-checked mutants; the bash mutator is a
narrow, audit-friendly set (negation flip, comparison swap, `set -e` removal,
sudoers mode bit flip, `as_user` bypass).

## Advisory — not blocking

Mutation results are **advisory in v0.3.0**. Both the nightly workflow job
(`.github/workflows/nightly-mutation.yml`) and stryker itself
(`thresholds.break: 0` in the config) are explicitly configured so a low score
cannot fail CI or block a merge. A regression that drops the score significantly
opens a follow-up issue, not a release blocker.

Promotion to a blocking release gate is a **v0.4 decision** — see ADR-007
follow-up. The intent: let v0.3.0 build up a mutation-score baseline and a
false-positive catalogue before we enforce a floor.

## Run locally

```bash
# Node.js CLI (stryker)
cd plugin/cli
npm install
npx stryker run

# Bash installer scripts (in-house mutator)
bash tests/mutation/bash-mutator.sh
```

Both commands print scores to stdout. On a Phase 1 empty plugin both commands
skip gracefully and exit 0 — no CLI source yet, no installer bash yet.

## Next steps (Phase 2+)

- Flesh out `bash-mutator.sh` to actually apply the five mutation operators and
  re-run the bats suite under Docker for each mutant.
- Wire stryker to the TypeScript CLI once real commands ship in Phase 4.
- Track mutation-score baseline per release in `docs/reviews/mutation-baseline.md`.
