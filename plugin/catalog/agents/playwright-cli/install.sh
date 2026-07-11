#!/usr/bin/env bash
set -euo pipefail
# playwright-cli install.sh — Microsoft's @playwright/cli for coding agents.
#
# Two-part install:
#   (1) npm install -g @playwright/cli@$PIN     — bootstrapper binary at
#                                                 ~agent/.npm-global/bin/playwright-cli
#   (2) playwright-cli install --skills          — wires the bundled Claude
#                                                 Code skill into
#                                                 ~/.claude/skills/playwright-cli/
#
# Discovered by user dogfood: npm-installing the package alone leaves the
# binary on PATH but Claude Code sees no /playwright-cli skills. The
# `--skills` invocation is what makes the user-visible intent ("install
# Playwright CLI for the agent") work end-to-end.
#
# References:
#   - https://playwright.dev/agent-cli/installation
#   - https://www.npmjs.com/package/@playwright/cli
#   - npm view @playwright/cli bin → { 'playwright-cli': 'playwright-cli.js' }

: "${AGENTLINUX_PINNED_VERSION:?AGENTLINUX_PINNED_VERSION not set}"
: "${AGENTLINUX_AGENT_HOME:?AGENTLINUX_AGENT_HOME not set}"

echo "playwright-cli: installing @playwright/cli@${AGENTLINUX_PINNED_VERSION}"

npm install -g \
  --omit=dev \
  --no-fund \
  --no-audit \
  "@playwright/cli@${AGENTLINUX_PINNED_VERSION}"

bin_path=$(command -v playwright-cli || true)
if [[ -z "$bin_path" ]]; then
  echo "playwright-cli install: playwright-cli not on PATH after npm install -g" >&2
  exit 1
fi

# Verify CLI version matches pin before invoking the skill bootstrapper.
pw_version=$(playwright-cli --version 2>&1 | head -1 | tr -d '[:space:]')
if [[ "$pw_version" != "${AGENTLINUX_PINNED_VERSION}" ]]; then
  printf 'playwright-cli install: pinned=%s but --version: %s\n' \
    "${AGENTLINUX_PINNED_VERSION}" "$pw_version" >&2
  exit 1
fi

echo "playwright-cli: CLI at ${bin_path}, version ${pw_version}"
echo "playwright-cli: wiring Claude Code skill via 'playwright-cli install --skills'"

# Bootstrap the bundled Claude Code skill into ~/.claude/skills/.
# Non-fatal: upstream may exit non-zero on re-runs / "already installed"
# paths; what we actually care about is that the skill landed on disk —
# verified below.
#
# Must run from a writable CWD: `playwright-cli install` calls
# initWorkspace() which mkdirs ./.playwright in the current directory.
# AgentLinux dispatches recipes from /opt/agentlinux-src/ (read-only repo
# copy in Docker / read-only workspace in QEMU), so a bare invocation
# crashes with EACCES on .playwright. Anchor CWD to agent-home (always
# writable, agent-owned) so the workspace dir lives at
# /home/agent/.playwright — a per-user side-effect that purge cleans via
# `userdel -r agent`.
( cd "${AGENTLINUX_AGENT_HOME}" && playwright-cli install --skills ) \
  || echo "playwright-cli install: bootstrapper exited non-zero (re-run / partial-state); verifying skill anyway" >&2

# Sanity-check the skill landed where Claude Code looks for it. Anchor
# the match on `playwright-cli` (mirrors install side) — a broader
# `*playwright*` would match unrelated user-installed skills.
skill_dir="${AGENTLINUX_AGENT_HOME}/.claude/skills"
mkdir -p "$skill_dir"
if ! find "$skill_dir" -maxdepth 1 -type d -name 'playwright-cli*' -print -quit 2>/dev/null | grep -q .; then
  printf 'playwright-cli install: no playwright-cli skill found under %s after bootstrapper run\n' "$skill_dir" >&2
  exit 1
fi

# Browser-launch dependencies (REC-01, v0.3.5).
# `playwright-cli install --skills` above downloads a Chromium *binary* but
# none of the ~20 system libraries it needs to LAUNCH (libnss3, libgbm1,
# libxkbcommon, the libX* set, ...). Absent them the binary sits on disk and
# `playwright-cli --version` still passes, but the first real browser command
# dies with `error while loading shared libraries`. Install that closure now,
# dispatched on distro family. The recipe runs standalone (the CLI does not
# export AGENTLINUX_DISTRO_FAMILY into the recipe env — see plugin/cli/src/
# runner.ts), so detect the family by reading /etc/os-release directly, the
# same standalone approach the bats distro.bash helper uses. AGT-06
# (tests/bats/50-agents.bats) locks the result on both families.
#
# Both arms install OS packages via sudo; the agent user's NOPASSWD drop-in
# (/etc/sudoers.d/agentlinux, ADR-012) is what lets that run mid-install
# without stalling a non-interactive coding-agent loop on a password prompt.
echo "playwright-cli: installing Chromium browser-launch dependencies"
pw_family=debian
if [[ -r /etc/os-release ]]; then
  # Source in a subshell so os-release's ID/VERSION_ID/... do not leak into
  # the recipe environment. Only `almalinux` maps to rhel — matching the
  # installer's detect_distro allowlist, which refuses other EL IDs upstream,
  # so a non-Alma host never reaches the debian-arm fallthrough in practice.
  # shellcheck disable=SC1091
  case "$(. /etc/os-release && printf '%s' "${ID:-}")" in
    almalinux) pw_family=rhel ;;
    *) pw_family=debian ;;
  esac
fi

case "$pw_family" in
  debian)
    # Use Playwright's own dependency installer rather than a hardcoded apt
    # list: it knows the package names for each Ubuntu release (incl. the
    # 24.04 `t64` ABI transition), so the recipe stays correct across 22.04/
    # 24.04/26.04. The classic `playwright` package ships bundled inside
    # @playwright/cli's dependency tree; `install-deps` auto-prepends sudo to
    # its apt step (handled by the NOPASSWD drop-in).
    #
    # Locate that bundled package's cli.js by resolving its package.json:
    # playwright's `exports` map blocks a direct require.resolve of `./cli.js`,
    # and npm may hoist the package to the top level rather than nest it under
    # @playwright/cli. Passing both candidate roots makes the lookup tolerant
    # of either layout and of a future pin bump that reshapes the tree.
    pw_root=$(npm root -g 2>/dev/null || true)
    pw_cli_js=$(node -e '
      try {
        const pkg = require.resolve("playwright/package.json",
          {paths: [process.argv[1] + "/@playwright/cli", process.argv[1]]});
        process.stdout.write(require("path").join(require("path").dirname(pkg), "cli.js"));
      } catch (e) { process.exit(1); }
    ' "$pw_root" 2>/dev/null || true)
    if [[ -z "$pw_cli_js" || ! -f "$pw_cli_js" ]]; then
      printf 'playwright-cli install: could not locate bundled playwright cli.js (npm root -g=%s); cannot install browser deps\n' \
        "${pw_root:-<empty>}" >&2
      exit 1
    fi
    node "$pw_cli_js" install-deps chromium
    ;;
  rhel)
    # Playwright's install-deps has no dnf path (it dies on EL9), so install
    # the EL9 closure explicitly. This list was derived and verified on-box
    # against the chromium-1222 (ubuntu24.04-x64 fallback) build: afterwards
    # `ldd chrome` is clean and a headless launch exits 0. weak-deps off keeps
    # the footprint lean (matches the verified run); `dnf install` is
    # idempotent, so re-install / upgrade is a no-op.
    sudo dnf install -y --setopt=install_weak_deps=False \
      nss nspr atk at-spi2-atk at-spi2-core cups-libs libdrm mesa-libgbm \
      pango cairo alsa-lib libxkbcommon \
      libX11 libXcomposite libXdamage libXext libXfixes libXrandr libxcb libxshmfence
    ;;
esac

echo "playwright-cli: install complete (binary at ${bin_path}; skill wired into ${skill_dir}/playwright-cli; Chromium browser-launch deps installed)"
