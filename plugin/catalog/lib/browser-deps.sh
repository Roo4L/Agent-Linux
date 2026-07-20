#!/usr/bin/env bash
# Shared catalog prerequisite helpers. Source from recipes; callers own strict
# mode. OS packages are the only root-level operation allowed here.

al_browser_family() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID_LIKE:-$ID}" in
      *rhel*|*fedora*|*centos*|*rocky*|*alma*) printf 'rhel' ;;
      *) printf 'debian' ;;
    esac
  else
    printf 'unknown'
  fi
}

al_browser_sudo() {
  if ! sudo -n true >/dev/null 2>&1; then
    echo "${1}: system prerequisites are missing and the agent user cannot run non-interactive sudo." >&2
    echo "${1}: ask an administrator to grant package-install permission, then rerun this command." >&2
    return 1
  fi
}

al_browser_install_packages() {
  local label=$1
  shift
  local family
  family=$(al_browser_family)
  al_browser_sudo "$label" || return 1
  case "$family" in
    debian)
      sudo -n env DEBIAN_FRONTEND=noninteractive apt-get update -qq || {
        echo "${label}: apt-get update failed; package installation was not completed." >&2
        return 1
      }
      sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" || {
        echo "${label}: apt-get could not install required packages: $*" >&2
        return 1
      }
      ;;
    rhel)
      sudo -n dnf install -y --setopt=install_weak_deps=False "$@" || {
        echo "${label}: dnf could not install required packages: $*" >&2
        return 1
      }
      ;;
    *)
      echo "${label}: unsupported distro; install these prerequisites manually: $*" >&2
      return 1
      ;;
  esac
}

al_browser_ensure_git() {
  command -v git >/dev/null 2>&1 && return 0
  local family
  family=$(al_browser_family)
  case "$family" in
    debian) al_browser_install_packages 'spec-kit/git' git ;;
    rhel) al_browser_install_packages 'spec-kit/git' git ;;
    *) echo 'spec-kit: git is absent and this distro has no supported package manager.' >&2; return 1 ;;
  esac
  command -v git >/dev/null 2>&1 || { echo 'spec-kit: git is still absent after prerequisite install.' >&2; return 1; }
}

al_browser_ensure_chrome() {
  local chrome=/opt/google/chrome/chrome
  [[ -x "$chrome" ]] && return 0
  local family arch tmp package_suffix
  family=$(al_browser_family)
  arch=$(uname -m)
  [[ "$arch" == x86_64 ]] || {
    echo "chrome-devtools-mcp: Google Chrome's official catalog package is unavailable for ${arch}." >&2
    echo 'chrome-devtools-mcp: install Chrome at /opt/google/chrome/chrome as root, then rerun.' >&2
    return 1
  }
  al_browser_sudo 'chrome-devtools-mcp/Chrome' || return 1
  package_suffix=deb
  [[ "$family" == rhel ]] && package_suffix=rpm
  # Keep the package suffix: apt-get and dnf use it to recognize a local
  # package path. A suffix-less temporary download is rejected by apt-get.
  tmp=$(mktemp "${AGENTLINUX_AGENT_HOME:-${HOME}}/.chrome-agentlinux.XXXXXX.${package_suffix}")
  trap 'rm -f -- "$tmp"' RETURN
  # Accepted, documented trust edge: Google publishes only a rolling
  # `..._current_...` Chrome package (no per-version URL, no published SHA), so
  # there is no stable digest to pin against. Trust rests on Google's HTTPS +
  # the official dl.google.com origin — the same model Playwright uses to fetch
  # its browser builds. AgentLinux does NOT bake or cache a checksum here; do
  # not "harden" this into a hardcoded SHA that would break on the next Chrome
  # release. Version-pinned assets (e.g. the Antigravity archive) ARE SHA-512
  # verified — this exception is specific to the rolling Chrome channel.
  case "$family" in
    debian)
      curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o "$tmp" || {
        echo 'chrome-devtools-mcp: failed to download the official Chrome .deb.' >&2; return 1;
      }
      sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp" || {
        echo 'chrome-devtools-mcp: apt could not install Google Chrome; request root package access.' >&2; return 1;
      }
      ;;
    rhel)
      curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm -o "$tmp" || {
        echo 'chrome-devtools-mcp: failed to download the official Chrome .rpm.' >&2; return 1;
      }
      sudo -n dnf install -y "$tmp" || {
        echo 'chrome-devtools-mcp: dnf could not install Google Chrome; request root package access.' >&2; return 1;
      }
      ;;
    *)
      echo "chrome-devtools-mcp: unsupported distro family; install Google Chrome at ${chrome} as root." >&2
      return 1
      ;;
  esac
  [[ -x "$chrome" ]] || { echo "chrome-devtools-mcp: Chrome was installed but ${chrome} is absent." >&2; return 1; }
}

al_browser_ensure_playwright_libs() {
  local family
  family=$(al_browser_family)
  case "$family" in
    debian)
      local alsound
      if apt-cache show libasound2t64 >/dev/null 2>&1; then alsound=libasound2t64; else alsound=libasound2; fi
      al_browser_install_packages 'playwright-cli/browser-libraries' \
        libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
        libdbus-1-3 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 \
        libxrandr2 libgbm1 "$alsound" libatspi2.0-0 libwayland-client0 \
        libwayland-egl1 libwayland-cursor0 libgtk-3-0 libpangocairo-1.0-0 \
        libpango-1.0-0 libcairo2 libx11-xcb1 libxcb1
      ;;
    rhel)
      al_browser_install_packages 'playwright-cli/browser-libraries' \
        nss nspr atk at-spi2-atk cups-libs libdrm mesa-libgbm libXcomposite \
        libXdamage libXfixes libXrandr libxkbcommon alsa-lib gtk3 pango cairo \
        libxcb libX11 libXScrnSaver
      ;;
    *)
      echo 'playwright-cli: cannot determine distro family for browser libraries.' >&2
      return 1
      ;;
  esac
}
