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

- [x] Add `scripts/verify.sh` — validate symlinks, permissions, file existence
- [x] Improve `setup.sh` — better error handling, idempotent re-runs
- [x] Add neovim config package (`common/nvim/`)

## Phase C: Polish

- [x] Add a taskrunner (Makefile or Justfile) for common operations
- [x] Prune BSD skeleton (or populate it)
- [x] Add `.editorconfig` for consistent formatting
