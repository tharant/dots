#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
export REPO_DIR
PLATFORM="$(uname -s)"
case "$PLATFORM" in
    Darwin) PLATFORM="macos" ;;
    Linux)  PLATFORM="linux" ;;
    *BSD)   PLATFORM="bsd" ;;
esac

QUIET=false
[[ "${1:-}" == "--quiet" ]] && QUIET=true

PASS=0
FAIL=0

pass() {
    PASS=$((PASS + 1))
    $QUIET || echo -e "  \033[1;32m✓\033[0m $*"
}

fail() {
    FAIL=$((FAIL + 1))
    $QUIET || echo -e "  \033[1;31m✗\033[0m $*"
}

section() {
    $QUIET || echo -e "\n\033[1;34m==>\033[0m $*"
}

# --- Required tools ---

section "Required tools"
for tool in age stow git; do
    if command -v "$tool" &>/dev/null; then
        pass "$tool installed"
    else
        fail "$tool not found"
    fi
done

# --- Symlink integrity ---

check_symlinks() {
    local stow_base="$1"
    local label="$2"

    [[ -d "$stow_base" ]] || return 0

    section "Symlinks: $label"
    for pkg_dir in "$stow_base"/*/; do
        [[ -d "$pkg_dir" ]] || continue
        local pkg_name
        pkg_name="$(basename "$pkg_dir")"

        while IFS= read -r -d '' file; do
            local rel="${file#"$pkg_dir"}"
            local target="$HOME/$rel"
            local expected="$file"

            if [[ -L "$target" ]]; then
                local actual
                actual="$(readlink "$target")"
                # Resolve relative symlinks for comparison
                if [[ "$actual" != /* ]]; then
                    actual="$(cd "$(dirname "$target")" && cd "$(dirname "$actual")" && pwd)/$(basename "$actual")"
                fi
                if [[ "$actual" == "$expected" ]]; then
                    pass "$label/$pkg_name: ~/$rel"
                else
                    fail "$label/$pkg_name: ~/$rel -> $actual (expected $expected)"
                fi
            elif [[ -e "$target" ]]; then
                fail "$label/$pkg_name: ~/$rel exists but is not a symlink"
            else
                fail "$label/$pkg_name: ~/$rel missing"
            fi
        done < <(find "$pkg_dir" -type f -print0)
    done
}

check_symlinks "$REPO_DIR/common" "common"
check_symlinks "$REPO_DIR/$PLATFORM" "$PLATFORM"
