#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for setting up dotfiles on a new machine.
# Can be run via: curl -fsSL https://raw.githubusercontent.com/USER/dots/main/scripts/setup.sh | bash
# Or after cloning: ./scripts/setup.sh

REPO_URL="${DOTS_REPO_URL:-https://github.com/tharant/dots.git}"
DOTS_DIR="${DOTS_DIR:-$HOME/.dots}"
FORCE="${FORCE:-false}"

usage() {
    echo "Usage: $(basename "$0") [--restow] [--adopt] [--unstow] [--force] [--verify]"
    echo "  (no args)   Full bootstrap: install deps, clone, decrypt, stow"
    echo "  --restow    Re-stow all packages (use after git pull)"
    echo "  --adopt     Adopt existing files into the repo, then re-stow"
    echo "  --unstow    Remove all symlinks managed by stow"
    echo "  --force     Force re-decrypt and re-stow (skip freshness checks)"
    echo "  --verify    Run verification checks on current deployment"
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
        return 1
    fi
}

detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *BSD)   echo "bsd" ;;
        *)      error "Unsupported platform: $(uname -s)" ;;
    esac
}

command_exists() { command -v "$1" &>/dev/null; }

# --- Install dependencies ---

install_age() {
    if command_exists age; then
        info "age already installed"
        return
    fi

    info "Installing age..."
    case "$PLATFORM" in
        macos)
            if command_exists brew; then
                brew install age
            else
                error "Homebrew not found. Install from https://brew.sh first, or install age manually."
            fi
            ;;
        linux)
            if command_exists apt-get; then
                sudo apt-get update && sudo apt-get install -y age
            elif command_exists dnf; then
                sudo dnf install -y age
            elif command_exists pacman; then
                sudo pacman -S --noconfirm age
            else
                error "No supported package manager found. Install age manually."
            fi
            ;;
        bsd)
            if command_exists pkg; then
                sudo pkg install -y age
            else
                error "pkg not found. Install age manually."
            fi
            ;;
    esac
}

install_stow() {
    if command_exists stow; then
        info "GNU Stow already installed"
        return
    fi

    info "Installing GNU Stow..."
    case "$PLATFORM" in
        macos)  brew install stow ;;
        linux)
            if command_exists apt-get; then
                sudo apt-get install -y stow
            elif command_exists dnf; then
                sudo dnf install -y stow
            elif command_exists pacman; then
                sudo pacman -S --noconfirm stow
            fi
            ;;
        bsd)    sudo pkg install -y stow ;;
    esac
}

install_just() {
    if command_exists just; then
        info "just already installed"
        return
    fi

    info "Installing just..."
    case "$PLATFORM" in
        macos)
            if command_exists brew; then
                brew install just
            else
                error "Homebrew not found. Install from https://brew.sh first, or install just manually."
            fi
            ;;
        linux)
            if command_exists apt-get; then
                sudo apt-get install -y just 2>/dev/null || {
                    warn "just not in apt repos — install manually from https://github.com/casey/just"
                    FAILURES+=("install: just")
                    return
                }
            elif command_exists dnf; then
                sudo dnf install -y just 2>/dev/null || {
                    warn "just not in dnf repos — install manually"
                    FAILURES+=("install: just")
                    return
                }
            elif command_exists pacman; then
                sudo pacman -S --noconfirm just
            else
                warn "No supported package manager found. Install just manually."
                FAILURES+=("install: just")
            fi
            ;;
        bsd)
            if command_exists pkg; then
                sudo pkg install -y just
            else
                warn "pkg not found. Install just manually."
                FAILURES+=("install: just")
            fi
            ;;
    esac
}

# --- Clone or update repo ---

setup_repo() {
    if [[ -d "$DOTS_DIR/.git" ]]; then
        info "Repo exists at $DOTS_DIR, pulling latest..."
        git -C "$DOTS_DIR" pull --ff-only
    else
        info "Cloning dotfiles repo..."
        git clone "$REPO_URL" "$DOTS_DIR"
    fi
}

# --- Decrypt secrets ---

decrypt_secrets() {
    info "Decrypting secrets..."
    FORCE="$FORCE" "$DOTS_DIR/scripts/decrypt.sh"
}

# --- Stow dotfiles ---

stow_packages() {
    local stow_flags=("--no-folding")
    local action_label="Stowing"

    case "${1:-}" in
        --restow) stow_flags+=("--restow"); action_label="Re-stowing" ;;
        --adopt)  stow_flags+=("--adopt");  action_label="Adopting + stowing" ;;
        --unstow) stow_flags=("--delete");  action_label="Unstowing" ;;
    esac

    local stow_dir="$DOTS_DIR"

    stow_one_dir() {
        local base_dir="$1"
        local label="$2"
        [[ -d "$base_dir" ]] || return 0
        info "$action_label $label configs..."
        for pkg in "$base_dir"/*/; do
            [[ -d "$pkg" ]] || continue
            local pkg_name
            pkg_name="$(basename "$pkg")"
            info "  $action_label $pkg_name"
            if ! stow -d "$base_dir" -t "$HOME" "${stow_flags[@]}" "$pkg_name" 2>&1; then
                warn "Failed to stow $pkg_name — continuing with remaining packages"
                FAILURES+=("stow: $pkg_name")
            fi
        done
    }

    stow_one_dir "$stow_dir/common" "common"
    stow_one_dir "$stow_dir/$PLATFORM" "$PLATFORM"
}

# --- Main ---

main() {
    trap on_error ERR
    PLATFORM="$(detect_platform)"
    info "Detected platform: $PLATFORM"

    case "${1:-}" in
        -h|--help) usage ;;
        --restow)
            install_stow
            install_just
            stow_packages --restow
            ;;
        --adopt)
            install_stow
            install_just
            stow_packages --adopt
            ;;
        --unstow)
            install_stow
            install_just
            stow_packages --unstow
            info "All symlinks removed."
            report_failures
            return
            ;;
        --force)
            FORCE=true
            install_age
            install_stow
            install_just
            setup_repo
            decrypt_secrets
            stow_packages
            ;;
        --verify)
            "$DOTS_DIR/scripts/verify.sh"
            return
            ;;
        "")
            install_age
            install_stow
            install_just
            setup_repo
            decrypt_secrets
            stow_packages
            ;;
        *)
            error "Unknown option: $1 (see --help)"
            ;;
    esac

    info "Done! Dotfiles deployed."
    info "Log out and back in (or source ~/.bashrc) for changes to take effect."
    report_failures
}

main "$@"
