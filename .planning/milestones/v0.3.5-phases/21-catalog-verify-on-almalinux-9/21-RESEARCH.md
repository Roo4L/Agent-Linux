# Phase 21 Research — On-box Catalog Smoke (AlmaLinux 9 + Ubuntu baseline)

**Method:** live `docker run --rm` smokes on `almalinux:9` and `ubuntu:24.04`
(throwaway, auto-removed containers). All commands mirror the catalog recipe
steps. Date: 2026-06-29.

## Q1 — claude-code + gsd on EL9

Already proven in Phase 20's 257/257 EL9 Docker row:
- `50-agents.bats` 11/11 green (AGT-01 six-mode loops for all three agents,
  AGT-02b/02c, AGT-03, AGT-04, AGT-05).
- `51/52-agt02` ran **real** `claude update` (native installer →
  `~agent/.local/bin/claude`) + npm global installs of gsd/playwright on EL9.

`claude-code` (distro-agnostic native installer) and `gsd` (pure npm) port
unchanged. No EL9-specific work needed. ✅

## Q2 — the open Playwright-Chromium question

### Finding 1 — `install --skills` downloads a browser (not just a skill)
`playwright-cli install --skills` downloads Chromium (~175 MB) into
`~/.cache/ms-playwright/chromium-1222`. On EL9 it prints:

```
BEWARE: your OS is not officially supported by Playwright;
downloading fallback build for ubuntu24.04-x64.
```

— Playwright has no native EL9 build, so it pulls the Ubuntu 24.04 fallback.
Install + skill-wiring + `playwright-cli --version` all exit 0 on EL9.

### Finding 2 — the fallback Chromium cannot LAUNCH without deps (EL9)
`ldd chrome` → **20 missing shared libraries**; a headless launch fails with
exit 127, `libnspr4.so: cannot open shared object file`. Missing set:
libX11, libXcomposite, libXdamage, libXext, libXfixes, libXrandr, libxcb,
libasound, libatk-1.0, libatk-bridge-2.0, libatspi, libcairo, libcups,
libgbm, libnspr4, libnss3, libnssutil3, libsmime3, libpango-1.0, libxkbcommon.

### Finding 3 — the gap is SYMMETRIC (Ubuntu baseline)
Same browser on stock `ubuntu:24.04` (recipe runs no `install-deps` on either
family): `ldd chrome` → **24 missing libs**, launch exit 127
(`libglib-2.0.so.0`). So browser-launch-readiness is a pre-existing
cross-family limitation, **not** an EL9 parity regression. No EL9-only dnf
block is warranted on parity grounds.

### Decision (user, 2026-06-29)
Make the browser launchable on **both** families. Mechanism research:
- `@playwright/cli@0.1.11` bundles the classic `playwright` + `playwright-core`
  packages in its dep tree, so Playwright's own `install-deps` is reachable at
  `$(npm root -g)/@playwright/cli/node_modules/playwright/cli.js`.
- `playwright-cli install --help` exposes only `--skills` (no `--with-deps`).
- `install-deps` has an apt path only — **no dnf path** (dies on EL9).

### Finding 4 — both fixes VERIFIED end-to-end
| Family | Mechanism | Missing libs after | Headless `--dump-dom` | `playwright-cli open` |
|---|---|---|---|---|
| debian (ubuntu:24.04) | `node …/playwright/cli.js install-deps chromium` | **0** | exit 0 | exit 0 |
| rhel (almalinux:9) | `dnf install -y <verified list>` | **0** | exit 0 | exit 0 |

Verified EL9 dnf list: `nss nspr atk at-spi2-atk at-spi2-core cups-libs libdrm
mesa-libgbm pango cairo alsa-lib libxkbcommon libX11 libXcomposite libXdamage
libXext libXfixes libXrandr libxcb libxshmfence`.

## Collateral finding — `docs/internals/playwright.md` was inaccurate
The internals doc claimed `--skills` auto-installs "OS-level browser deps via
apt" through the sudo drop-in. Grep confirmed **no** browser-deps logic existed
anywhere in `plugin/` before this phase; the doc conflated classic
`npx playwright install --with-deps` with `@playwright/cli`'s `install --skills`
(browsers + skill only). Corrected as part of this phase to match the recipe's
real, now-implemented behavior.
