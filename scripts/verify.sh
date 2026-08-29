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
        # stow's default ignore set: these are never deployed, so skip them
        done < <(find "$pkg_dir" -type f \
            ! -name '*~' ! -name '#*#' ! -name '.git*' ! -name '.DS_Store' -print0)
    done
}

check_symlinks "$REPO_DIR/common" "common"
check_symlinks "$REPO_DIR/$PLATFORM" "$PLATFORM"

# --- File permissions ---

section "File permissions"
if [[ -d "$HOME/.ssh" ]]; then
    ssh_perms="$(stat -c '%a' "$HOME/.ssh" 2>/dev/null || stat -f '%Lp' "$HOME/.ssh" 2>/dev/null)"
    if [[ "$ssh_perms" == "700" ]]; then
        pass "$HOME/.ssh/ is 700"
    else
        fail "$HOME/.ssh/ is $ssh_perms (expected 700)"
    fi

    while IFS= read -r -d '' keyfile; do
        fname="$(basename "$keyfile")"
        perms="$(stat -c '%a' "$keyfile" 2>/dev/null || stat -f '%Lp' "$keyfile" 2>/dev/null)"
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

# Target mapping (case-based: no declare -A, keeps this script runnable under
# the bash 3.2 that a fresh macOS curl|bash bootstrap starts with).
target_dir_for() {
    case "$1" in
        ssh)    echo "$HOME/.ssh" ;;
        tokens) echo "$HOME/.config/tokens" ;;
        *)      echo "" ;;
    esac
}

section "Decrypted secrets"
found_secrets=0
while IFS= read -r -d '' age_file; do
    rel_path="${age_file#"$SECRETS_DIR"/}"
    # Passphrase fallback copies (X.phrase.age) exist only as vault copies of
    # X.age — the deployed target is X itself, so skip them here
    case "$rel_path" in
        *.phrase.age) continue ;;
    esac
    found_secrets=$((found_secrets + 1))
    subdir="${rel_path%%/*}"
    filename="${rel_path#*/}"
    filename="${filename%.age}"

    target_dir="$(target_dir_for "$subdir")"
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

# --- direnv/runtimes ---

section "direnv + runtimes"

# Soft presence: setup.sh installs direnv as a hard requirement, but verify.sh
# can legitimately run pre-bootstrap, so absence is reported, not failed.
if command -v direnv &>/dev/null; then
    pass "direnv installed"
else
    $QUIET || echo "  - direnv not found (soft check; setup.sh installs it)"
fi

# The direnv hook must sit after the trueline source: trueline resets
# PROMPT_COMMAND when it loads and never chains, silently discarding a hook
# placed before it. Compare line numbers so a reorder cannot slip through.
bashrc="$HOME/.bashrc"
if [[ -f "$bashrc" ]]; then
    hook_line="$(grep -n 'direnv hook bash' "$bashrc" 2>/dev/null | head -1 | cut -d: -f1 || true)"
    trueline_line="$(grep -n 'source .*trueline' "$bashrc" 2>/dev/null | head -1 | cut -d: -f1 || true)"
    if [[ -z "$hook_line" ]]; then
        fail "direnv hook missing from $HOME/.bashrc"
    elif [[ -z "$trueline_line" ]]; then
        fail "trueline source missing from $HOME/.bashrc (cannot confirm hook order)"
    elif [[ "$hook_line" -le "$trueline_line" ]]; then
        fail "direnv hook (line $hook_line) must come after the trueline source (line $trueline_line)"
    else
        pass "direnv hook (line $hook_line) ordered after the trueline source (line $trueline_line)"
    fi
else
    fail "$HOME/.bashrc not found"
fi

# Content check on the symlink target in the repo — the symlink itself is
# already covered by check_symlinks auto-discovery.
direnvrc="$REPO_DIR/common/direnv/.config/direnv/direnvrc"
if [[ -f "$direnvrc" ]] && grep -Eq '^[[:space:]]*(function[[:space:]]+)?use_runtimes[[:space:]]*\(\)' "$direnvrc"; then
    pass "direnvrc defines use_runtimes"
else
    fail "direnvrc missing or does not define use_runtimes ($direnvrc)"
fi

# Symlink existence is covered by check_symlinks; the executable bit lives on
# the repo file, which is what -x tests through the deployed symlink.
if [[ -x "$HOME/bin/runtimes" ]]; then
    pass "$HOME/bin/runtimes is executable"
else
    fail "$HOME/bin/runtimes missing or not executable"
fi

# Soft: uv/fnm/sdkman are best-effort installs and the BSD tier legitimately
# ships without them, so absence is reported, not failed. sdkman has no binary
# on PATH outside an interactive shell; its install dir is the presence signal.
for tool in uv fnm; do
    if command -v "$tool" &>/dev/null; then
        pass "$tool installed"
    else
        $QUIET || echo "  - $tool not found (optional)"
    fi
done
if command -v sdk &>/dev/null || [[ -d "$HOME/.sdkman" ]]; then
    pass "sdkman installed"
else
    $QUIET || echo "  - sdkman not found (optional)"
fi

# --- Summary ---

echo ""
if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[1;32mAll $PASS checks passed.\033[0m"
else
    echo -e "\033[1;31m$FAIL failed\033[0m, $PASS passed."
fi

exit "$( [[ $FAIL -eq 0 ]] && echo 0 || echo 1 )"
