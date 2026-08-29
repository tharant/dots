# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Central dotfiles repository for bash across macOS, Debian flavors, Alpine, WSL2, and occasionally BSD. Hosted publicly on GitHub. Contains both public configs and encrypted secrets (SSH private keys, tokens, etc.). All blessed targets should look and behave identically: platform deltas live in per-platform Stow packages, never in conditionals inside `common/`.

## Architecture

### Directory Layout

```
dots/
├── common/          # Shared configs across all platforms (GNU Stow packages)
│   ├── bash/        # .bashrc (with .bashrc.platform.d hook), aliases, functions, ...
│   ├── bin/         # ~/bin shims: loadavg, tmux-copy (uname-branching, one file for all)
│   ├── git/         # .gitconfig, .gitignore_global
│   ├── nvim/        # .config/nvim/init.lua (clipboard-guarded)
│   ├── ssh/         # ssh config (portable; UseKeychain behind IgnoreUnknown)
│   ├── tmux/        # .tmux.conf (single, identical on every platform)
│   ├── trueline/    # .local/trueline/ (patched trueline.sh + .trueline.conf)
│   └── vim/         # .vimrc, .vim/ (vim-plug; plug.vim vendored, coc on 'release' branch)
├── macos/           # macOS overrides → .bashrc.platform.d/macos.sh, .bash_profile
├── linux/           # Linux overrides  → .bashrc.platform.d/linux.sh, .bash_profile
├── alpine/          # Alpine overrides → .bashrc.platform.d/alpine.sh (new package)
├── wsl/             # WSL2 overrides   → .bashrc.platform.d/wsl.sh (new package)
├── bsd/             # BSD overrides    → .bashrc.platform.d/bsd.sh, .bash_profile
├── secrets/         # Encrypted files (dual artifacts *.age + *.phrase.age)
│   ├── recipients.txt  # age public key(s) for encryption (public, safe to commit)
│   ├── ssh/         # Encrypted SSH private keys
│   └── tokens/      # Encrypted API tokens, credentials
├── scripts/
│   ├── setup.sh     # Bootstrap (curl-able): pkg_install dispatcher, platform/distro/env
│   │                #   detection (macos/linux/bsd + alpine + wsl layers), decrypt, stow
│   ├── verify.sh    # Symlink + permissions health check (stow-ignore aware)
│   ├── encrypt.sh   # Encrypt a file (age key + passphrase copies)
│   └── decrypt.sh   # Decrypt secrets (age key if present, else passphrase)
├── docs/            # Reference documentation
├── Justfile         # Task runner (just) for common operations
├── .editorconfig    # Editor formatting settings
└── .gitignore       # Blocks plaintext secret patterns (id_* etc.)
```

### Platform layer (bash)

`.bashrc` sources every file in `~/.bashrc.platform.d/` (2-line hook — the only sanctioned conditional in `common/` besides `command -v` guards for optional tools). Each platform package ships a `bash/.bashrc.platform.d/<name>.sh`:

- `macos/` → `macos.sh` (locale `en_US.UTF-8`, brew shellenv arch-aware, LSCOLORS, macOS-only functions)
- `linux/` → `linux.sh` (locale with C.UTF-8 fallback, dircolors, `~/.local/bin` PATH)
- `alpine/` → `alpine.sh` (`C.UTF-8` — musl has no `en_US.UTF-8`; shipped for Alpine incl. WSL-Alpine)
- `wsl/` → `wsl.sh` (self-detects via `/proc/version`; trims `/mnt/[a-z]` PATH entries, absolute-path `clip.exe`)
- `bsd/` → `bsd.sh`

Layers stack: a WSL2-Alpine distro gets both `alpine.sh` and `wsl.sh` (setup.sh detects distro via `/etc/os-release`, WSL via `/proc/version`/`$WSL_DISTRO_NAME`, and stows `common` + `$PLATFORM` + `alpine` + `wsl` as applicable).

Platform files load in every interactive shell (login or not); `common/bash/.bash_profile` files are 5-line `source ~/.bashrc` shims. The trueline prompt is gated on bash ≥ 4.3 (macOS `/bin/bash` 3.2 gets a clean skip, not an error).

### Deployment with GNU Stow

Each subdirectory inside `common/` and the platform dirs is a Stow package. Files are mirrored to `$HOME` via symlinks. For example, `common/bash/.bashrc` symlinks to `~/.bashrc`. The `--no-folding` flag is used to avoid replacing existing directories with symlinks (and is kept alongside `--delete` when unstowing). `setup.sh` stows `common/` + the platform dir + distro/env dirs (see platform layer above), sets `core.hooksPath .githooks` so the shellcheck pre-commit hook is actually installed, and pulls with `--autostash` when the working tree is dirty (e.g. after a prior `--adopt`).

### Secrets: Dual age Artifacts

Secrets are stored as **two age artifacts per secret**, each encrypting the same plaintext:

- `X.age` — encrypted to the recipients in `secrets/recipients.txt`
- `X.phrase.age` — encrypted with a passphrase

**Why two files:** the age file format supports combining recipient stanzas with a passphrase stanza, but no CLI (age or rage) can produce such a file — `age -p -R` is rejected. Dual artifacts replicate the "either unlocks it" property with plain age:

- **Established machine:** age identity at `~/.age/keys.txt` — no prompts needed
- **Fresh machine (no keys):** passphrase prompt — enables `curl | bash` bootstrap

The decrypt script (`scripts/decrypt.sh`) tries the age identity first and falls back to the passphrase copy. Legacy single-artifact secrets (passphrase-only `X.age`) still decrypt. Target locations are mapped by subdirectory: `secrets/ssh/*` → `~/.ssh/`, `secrets/tokens/*` → `~/.config/tokens/`.

### New Machine Bootstrap

```bash
curl -fsSL https://raw.githubusercontent.com/tharant/dots/main/scripts/setup.sh | bash
```

This installs age + GNU Stow, clones the repo to `~/.dots`, prompts for passphrase to decrypt secrets, and stows all configs. Platform is auto-detected via `uname -s`.

## Commands

A `Justfile` provides the primary interface. Run `just` to see all recipes.

```bash
# Core operations
just setup                    # Full bootstrap (install deps, clone, decrypt, stow)
just restow                   # Re-stow all packages (after git pull)
just adopt                    # Adopt existing files into repo, then stow
just unstow                   # Remove all managed symlinks
just verify                   # Run verification checks
just encrypt <file>           # Encrypt a file (age key + passphrase copies)
just decrypt                  # Decrypt all secrets

# Dev
just lint                     # Shellcheck all scripts and bash dotfiles
just add-package <plat> <name>  # Scaffold a new stow package

# Info
just status                   # Quick symlink health check
just list-packages            # List stow packages by platform
just diff-secrets             # Compare encrypted vs decrypted timestamps
```

Scripts can also be called directly:

```bash
./scripts/setup.sh                              # Full bootstrap (or curl it)
./scripts/setup.sh --restow                     # Re-stow all packages (after git pull)
./scripts/setup.sh --adopt                      # Adopt existing files into repo, then stow
./scripts/setup.sh --unstow                     # Remove all managed symlinks
./scripts/encrypt.sh <plaintext> <output.age>   # Encrypt a file (writes X.age + X.phrase.age)
./scripts/decrypt.sh                            # Decrypt all secrets
```

## Critical Rules

- **Never commit unencrypted secrets.** `.gitignore` blocks the `id_*` key family (except `*.pub`) and common patterns, but always verify with `git status` before committing.
- **The age private key (`keys.txt`) must never be in this repo.** `secrets/recipients.txt` is public keys only — safe to commit.
- **File permissions:** SSH keys `chmod 600`, `.ssh/` dir `chmod 700`, decrypted tokens `chmod 600`. `decrypt.sh` enforces this (with `umask 077` from the start) for every target directory.
- **Platform-specific configs go in platform dirs**, not as conditionals in common configs. Keep `common/` portable across macOS, Linux, and BSD. Sanctioned exceptions: the `~/.bashrc.platform.d` source hook in `.bashrc`, the bash ≥4.3 guard before trueline, and `command -v` guards for tools that are genuinely optional per platform.
- **Stow package layout must mirror `$HOME`.** E.g., to deploy `~/.bashrc`, the file goes at `common/bash/.bashrc`.
- **Bootstrap scripts must run under bash 3.2** (fresh-macOS `curl | bash` resolves `/bin/bash` 3.2): no `declare -A`, no `mapfile`, no `${var,,}` in `scripts/`, `.githooks/`, or the shims. Interactive configs require bash ≥ 4.3, which setup.sh installs.
- **Run `shellcheck` before committing any bash files.** A pre-commit hook (`.githooks/pre-commit`) enforces this automatically (setup.sh installs the hook path). Fix all errors and warnings; SC1090/SC1091 (non-constant source) are globally excluded. If a warning seems like a false positive, ask the user before suppressing it with a directive.
