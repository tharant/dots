# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Central dotfiles repository for Bash configurations across macOS, Linux, and BSD. Hosted publicly on GitHub. Contains both public configs and encrypted secrets (SSH private keys, tokens, etc.).

## Architecture

### Directory Layout

```
dots/
├── common/          # Shared configs across all platforms (GNU Stow packages)
│   ├── bash/        # .bashrc, .bash_profile, .bash_aliases
│   ├── git/         # .gitconfig, .gitignore_global
│   └── ssh/         # ssh config (public parts)
├── macos/           # macOS-specific overrides (Stow packages)
├── linux/           # Linux-specific overrides (Stow packages)
│   ├── bash/        # .bash_profile
│   └── vim/         # .vimrc, .vim/
├── bsd/             # BSD-specific overrides (Stow packages)
├── secrets/         # Encrypted files (*.age only, hybrid encrypted)
│   ├── recipients.txt  # age public key(s) for encryption
│   ├── ssh/         # Encrypted SSH private keys
│   └── tokens/      # Encrypted API tokens, credentials
├── scripts/
│   ├── setup.sh     # Bootstrap script (curl-able, installs deps, decrypts, stows)
│   ├── encrypt.sh   # Encrypt a file (hybrid: passphrase + age key)
│   └── decrypt.sh   # Decrypt secrets (tries age key, falls back to passphrase)
├── docs/            # Reference documentation
│   ├── bash-startup-order.md  # Bash startup file loading order
│   └── stow-adopt-workflow.md # How to adopt existing configs with stow --adopt
└── .gitignore       # Blocks plaintext secret patterns
```

### Deployment with GNU Stow

Each subdirectory inside `common/` and platform dirs is a Stow package. Files are mirrored to `$HOME` via symlinks. For example, `common/bash/.bashrc` symlinks to `~/.bashrc`. The `--no-folding` flag is used to avoid replacing existing directories with symlinks.

### Secrets: Hybrid Encryption with age

Secrets are encrypted with **both** a passphrase and an age recipient key using `age -p -R recipients.txt`. Either method can decrypt:

- **Fresh machine (no keys):** passphrase prompt — enables `curl | bash` bootstrap
- **Established machine:** age identity at `~/.age/keys.txt` — no prompts needed

The decrypt script (`scripts/decrypt.sh`) auto-detects which method to use. Target locations are mapped by subdirectory: `secrets/ssh/*` → `~/.ssh/`, `secrets/tokens/*` → `~/.config/tokens/`.

### New Machine Bootstrap

```bash
curl -fsSL https://raw.githubusercontent.com/USER/dots/main/scripts/setup.sh | bash
```

This installs age + GNU Stow, clones the repo to `~/.dots`, prompts for passphrase to decrypt secrets, and stows all configs. Platform is auto-detected via `uname -s`.

## Commands

```bash
./scripts/setup.sh                              # Full bootstrap (or curl it)
./scripts/setup.sh --restow                     # Re-stow all packages (after git pull)
./scripts/setup.sh --adopt                      # Adopt existing files into repo, then stow
./scripts/setup.sh --unstow                     # Remove all managed symlinks
./scripts/encrypt.sh <plaintext> <output.age>   # Hybrid-encrypt a file
./scripts/decrypt.sh                            # Decrypt all secrets
```

## Critical Rules

- **Never commit unencrypted secrets.** `.gitignore` blocks common patterns but always verify with `git status` before committing.
- **The age private key (`keys.txt`) must never be in this repo.**
- **File permissions:** SSH keys `chmod 600`, `.ssh/` dir `chmod 700`. `decrypt.sh` enforces this automatically.
- **Platform-specific configs go in platform dirs**, not as conditionals in common configs. Keep `common/` portable across macOS, Linux, and BSD.
- **Stow package layout must mirror `$HOME`.** E.g., to deploy `~/.bashrc`, the file goes at `common/bash/.bashrc`.
- **Update `DOTS_REPO_URL` in `setup.sh`** before publishing (replace `USER` with actual GitHub username).
- **Run `shellcheck` before committing any bash files.** A pre-commit hook (`.githooks/pre-commit`) enforces this automatically. Fix all errors and warnings; SC1090/SC1091 (non-constant source) are globally excluded. If a warning seems like a false positive, ask the user before suppressing it with a directive.
