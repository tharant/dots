# Phase B Design: Robustness & Verification

## 1. `scripts/verify.sh` — Validate deployment state

Standalone script that checks the health of a dotfiles deployment. Exits 0 if everything passes, 1 if any check fails.

### Checks

**Symlink integrity:** Walk every stow package directory under `common/` and `$PLATFORM/`. For each file, verify `~/<relative_path>` exists and is a symlink pointing to the correct repo path. Report missing or broken symlinks.

**File permissions:** Check `~/.ssh/` is 700 and all files inside are 600. Extensible for future permission requirements.

**Required tools:** Verify `age`, `stow`, and `git` are installed and on PATH.

**Secrets decrypted:** For each `.age` file in `secrets/`, check that the corresponding decrypted target exists (using the same subdir-to-target mapping from `decrypt.sh`). Does not check file contents.

### Output format

Colorized pass/fail per check category, with individual failures listed. Summary line at the end: "X passed, Y failed".

### Interface

```
./scripts/verify.sh           # Run all checks
./scripts/verify.sh --quiet   # Exit code only, no output on success
```

## 2. `setup.sh` improvements

### Error handling

- Add `trap cleanup ERR` that prints which step failed, the exit code, and a hint (e.g., "Run with --help for options").
- Each major function (install_age, install_stow, setup_repo, decrypt_secrets, stow_packages) prints its name on entry so failures are traceable.
- Non-fatal warnings (e.g., stow conflict on a single package) don't abort the whole script — continue with remaining packages and report failures at the end.

### Idempotency

- `install_age` / `install_stow`: Already idempotent (skip if installed). No changes needed.
- `setup_repo`: Already idempotent (pull if exists, clone if not). No changes needed.
- `decrypt_secrets`: Skip files whose decrypted target already exists and is newer than the `.age` source. Add `--force` flag to override.
- `stow_packages`: Stow is already mostly idempotent, but conflicts on existing non-symlink files cause errors. Catch these per-package and report rather than aborting.
- Add `--force` flag: When set, re-decrypt and re-stow regardless of existing state.

### New flags

- `--force`: Override skip logic for decrypt and stow steps.
- `--verify`: Run `verify.sh` after setup completes (call it as a post-step).

## 3. `common/nvim/.config/nvim/init.lua` — Minimal neovim config

A single `init.lua` file with sensible defaults, no plugin manager. Deployed via stow to `~/.config/nvim/init.lua`.

### Contents

- Line numbers (relative + absolute)
- Search: incremental, ignore case with smart case
- Indentation: 4 spaces, expandtab
- Clipboard: system clipboard integration (`unnamedplus`)
- Leader key: space
- Basic keymaps: clear search highlight, window navigation, buffer navigation
- Visual: sign column, scroll offset, terminal colors
- File handling: no swap files, undo file persistence
