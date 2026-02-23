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

# --- File permissions ---

section "File permissions"
if [[ -d "$HOME/.ssh" ]]; then
    ssh_perms="$(stat -f '%Lp' "$HOME/.ssh" 2>/dev/null || stat -c '%a' "$HOME/.ssh" 2>/dev/null)"
    if [[ "$ssh_perms" == "700" ]]; then
        pass "$HOME/.ssh/ is 700"
    else
        fail "$HOME/.ssh/ is $ssh_perms (expected 700)"
    fi

    while IFS= read -r -d '' keyfile; do
        fname="$(basename "$keyfile")"
        perms="$(stat -f '%Lp' "$keyfile" 2>/dev/null || stat -c '%a' "$keyfile" 2>/dev/null)"
        if [[ "$perms" == "600" ]]; then
            pass "$HOME/.ssh/$fname is 600"
        else
            fail "$HOME/.ssh/$fname is $perms (expected 600)"
        fi
    done < <(find "$HOME/.ssh" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' -print0 2>/dev/null)
else
    fail "$HOME/.ssh/ directory does not exist"
fi

# --- Secrets decrypted ---

SECRETS_DIR="$REPO_DIR/secrets"

declare -A TARGET_MAP=(
    ["ssh"]="$HOME/.ssh"
    ["tokens"]="$HOME/.config/tokens"
)

section "Decrypted secrets"
found_secrets=0
while IFS= read -r -d '' age_file; do
    found_secrets=$((found_secrets + 1))
    rel_path="${age_file#"$SECRETS_DIR"/}"
    subdir="${rel_path%%/*}"
    filename="${rel_path#*/}"
    filename="${filename%.age}"

    target_dir="${TARGET_MAP[$subdir]:-}"
    if [[ -z "$target_dir" ]]; then
        fail "No target mapping for $rel_path"
        continue
    fi

    target="$target_dir/$filename"
    if [[ -f "$target" ]]; then
        pass "$rel_path -> $target"
    else
        fail "$rel_path: expected $target (not found)"
    fi
done < <(find "$SECRETS_DIR" -name '*.age' -print0 2>/dev/null)

if [[ $found_secrets -eq 0 ]]; then
    $QUIET || echo "  (no .age files found)"
fi

# --- Summary ---

echo ""
if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[1;32mAll $PASS checks passed.\033[0m"
else
    echo -e "\033[1;31m$FAIL failed\033[0m, $PASS passed."
fi

exit "$( [[ $FAIL -eq 0 ]] && echo 0 || echo 1 )"
