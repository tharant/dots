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
