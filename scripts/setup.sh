#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for setting up dotfiles on a new machine.
#
# Can be run via: curl -fsSL https://raw.githubusercontent.com/USER/dots/main/scripts/setup.sh | bash
# Or after cloning: ./scripts/setup.sh
#
# Privilege policy: commands run directly as root; otherwise sudo is used, then
# doas. With neither (and not root) the script aborts with a clear message.
#
# Output policy: the terminal carries only ==> status lines; package-manager,
# installer and git output is captured in a per-run audit log
# (~/.local/state/dots/setup-<timestamp>.log), whose tail is printed when a
# quiet-wrapped step fails.
#
# Alpine bootstrap (busybox-only base image): this script needs bash, git and
# curl up front, so on a bare Alpine box run the two-step bootstrap:
#     apk add bash git curl
#     ./scripts/setup.sh        # or: wget -qO- <setup.sh url> | bash
#
# Blessed targets: macOS 14+, Debian bookworm & trixie, Alpine 3.22+ (including
# the WSL2 flavours), FreeBSD best effort.

REPO_URL="${DOTS_REPO_URL:-https://github.com/tharant/dots.git}"
DOTS_DIR="${DOTS_DIR:-$HOME/.dots}"
FORCE="${FORCE:-false}"

PLATFORM=""
DISTRO=""
ENV=""            # environment layer: "wsl" (distro layers live in DISTRO)
PKG_MGR=""
SUDO=""
APT_UPDATED=""
SUCCESS_MSG="Dotfiles deployed."
AUDIT_LOG=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [--restow] [--adopt] [--unstow] [--force] [--verify]
  (no args)   Full bootstrap: install deps, clone, decrypt, stow
  --restow    Re-stow all packages (use after git pull)
  --adopt     Adopt existing files into the repo, then re-stow
  --unstow    Remove all symlinks managed by stow
  --force     Force re-decrypt and re-stow (skip freshness checks)
  --verify    Run verification checks on current deployment

Privileges: run as root, or with sudo/doas available.

Alpine note: on a bare Alpine system the script needs bash, git and curl first:
  apk add bash git curl
EOF
    exit 0
}

# --- Helpers ---

info()  { echo -e "\033[1;34m==>\033[0m $*"; }
warn()  { echo -e "\033[1;33m==> WARNING:\033[0m $*"; }
error() { echo -e "\033[1;31m==> ERROR:\033[0m $*"; exit 1; }

# Track failures for non-fatal errors
FAILURES=()

on_error() {
    local exit_code=$?
    error "Step failed with exit code $exit_code. Run with --help for options."
}

report_failures() {
    if [[ ${#FAILURES[@]} -gt 0 ]]; then
        warn "The following steps had issues:"
        for f in "${FAILURES[@]}"; do
            warn "  - $f"
        done
        warn "Details (package-manager and installer output): $AUDIT_LOG"
        return 1
    fi
}

finish() {
    if report_failures; then
        info "Done! $SUCCESS_MSG"
        info "Log out and back in (or source ~/.bashrc) for changes to take effect."
    else
        # exit (not return) so the ERR trap does not print a second message
        exit 1
    fi
}

command_exists() { command -v "$1" &>/dev/null; }

download() {
    # download <url> <output-file> — curl first, busybox wget as fallback
    if command_exists curl; then
        curl -fsSL "$1" -o "$2"
    elif command_exists wget; then
        wget -qO "$2" "$1"
    else
        warn "Neither curl nor wget is available — cannot download $1"
        return 1
    fi
}

# --- Environment, privilege, tty ---

detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *BSD)   echo "bsd" ;;
        *)      error "Unsupported platform: $(uname -s)" ;;
    esac
}

detect_env() {
    PLATFORM="$(detect_platform)"
    info "Detected platform: $PLATFORM"

    # Distro (only meaningful on Linux)
    if [[ -r /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        DISTRO="${ID:-}"
    fi
    if [[ "$PLATFORM" == "linux" && -n "$DISTRO" ]]; then
        info "Detected distro: $DISTRO"
    fi

    # WSL: either the distro name env var is set or the kernel says Microsoft
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
        ENV="wsl"
        info "Detected environment: WSL"
    fi

    # Informational only: OrbStack on macOS exposes a WSL-like layer
    case "$(uname -r)" in
        *orbstack*|*OrbStack*) info "Detected environment: OrbStack" ;;
    esac
}

detect_privilege() {
    if [[ $EUID -eq 0 ]]; then
        SUDO=""
        info "Running as root — no privilege escalation needed"
    elif command_exists sudo; then
        SUDO="sudo"
    elif command_exists doas; then
        SUDO="doas"
    else
        SUDO=""
        warn "Not root and neither sudo nor doas is installed — steps needing"
        warn "root will abort until you install one or run as root."
    fi
}

require_priv() {
    if [[ $EUID -ne 0 && -z "$SUDO" ]]; then
        error "Root privileges are required but neither sudo nor doas is available. Install one (apk/apt/dnf/pacman install sudo) or run as root."
    fi
}

run_priv() {
    # Same as "$SUDO $@" unless already root, where the prefix is empty
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        "$SUDO" "$@"
    fi
}

init_audit_log() {
    # Per-run audit log under ~/.local/state/dots/: every quiet-wrapped
    # sub-step (package managers, installers, git) writes its output here so
    # the terminal carries only the ==> status lines. Kept across runs for
    # post-hoc inspection.
    local dir="$HOME/.local/state/dots"
    mkdir -p "$dir"
    AUDIT_LOG="$dir/setup-$(date +%Y%m%d%H%M%S).log"
    : > "$AUDIT_LOG"
    info "Audit log: $AUDIT_LOG"
}

quiet() {
    # quiet <cmd...> — run a verbose sub-step with stdout/stderr captured in
    # the audit log. On failure the tail of the log is printed so the error
    # itself stays on the terminal; the caller reports/records the failure
    # (FAILURES or error()) exactly as before. `|| rc=$?` (not a plain call
    # followed by rc=$?) both captures the real exit code and keeps errexit
    # from firing inside this function, whatever context the caller used.
    local rc=0
    "$@" >>"$AUDIT_LOG" 2>&1 || rc=$?
    if [[ $rc -ne 0 ]]; then
        warn "Step failed (exit $rc) — last 20 lines of $AUDIT_LOG:"
        tail -20 "$AUDIT_LOG" >&2
    fi
    return $rc
}

reattach_tty() {
    # `curl ... | bash` leaves stdin on the pipe; age's passphrase prompt (and
    # chsh) need a real TTY, so reattach to /dev/tty when stdin is not one.
    # Guard with a test open too: /dev/tty exists but opening it fails (ENXIO)
    # when there is no controlling terminal at all (CI, non-interactive jobs).
    if [[ ! -t 0 ]]; then
        if { : </dev/tty; } 2>/dev/null; then
            exec 0</dev/tty
        fi
    fi
}

# --- Package installation ---

detect_pkg_mgr() {
    if [[ -n "$PKG_MGR" ]]; then
        return 0
    fi
    local m
    for m in brew apt-get dnf pacman apk pkg; do
        if command_exists "$m"; then
            PKG_MGR="$m"
            info "Detected package manager: $PKG_MGR"
            return 0
        fi
    done
    error "No supported package manager found (brew, apt-get, dnf, pacman, apk, pkg). Install dependencies manually."
}

pkg_install() {
    # pkg_install pkg... — install packages with the detected package manager
    if [[ $# -eq 0 ]]; then
        return 0
    fi
    detect_pkg_mgr

    # apt needs its lists refreshed once, before the first install
    if [[ "$PKG_MGR" == "apt-get" && "$APT_UPDATED" != "true" ]]; then
        info "Updating apt package lists..."
        quiet run_priv apt-get update
        APT_UPDATED=true
    fi

    case "$PKG_MGR" in
        brew)    quiet brew install "$@" ;;                # brew must not run as root
        apt-get) quiet run_priv apt-get install -y "$@" ;;
        dnf)     quiet run_priv dnf install -y "$@" ;;
        pacman)  quiet run_priv pacman -S --noconfirm "$@" ;;
        apk)     quiet run_priv apk add "$@" ;;
        pkg)     quiet run_priv pkg install -y "$@" ;;
        *)       error "Unsupported package manager: $PKG_MGR" ;;
    esac
}

# Install a set of packages; on a batch failure retry one by one, so a single
# missing or renamed package does not take the whole set down with it.
pkg_install_set() {
    if pkg_install "$@"; then
        return 0
    fi
    warn "Batch install failed — retrying packages individually"
    local p
    for p in "$@"; do
        pkg_install "$p" || FAILURES+=("install: $p")
    done
    return 0
}

ensure_tool() {
    # ensure_tool <command> [package] — install a package only if its binary is missing
    local cmd="$1"
    local pkg="${2:-$1}"
    if command_exists "$cmd"; then
        info "$cmd already installed"
        return 0
    fi
    info "Installing $pkg..."
    pkg_install "$pkg"
}

# --- Static binary fallbacks ---

install_age_binary() {
    # Upstream static age release, for when no package is available
    local version="v1.3.1"
    local os="" arch="" url tmp

    case "$PLATFORM" in
        linux) os="linux" ;;
        macos) os="darwin" ;;
        bsd)   os="freebsd" ;;
        *)     warn "No prebuilt age release for platform '$PLATFORM'"; return 1 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64)        arch="amd64" ;;
        aarch64|arm64|armv8) arch="arm64" ;;
        *)                   warn "No prebuilt age release for architecture '$(uname -m)'"; return 1 ;;
    esac

    url="https://github.com/FiloSottile/age/releases/download/$version/age-$version-$os-$arch.tar.gz"
    info "Installing age from static release: $url"
    tmp="$(mktemp -d)"
    if ! download "$url" "$tmp/age.tar.gz"; then
        rm -rf "$tmp"
        return 1
    fi
    if ! tar -xzf "$tmp/age.tar.gz" -C "$tmp"; then
        warn "Could not extract the age release tarball"
        rm -rf "$tmp"
        return 1
    fi
    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$tmp/age/age" "$HOME/.local/bin/age"
    install -m 0755 "$tmp/age/age-keygen" "$HOME/.local/bin/age-keygen"
    rm -rf "$tmp"
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) warn "Add $HOME/.local/bin to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
    esac
    info "Installed age to $HOME/.local/bin"
}

install_direnv() {
    # Upstream static direnv release, for when no package is available.
    # Unlike age this is a hard requirement — the direnv stow package is
    # useless without its hook binary — so post_install_checks aborts the
    # run when neither a package nor this fallback produces a binary.
    local version="v2.37.1"
    local os="" arch="" url tmp

    case "$PLATFORM" in
        linux) os="linux" ;;
        macos) os="darwin" ;;
        bsd)   os="freebsd" ;;
        *)     warn "No prebuilt direnv release for platform '$PLATFORM'"; return 1 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64)        arch="amd64" ;;
        aarch64|arm64|armv8) arch="arm64" ;;
        *)                   warn "No prebuilt direnv release for architecture '$(uname -m)'"; return 1 ;;
    esac

    # The release asset is a single binary, not a tarball
    url="https://github.com/direnv/direnv/releases/download/$version/direnv.$os-$arch"
    info "Installing direnv from static release: $url"
    tmp="$(mktemp -d)"
    if ! download "$url" "$tmp/direnv"; then
        rm -rf "$tmp"
        return 1
    fi
    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$tmp/direnv" "$HOME/.local/bin/direnv"
    rm -rf "$tmp"
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) warn "Add $HOME/.local/bin to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
    esac
    info "Installed direnv to $HOME/.local/bin"
}

install_just_binary() {
    # just is not packaged for Debian bookworm — use the upstream musl binary
    local version="1.58.0"
    local arch="" target url tmp

    case "$(uname -m)" in
        x86_64)  arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        *)       warn "No prebuilt just release for architecture '$(uname -m)'"; return 1 ;;
    esac
    target="${arch}-unknown-linux-musl"
    url="https://github.com/casey/just/releases/download/$version/just-$version-$target.tar.gz"

    info "Installing just from static release: $url"
    tmp="$(mktemp -d)"
    if ! download "$url" "$tmp/just.tar.gz"; then
        rm -rf "$tmp"
        return 1
    fi
    if ! tar -xzf "$tmp/just.tar.gz" -C "$tmp"; then
        warn "Could not extract the just release tarball"
        rm -rf "$tmp"
        return 1
    fi
    run_priv install -m 0755 "$tmp/just" /usr/local/bin/just
    rm -rf "$tmp"
    info "Installed just to /usr/local/bin"
}

install_node_tarball() {
    # Node.js 22 from the official dist tarball (bookworm tops out at Node 18)
    local version="v22.23.2"
    local arch="" tarball url tmp

    case "$(uname -m)" in
        x86_64)        arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)             warn "No Node.js tarball for architecture '$(uname -m)'"; return 1 ;;
    esac
    tarball="node-$version-linux-$arch.tar.xz"
    url="https://nodejs.org/dist/$version/$tarball"

    info "Installing Node.js $version from the official tarball: $url"
    tmp="$(mktemp -d)"
    if ! download "$url" "$tmp/$tarball"; then
        rm -rf "$tmp"
        return 1
    fi
    # tar -C fails into a nonexistent directory — create it first (pristine
    # Debian machines have no /usr/local/lib/nodejs)
    if ! run_priv mkdir -p /usr/local/lib/nodejs; then
        warn "Could not create /usr/local/lib/nodejs"
        rm -rf "$tmp"
        return 1
    fi
    if ! run_priv tar -xJf "$tmp/$tarball" -C /usr/local/lib/nodejs; then
        warn "Could not extract the Node.js tarball"
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    local b
    for b in node npm npx; do
        run_priv ln -sfn "/usr/local/lib/nodejs/node-$version-linux-$arch/bin/$b" "/usr/local/bin/$b"
    done
    info "Installed Node.js to /usr/local/lib/nodejs (symlinks in /usr/local/bin)"
}

# --- Per-platform core installs ---

install_homebrew() {
    # A pristine Mac has neither brew nor any other supported package manager,
    # so bootstrap Homebrew itself via the official installer. The installer
    # must run as the user (it invokes sudo itself for the prefix directory);
    # NONINTERACTIVE=1 skips the "press RETURN" pause so curl | bash works.
    if command_exists brew; then
        return 0
    fi
    if [[ $EUID -eq 0 ]]; then
        error "Homebrew cannot be installed as root. Log in as an admin user and re-run."
    fi
    info "Homebrew not found — installing (official installer, non-interactive)..."
    if ! quiet env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL \
        https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        error "Homebrew installation failed — install it from https://brew.sh and re-run."
    fi
    # Put brew on PATH for the rest of this run; the shellenv itself lands in
    # the shell via the macos platform layer on the next login.
    local prefix
    case "$(uname -m)" in
        arm64) prefix="/opt/homebrew" ;;
        *)     prefix="/usr/local" ;;
    esac
    case ":$PATH:" in
        *":$prefix/bin:"*) ;;
        *) export PATH="$prefix/bin:$PATH" ;;
    esac
    if ! command_exists brew; then
        error "Homebrew installed but brew is still not on PATH ($prefix/bin)."
    fi
    info "Homebrew installed at $(command -v brew)"
}

macos_default_shell() {
    # Hand the login shell over to Homebrew's bash; idempotent and non-fatal
    local brew_bin brew_prefix bash_path arch
    brew_bin="$(command -v brew || true)"
    arch="$(uname -m)"
    if [[ -n "$brew_bin" ]]; then
        brew_prefix="$(dirname "$(dirname "$brew_bin")")"   # /usr/local/bin/brew -> /usr/local
    elif [[ "$arch" == "arm64" ]]; then
        brew_prefix="/opt/homebrew"
    else
        brew_prefix="/usr/local"
    fi
    bash_path="$brew_prefix/bin/bash"
    if [[ ! -x "$bash_path" ]]; then
        warn "Homebrew bash not found at $bash_path — keeping the current login shell"
        return 0
    fi

    if ! grep -qxF "$bash_path" /etc/shells 2>/dev/null; then
        info "Adding $bash_path to /etc/shells"
        echo "$bash_path" | run_priv tee -a /etc/shells >/dev/null \
            || { warn "Could not write $bash_path to /etc/shells"; FAILURES+=("macos: /etc/shells"); }
    fi

    if [[ "${SHELL:-}" == "$bash_path" ]]; then
        info "Default login shell is already $bash_path"
    else
        info "Setting default login shell to $bash_path (may prompt for your password)"
        if ! chsh -s "$bash_path"; then
            warn "Could not change the default shell — run manually: chsh -s $bash_path"
            FAILURES+=("macos: chsh")
        fi
    fi
}

alpine_prepare() {
    # age, stow, just, shellcheck and direnv all live in the community repository
    if [[ ! -f /etc/apk/repositories ]]; then
        warn "/etc/apk/repositories not found — cannot check for the community repo"
        FAILURES+=("alpine: repositories file missing")
        return 0
    fi
    if ! grep -qE '^[^#].*/community' /etc/apk/repositories; then
        local main_line
        main_line="$(grep -m1 -E '^[^#].*/main' /etc/apk/repositories || true)"
        if [[ -z "$main_line" ]]; then
            warn "Could not determine the Alpine mirror from /etc/apk/repositories"
            warn "Add the matching community repository manually, then re-run."
            FAILURES+=("alpine: community repository")
            return 0
        fi
        warn "Alpine 'community' repository is not enabled — appending it"
        echo "${main_line%/main}/community" | run_priv tee -a /etc/apk/repositories >/dev/null
    fi
    info "Refreshing apk indexes..."
    run_priv apk update
}

apt_candidate_version() {
    # The version apt would install, or empty when the package is unavailable
    apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2; exit}'
}

install_debian_extra() {
    # Debian extras: Node.js 22, just (bookworm only has neither), UTF-8 locale
    local ver major

    ver="$(apt_candidate_version nodejs)"
    major="${ver#v}"
    major="${major%%.*}"
    case "$major" in
        ''|*[!0-9]*) major="" ;;
    esac
    if [[ -n "$major" && "$major" -ge 22 ]]; then
        info "apt has Node.js $ver — installing nodejs/npm from apt"
        pkg_install_set nodejs npm
    else
        info "apt Node.js is ${ver:-<none>}, need >= 22 — using the official Node.js tarball"
        install_node_tarball || FAILURES+=("install: nodejs tarball")
    fi

    if command_exists just; then
        info "just already installed"
    elif [[ -n "$(apt_candidate_version just)" ]]; then
        if ! pkg_install just; then
            warn "apt install failed for just — falling back to the upstream binary"
            install_just_binary || FAILURES+=("install: just (static binary)")
        fi
    else
        install_just_binary || FAILURES+=("install: just (static binary)")
    fi

    install_utf8_locale
}

install_utf8_locale() {
    # Enable en_US.UTF-8 non-interactively right after installing locales.
    # locale-gen lives in /usr/sbin, which is not always on PATH (OrbStack
    # syncs the Mac's PATH into its machines; non-login shells) — so resolve
    # it by absolute path as a fallback before declaring it missing.
    local locale_gen
    locale_gen="$(command -v locale-gen || true)"
    if [[ -z "$locale_gen" && -x /usr/sbin/locale-gen ]]; then
        locale_gen=/usr/sbin/locale-gen
    fi
    if [[ -z "$locale_gen" ]]; then
        warn "locale-gen not available — skipping en_US.UTF-8 generation"
        FAILURES+=("locales: locale-gen missing")
        return 0
    fi
    if locale -a 2>/dev/null | grep -qi '^en_US.utf8$'; then
        info "Locale en_US.UTF-8 is already generated"
        return 0
    fi
    info "Enabling the en_US.UTF-8 locale..."
    if ! [[ -f /etc/locale.gen ]]; then
        warn "/etc/locale.gen not found — skipping en_US.UTF-8 generation"
        FAILURES+=("locales: /etc/locale.gen missing")
        return 0
    fi
    if grep -qi '^en_US.UTF-8 UTF-8' /etc/locale.gen; then
        info "en_US.UTF-8 already enabled in /etc/locale.gen"
    elif grep -qi '^# *en_US.UTF-8 UTF-8' /etc/locale.gen; then
        run_priv sed -i 's/^#[[:space:]]*en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    else
        echo 'en_US.UTF-8 UTF-8' | run_priv tee -a /etc/locale.gen >/dev/null
    fi
    quiet run_priv "$locale_gen" || {
        warn "locale-gen failed — set LANG manually if the shell looks broken"
        FAILURES+=("locales: en_US.UTF-8")
    }
}

# --- Runtime managers (best-effort) ---

install_uv() {
    # uv (python backend for the `runtimes` shim) via the official installer.
    # UV_NO_MODIFY_PATH=1 is mandatory: without it the installer appends PATH
    # lines to the shell RCs, which on a deployed machine are stowed symlinks
    # into this repo (dirty-tree hazard).
    if command_exists uv; then
        info "uv already installed"
        return 0
    fi
    local tmp
    tmp="$(mktemp -d)"
    if ! download "https://astral.sh/uv/install.sh" "$tmp/uv-install.sh"; then
        warn "Could not download the uv installer"
        rm -rf "$tmp"
        return 1
    fi
    info "Installing uv (official installer)..."
    if ! quiet env UV_NO_MODIFY_PATH=1 sh "$tmp/uv-install.sh"; then
        warn "The uv installer failed"
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    if [[ ! -x "$HOME/.local/bin/uv" ]]; then
        warn "The uv installer finished but $HOME/.local/bin/uv is missing"
        return 1
    fi
    info "Installed uv to $HOME/.local/bin"
}

install_fnm() {
    # fnm (node backend for the `runtimes` shim) from the upstream release
    # zips. fnm-macos.zip is a universal (x86_64 + aarch64) binary;
    # fnm-linux.zip (x86_64) and fnm-arm64.zip (aarch64) are static musl
    # binaries, so they run on Alpine and glibc alike.
    if command_exists fnm; then
        info "fnm already installed"
        return 0
    fi
    local version="v1.39.0"
    local asset="" url tmp

    case "$PLATFORM" in
        macos) asset="fnm-macos.zip" ;;
        linux)
            case "$(uname -m)" in
                x86_64|amd64)        asset="fnm-linux.zip" ;;
                aarch64|arm64|armv8) asset="fnm-arm64.zip" ;;
                *)                   warn "No fnm release for architecture '$(uname -m)'"; return 1 ;;
            esac
            ;;
        *)     warn "No fnm release for platform '$PLATFORM'"; return 1 ;;
    esac

    # The releases are zips; pull unzip on demand (Alpine ships it as a
    # busybox applet, macOS as part of the base system)
    if ! command_exists unzip; then
        pkg_install unzip || { warn "unzip is needed to extract the fnm release"; return 1; }
    fi

    url="https://github.com/Schniz/fnm/releases/download/$version/$asset"
    info "Installing fnm from release: $url"
    tmp="$(mktemp -d)"
    if ! download "$url" "$tmp/$asset"; then
        rm -rf "$tmp"
        return 1
    fi
    if ! quiet unzip -o "$tmp/$asset" -d "$tmp"; then
        warn "Could not extract the fnm release"
        rm -rf "$tmp"
        return 1
    fi
    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$tmp/fnm" "$HOME/.local/bin/fnm"
    rm -rf "$tmp"
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) warn "Add $HOME/.local/bin to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
    esac
    info "Installed fnm to $HOME/.local/bin"
}

sdkman_auto_answer() {
    # `sdk install` prompts y/n unless sdkman_auto_answer=true; the installer
    # writes 'false', so flip the key in place (append only when missing)
    local config="$HOME/.sdkman/etc/config"
    if [[ ! -f "$config" ]]; then
        warn "sdkman config not found at $config"
        return 1
    fi
    if grep -q '^sdkman_auto_answer=' "$config"; then
        # sed -i differs between GNU and BSD — rewrite via a temp file
        sed 's/^sdkman_auto_answer=.*/sdkman_auto_answer=true/' "$config" > "$config.tmp" \
            && mv "$config.tmp" "$config"
    else
        echo 'sdkman_auto_answer=true' >> "$config"
    fi
    info "sdkman_auto_answer=true set in $config"
}

install_sdkman() {
    # sdkman (java backend for the `runtimes` shim) via the official
    # installer, on the install_homebrew precedent: best-effort, never fatal.
    #
    # The installer appends its init snippet to ~/.bashrc, ~/.bash_profile or
    # ~/.zshrc (and creates them when absent). On a deployed machine those
    # are stowed symlinks into this repo — the append dirties the working
    # tree — and on a fresh one the created files would collide with stow.
    # So each file is snapshotted before the install and restored right
    # after; our .bashrc already ships the identical snippet, so the strip
    # changes nothing functionally.
    if [[ -x "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
        info "sdkman already installed"
        sdkman_auto_answer || return 1
        return 0
    fi

    # The installer needs zip/unzip alongside curl and tar; Debian's minimal
    # install ships neither
    if ! command_exists zip || ! command_exists unzip; then
        pkg_install zip unzip || { warn "zip/unzip could not be installed"; return 1; }
    fi

    local tmp
    tmp="$(mktemp -d)"

    # Snapshot the shell RCs the installer may touch
    local rc
    for rc in bashrc bash_profile zshrc; do
        if [[ -f "$HOME/.$rc" ]]; then
            cp "$HOME/.$rc" "$tmp/$rc"
        else
            touch "$tmp/$rc.missing"
        fi
    done

    local installed=true
    if ! download "https://get.sdkman.io" "$tmp/sdkman-install.sh"; then
        warn "Could not download the sdkman installer"
        installed=false
    elif ! quiet bash "$tmp/sdkman-install.sh"; then
        warn "The sdkman installer failed"
        installed=false
    fi

    # Strip the appended snippets (or remove files the installer created)
    for rc in bashrc bash_profile zshrc; do
        if [[ -f "$tmp/$rc.missing" ]]; then
            rm -f "$HOME/.$rc"
        elif [[ -f "$tmp/$rc" ]]; then
            cat "$tmp/$rc" > "$HOME/.$rc"
        fi
    done
    rm -rf "$tmp"

    if [[ "$installed" != "true" ]]; then
        return 1
    fi
    sdkman_auto_answer || return 1
    info "Installed sdkman to $HOME/.sdkman"
}

install_runtimes() {
    # Backends behind the `runtimes` shim. direnv (the hard requirement) is
    # already handled by the package lists plus post_install_checks; these
    # three are best-effort and must never abort the run. BSD is
    # dotfiles-only: runtime auto-install is unsupported there.
    if [[ "$PLATFORM" == "bsd" ]]; then
        info "BSD: skipping uv, fnm, sdkman (runtime auto-install unsupported)"
        return 0
    fi
    install_uv || FAILURES+=("install: uv")
    install_fnm || FAILURES+=("install: fnm")
    install_sdkman || FAILURES+=("install: sdkman")
}

post_install_checks() {
    # Never fail silently: verify the tools the rest of the run depends on
    local tool
    for tool in git curl just tmux shellcheck jq; do
        if ! command_exists "$tool"; then
            warn "Expected tool '$tool' is still missing after install"
            FAILURES+=("missing: $tool")
        fi
    done
    if ! command_exists stow; then
        error "GNU Stow is required to deploy the dotfiles but could not be installed."
    fi
    if ! command_exists age; then
        install_age_binary || FAILURES+=("install: age (static binary fallback)")
    fi
    # direnv is a hard requirement — the direnv stow package is useless
    # without its hook binary — so unlike age there is no FAILURES entry:
    # the run aborts if neither a package nor the static fallback worked.
    if ! command_exists direnv; then
        install_direnv || error "direnv is required for the direnv integration but could not be installed."
    fi
}

install_core() {
    detect_pkg_mgr

    case "$PLATFORM" in
        macos)
            # Privacy: keep Homebrew from calling home, both for the bootstrap
            # run itself and for every install it performs. The same exports
            # live in the macos platform layer for interactive shells.
            export HOMEBREW_NO_ANALYTICS=1
            export HOMEBREW_NO_ENV_HINTS=1
            install_homebrew
            info "Installing core packages via Homebrew..."
            pkg_install_set bash age stow just tmux shellcheck git coreutils \
                direnv jq bc
            macos_default_shell
            ;;
        linux)
            if [[ "$DISTRO" == "alpine" ]]; then
                alpine_prepare
                info "Installing core packages via apk..."
                local alpine_pkgs=(bash coreutils findutils util-linux git age stow just tmux
                    shellcheck direnv shadow bash-completion ncurses-terminfo curl \
                    ca-certificates jq bc)
                # Keep doas-only systems doas-only
                if ! command_exists sudo && ! command_exists doas; then
                    alpine_pkgs+=(sudo)
                fi
                pkg_install_set "${alpine_pkgs[@]}"
            elif [[ "$PKG_MGR" == "apt-get" ]]; then
                info "Installing core packages via apt..."
                pkg_install_set git age stow tmux shellcheck bash coreutils less \
                    locales ca-certificates curl wl-clipboard xz-utils direnv jq bc
                install_debian_extra
            else
                info "Installing core packages..."
                pkg_install_set git age stow just tmux shellcheck bash coreutils direnv curl \
                    ca-certificates jq bc
            fi
            ;;
        bsd)
            info "Installing core packages via pkg..."
            pkg_install_set git age stow just tmux shellcheck bash coreutils direnv curl \
                ca_root_nss jq bc
            ;;
    esac

    post_install_checks
    install_runtimes
}

preflight_checks() {
    info "Checking preflight requirements..."
    if ! command_exists git; then
        info "Installing git..."
        pkg_install git || FAILURES+=("install: git")
    fi
    if ! command_exists curl; then
        if [[ "$DISTRO" == "alpine" ]] && command_exists wget; then
            info "curl is missing — downloads will fall back to busybox wget"
        else
            warn "curl is missing — release-tarball fallbacks need it"
            FAILURES+=("preflight: curl missing")
        fi
    fi
    if [[ "$DISTRO" == "alpine" && -z "${BASH_VERSION:-}" ]]; then
        error "Alpine: this script must run under bash (apk add bash git curl, then re-run)"
    fi
}

# --- Clone or update repo ---

require_repo() {
    if [[ ! -d "$DOTS_DIR/.git" ]]; then
        error "Repo is not cloned at $DOTS_DIR — run '$(basename "$0")' with no arguments first."
    fi
}

setup_repo() {
    if [[ -d "$DOTS_DIR/.git" ]]; then
        info "Repo exists at $DOTS_DIR, pulling latest..."
        if [[ -n "$(git -C "$DOTS_DIR" status --porcelain)" ]]; then
            warn "Repo has local changes — pulling with --autostash"
            quiet git -C "$DOTS_DIR" pull --ff-only --autostash || {
                warn "Pull failed — keeping the current checkout"
                FAILURES+=("git pull")
            }
        else
            quiet git -C "$DOTS_DIR" pull --ff-only || {
                warn "Pull failed — keeping the current checkout"
                FAILURES+=("git pull")
            }
        fi
    else
        info "Cloning dotfiles repo..."
        quiet git clone "$REPO_URL" "$DOTS_DIR"
    fi
    # Make sure the repo's hook directory stays active (shellcheck gate)
    git -C "$DOTS_DIR" config core.hooksPath .githooks
}

# --- Clone the tmux-powerline statusline ---

TMUX_POWERLINE_REPO_URL="https://github.com/erikw/tmux-powerline.git"
# Pinned upstream commit (main HEAD when this was integrated). Bump
# deliberately: a new pin changes the segment/theme files under
# ~/.config/tmux-powerline/tmux-powerline (run `just restow` to apply).
TMUX_POWERLINE_PIN="6cfa41c7696f0d530450d509b1e07ce3d778bd4b"

install_tmux_powerline() {
    # Clone/refresh erikw/tmux-powerline at the pinned commit into
    # ${XDG_CONFIG_HOME:-$HOME/.config}/tmux-powerline/tmux-powerline — the
    # user-config dir stowed by the common/tmux-powerline package sits beside
    # it. Non-fatal on failure: .tmux.conf falls back to its inline status bar.
    local dir
    dir="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-powerline/tmux-powerline"

    if [[ -d "$dir/.git" ]]; then
        info "tmux-powerline present — resetting to pinned commit ${TMUX_POWERLINE_PIN:0:8}..."
        if (cd "$dir" &&
                # lowSpeed* bounds the offline case portably (no timeout(1) on macOS/Alpine)
                git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=15 fetch --quiet origin &&
                git checkout --quiet --detach "$TMUX_POWERLINE_PIN" &&
                git reset --hard --quiet "$TMUX_POWERLINE_PIN"); then
            info "tmux-powerline at pinned commit"
        else
            warn "Could not update tmux-powerline (offline?) — keeping the current checkout"
            FAILURES+=("tmux-powerline: update")
        fi
        return 0
    fi

    if [[ -d "$dir" ]]; then
        warn "$dir exists but is not a git clone — not touching it"
        FAILURES+=("tmux-powerline: unexpected directory")
        return 0
    fi

    info "Cloning tmux-powerline..."
    # Full clone (not shallow) so future pin bumps can still resolve the SHA.
    if ! git clone --quiet "$TMUX_POWERLINE_REPO_URL" "$dir"; then
        warn "Could not clone tmux-powerline (offline?) — the tmux status bar"
        warn "falls back to the plain statusline in .tmux.conf"
        FAILURES+=("tmux-powerline: clone")
        return 0
    fi
    if ! (cd "$dir" && git checkout --quiet --detach "$TMUX_POWERLINE_PIN"); then
        warn "Pinned commit $TMUX_POWERLINE_PIN not found — the clone stays on main"
        FAILURES+=("tmux-powerline: pin")
    fi
}

# --- Decrypt secrets ---

decrypt_secrets() {
    info "Decrypting secrets..."
    FORCE="$FORCE" "$DOTS_DIR/scripts/decrypt.sh"
}

# --- Stow dotfiles ---

STOW_BACKUP_DIR=""

backup_stow_conflicts() {
    # backup_stow_conflicts <pkg_dir> — before stowing, move any plain regular
    # file sitting at one of the package's target paths into
    # ~/.dots-backup-<timestamp>/, so a fresh distro's /etc/skel defaults
    # (Debian's ~/.bashrc, ~/.bash_logout, ...) do not abort the whole package.
    # Symlinks and directories are left alone: those are conflicts stow is
    # right to refuse. Nothing is deleted — the backup can be restored by hand.
    local pkg_dir="$1"
    local rel rel_dir target

    while IFS= read -r -d '' rel; do
        rel="${rel#./}"
        target="$HOME/$rel"
        if [[ -f "$target" && ! -L "$target" ]]; then
            if [[ -z "$STOW_BACKUP_DIR" ]]; then
                STOW_BACKUP_DIR="$HOME/.dots-backup-$(date +%Y%m%d%H%M%S)"
            fi
            rel_dir="${rel%/*}"
            [[ "$rel_dir" == "$rel" ]] && rel_dir="."
            mkdir -p "$STOW_BACKUP_DIR/$rel_dir"
            mv "$target" "$STOW_BACKUP_DIR/$rel"
            info "  Moved pre-existing ~/$rel -> ~${STOW_BACKUP_DIR#"$HOME"}/$rel"
        fi
    done < <(cd "$pkg_dir" && find . -mindepth 1 \( -type f -o -type d \) -print0)
}

stow_one_dir() {
    local base_dir="$1"
    local label="$2"
    local action_msg="$3"
    local found=0
    local pkg pkg_name

    for pkg in "$base_dir"/*/; do
        [[ -d "$pkg" ]] || continue
        if [[ $found -eq 0 ]]; then
            found=1
            info "$action_msg $label configs..."
        fi
        pkg_name="$(basename "$pkg")"
        info "  $action_msg $pkg_name"
        if [[ "$STOW_BACKUP" == "true" ]]; then
            backup_stow_conflicts "$pkg"
        fi
        if ! stow -d "$base_dir" -t "$HOME" --no-folding "${STOW_FLAGS[@]}" "$pkg_name"; then
            warn "Failed to stow $pkg_name — continuing with remaining packages"
            FAILURES+=("stow: $pkg_name")
        fi
    done
}

stow_packages() {
    STOW_FLAGS=("--no-folding")
    STOW_BACKUP="true"
    local action_msg="Stowing"

    case "${1:-}" in
        --restow) STOW_FLAGS+=("--restow"); action_msg="Re-stowing" ;;
        --adopt)  STOW_FLAGS+=("--adopt");  action_msg="Adopting + stowing"; STOW_BACKUP="false" ;;
        --unstow) STOW_FLAGS=("--no-folding" "--delete"); action_msg="Unstowing"; STOW_BACKUP="false" ;;
    esac

    stow_one_dir "$DOTS_DIR/common" "common" "$action_msg"
    stow_one_dir "$DOTS_DIR/$PLATFORM" "$PLATFORM" "$action_msg"
    # Environment/distro layers on top of the platform packages
    if [[ "$DISTRO" == "alpine" ]]; then
        stow_one_dir "$DOTS_DIR/alpine" "alpine" "$action_msg"
    fi
    if [[ "$ENV" == "wsl" ]]; then
        stow_one_dir "$DOTS_DIR/wsl" "wsl" "$action_msg"
    fi
    if [[ -n "$STOW_BACKUP_DIR" ]]; then
        info "Pre-existing files were backed up to $STOW_BACKUP_DIR"
    fi
}

# --- Verify ---

run_verify() {
    if [[ ! -f "$DOTS_DIR/scripts/verify.sh" ]]; then
        error "verify.sh not found at $DOTS_DIR/scripts/verify.sh — re-clone the repo."
    fi
    if [[ ! -x "$DOTS_DIR/scripts/verify.sh" ]]; then
        warn "verify.sh is not executable — running it with bash"
        bash "$DOTS_DIR/scripts/verify.sh"
        return
    fi
    "$DOTS_DIR/scripts/verify.sh"
}

# --- Main ---

main() {
    trap on_error ERR
    detect_env
    reattach_tty
    detect_privilege
    case "${1:-}" in
        -h|--help) usage ;;
        *)         init_audit_log ;;
    esac

    case "${1:-}" in
        -h|--help)
            usage
            ;;
        --verify)
            require_repo
            run_verify
            return
            ;;
        --unstow)
            require_repo
            ensure_tool stow || error "GNU Stow is required to unstow but could not be installed."
            stow_packages --unstow
            SUCCESS_MSG="All symlinks removed."
            ;;
        --restow|--adopt)
            require_repo
            ensure_tool stow || error "GNU Stow is required but could not be installed."
            install_tmux_powerline
            stow_packages "$1"
            ;;
        --force)
            FORCE=true
            require_priv
            install_core
            preflight_checks
            setup_repo
            install_tmux_powerline
            decrypt_secrets
            stow_packages
            ;;
        "")
            require_priv
            install_core
            preflight_checks
            setup_repo
            install_tmux_powerline
            decrypt_secrets
            stow_packages
            ;;
        *)
            error "Unknown option: $1 (see --help)"
            ;;
    esac

    finish
}

main "$@"