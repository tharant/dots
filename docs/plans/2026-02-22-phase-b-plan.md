# Phase B Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add deployment verification, harden setup.sh with error handling + idempotency, and add a minimal neovim config package.

**Architecture:** Three independent deliverables: a new `verify.sh` script, improvements to the existing `setup.sh`, and a new `common/nvim/` stow package. `verify.sh` is built first since `setup.sh` gains a `--verify` flag that calls it.

**Tech Stack:** Bash (shellcheck-clean), Lua (neovim init)

---

### Task 1: Create `scripts/verify.sh` — helpers and tool checks

**Files:**
- Create: `scripts/verify.sh`

**Step 1: Create verify.sh with helpers and required-tools check**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
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
```

**Step 2: Run shellcheck**

Run: `shellcheck -s bash -e SC1090,SC1091 scripts/verify.sh`
Expected: No output (clean)

**Step 3: Commit**

```bash
git add scripts/verify.sh
git commit -m "Add verify.sh with helpers and required-tools check"
```

---

### Task 2: Add symlink integrity check to verify.sh

**Files:**
- Modify: `scripts/verify.sh` (append before summary)

**Step 1: Add symlink check function**

Append after the "Required tools" section:

```bash
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
```

**Step 2: Run shellcheck**

Run: `shellcheck -s bash -e SC1090,SC1091 scripts/verify.sh`
Expected: Clean

**Step 3: Commit**

```bash
git add scripts/verify.sh
git commit -m "Add symlink integrity check to verify.sh"
```

---

### Task 3: Add permissions and secrets checks, plus summary

**Files:**
- Modify: `scripts/verify.sh` (append)

**Step 1: Add permissions check, secrets check, and summary**

Append after the symlink checks:

```bash
# --- File permissions ---

section "File permissions"
if [[ -d "$HOME/.ssh" ]]; then
    ssh_perms="$(stat -f '%Lp' "$HOME/.ssh" 2>/dev/null || stat -c '%a' "$HOME/.ssh" 2>/dev/null)"
    if [[ "$ssh_perms" == "700" ]]; then
        pass "~/.ssh/ is 700"
    else
        fail "~/.ssh/ is $ssh_perms (expected 700)"
    fi

    while IFS= read -r -d '' keyfile; do
        fname="$(basename "$keyfile")"
        perms="$(stat -f '%Lp' "$keyfile" 2>/dev/null || stat -c '%a' "$keyfile" 2>/dev/null)"
        if [[ "$perms" == "600" ]]; then
            pass "~/.ssh/$fname is 600"
        else
            fail "~/.ssh/$fname is $perms (expected 600)"
        fi
    done < <(find "$HOME/.ssh" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' -print0 2>/dev/null)
else
    fail "~/.ssh/ directory does not exist"
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
```

**Step 2: Run shellcheck**

Run: `shellcheck -s bash -e SC1090,SC1091 scripts/verify.sh`
Expected: Clean

**Step 3: Test it**

Run: `./scripts/verify.sh`
Expected: Colored output showing pass/fail for each category, summary at end.

**Step 4: Commit**

```bash
git add scripts/verify.sh
git commit -m "Add permissions, secrets, and summary to verify.sh"
```

---

### Task 4: Improve setup.sh — error handling

**Files:**
- Modify: `scripts/setup.sh`

**Step 1: Add error trap after the helpers section (line 24)**

Insert after the `error()` function (after line 24):

```bash
# Track failures for non-fatal errors
FAILURES=()

on_error() {
    local exit_code=$?
    error "Step failed with exit code $exit_code. Run with --help for options."
}
```

**Step 2: Make stow_packages resilient — catch per-package failures**

Replace the stow command calls in `stow_packages` (lines 136 and 147) to catch errors per-package instead of aborting. Replace the entire `stow_packages` function (lines 118-150) with:

```bash
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
```

**Step 3: Update main() to set the trap and report failures**

Replace the main function (lines 154-190) with:

```bash
main() {
    trap on_error ERR
    PLATFORM="$(detect_platform)"
    info "Detected platform: $PLATFORM"

    case "${1:-}" in
        -h|--help) usage ;;
        --restow)
            install_stow
            stow_packages --restow
            ;;
        --adopt)
            install_stow
            stow_packages --adopt
            ;;
        --unstow)
            install_stow
            stow_packages --unstow
            info "All symlinks removed."
            report_failures
            return
            ;;
        --force)
            FORCE=true
            install_age
            install_stow
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
```

Add `report_failures` helper after the `FAILURES` array declaration:

```bash
report_failures() {
    if [[ ${#FAILURES[@]} -gt 0 ]]; then
        warn "The following steps had issues:"
        for f in "${FAILURES[@]}"; do
            warn "  - $f"
        done
        return 1
    fi
}
```

**Step 4: Add FORCE=false default at the top (after DOTS_DIR)**

```bash
FORCE="${FORCE:-false}"
```

**Step 5: Update usage() to include new flags**

Replace usage function:

```bash
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
```

**Step 6: Run shellcheck**

Run: `shellcheck -s bash -e SC1090,SC1091 scripts/setup.sh`
Expected: Clean

**Step 7: Commit**

```bash
git add scripts/setup.sh
git commit -m "Improve setup.sh error handling: trap, per-package resilience, failure reporting"
```

---

### Task 5: Improve setup.sh — idempotent decrypt

**Files:**
- Modify: `scripts/decrypt.sh`

**Step 1: Add freshness check to decrypt_file**

In `scripts/decrypt.sh`, replace the `decrypt_file` function (lines 32-56) with:

```bash
decrypt_file() {
    local age_file="$1"
    local rel_path="${age_file#"$SECRETS_DIR"/}"
    local subdir="${rel_path%%/*}"
    local filename="${rel_path#*/}"
    filename="${filename%.age}"

    local target_dir="${TARGET_MAP[$subdir]:-}"
    if [[ -z "$target_dir" ]]; then
        echo "Warning: No target mapping for subdir '$subdir', skipping $rel_path"
        return
    fi

    local target="$target_dir/$filename"

    # Skip if target exists and is newer than source (unless FORCE)
    if [[ "${FORCE:-false}" != "true" && -f "$target" && "$target" -nt "$age_file" ]]; then
        echo "Skipping (up to date): $rel_path -> $target"
        return
    fi

    mkdir -p "$target_dir"

    echo "Decrypting: $rel_path -> $target"
    age -d "${AGE_ARGS[@]}" -o "$target" "$age_file"

    # Set restrictive permissions for SSH keys
    if [[ "$subdir" == "ssh" ]]; then
        chmod 600 "$target"
        chmod 700 "$target_dir"
    fi
}
```

**Step 2: Pass FORCE from setup.sh**

In `scripts/setup.sh`, update the `decrypt_secrets` function to pass FORCE:

```bash
decrypt_secrets() {
    info "Decrypting secrets..."
    FORCE="$FORCE" "$DOTS_DIR/scripts/decrypt.sh"
}
```

**Step 3: Run shellcheck on both files**

Run: `shellcheck -s bash -e SC1090,SC1091 scripts/decrypt.sh scripts/setup.sh`
Expected: Clean

**Step 4: Commit**

```bash
git add scripts/decrypt.sh scripts/setup.sh
git commit -m "Add idempotent decrypt: skip up-to-date secrets unless --force"
```

---

### Task 6: Create minimal neovim config

**Files:**
- Create: `common/nvim/.config/nvim/init.lua`

**Step 1: Create the directory and init.lua**

```lua
-- Minimal neovim config — no plugin manager, sensible defaults only

-- Leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true
vim.opt.hlsearch = true

-- Indentation
vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.smartindent = true

-- Clipboard
vim.opt.clipboard = "unnamedplus"

-- Visual
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.scrolloff = 8
vim.opt.cursorline = true
vim.opt.colorcolumn = "100"

-- File handling
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = true

-- Misc
vim.opt.updatetime = 250
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.mouse = "a"

-- Keymaps
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Move to below window" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Move to above window" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })
vim.keymap.set("n", "[b", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
vim.keymap.set("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })
```

**Step 2: Commit**

```bash
git add common/nvim/.config/nvim/init.lua
git commit -m "Add minimal neovim config package"
```

---

### Task 7: Update TODO.md and final verification

**Files:**
- Modify: `TODO.md`

**Step 1: Mark Phase B items as done**

Change the three Phase B items from `- [ ]` to `- [x]`.

**Step 2: Run verify.sh**

Run: `./scripts/verify.sh`
Expected: All checks pass (or known-expected failures only).

**Step 3: Commit**

```bash
git add TODO.md
git commit -m "Mark Phase B complete in TODO.md"
```
