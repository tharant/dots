# TODO

Planned enhancements for the dots repo, organized into phases.

## Phase A: Fix & Consolidate

- [x] Fix circular bash sourcing (`.bashrc` ↔ `.bash_profile` infinite loop)
- [x] Reorganize bash config: move portable parts from `linux/bash/.bash_profile` to `common/bash/.bashrc`
- [x] Trim `linux/bash/.bash_profile` to Linux-only items
- [x] Remove machine-specific paths from `common/bash/.bashrc` (opencode, sbt)
- [x] Create `common/git/.gitconfig` (adopt or create)
- [x] Add `common/ssh/.ssh/config`
- [x] Create `macos/bash/.bash_profile` with Homebrew + macOS-specific setup

## Phase B: Robustness & Verification

- [ ] Add `scripts/verify.sh` — validate symlinks, permissions, file existence
- [ ] Improve `setup.sh` — better error handling, idempotent re-runs
- [ ] Add neovim config package (`common/nvim/`)

## Phase C: Polish

- [ ] Add a taskrunner (Makefile or Justfile) for common operations
- [ ] Prune BSD skeleton (or populate it)
- [ ] Add `.editorconfig` for consistent formatting
