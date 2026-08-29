# dots

Dotfiles for Bash configurations across macOS, Linux, and BSD. Managed with [GNU Stow](https://www.gnu.org/software/stow/) and encrypted secrets via [age](https://github.com/FiloSottile/age).

## Quick Start

**New machine (one-liner):**

```bash
curl -fsSL https://raw.githubusercontent.com/tharant/dots/main/scripts/setup.sh | bash
```

**After cloning:**

```bash
./scripts/setup.sh
```

This installs dependencies (age, GNU Stow), clones the repo to `~/.dots`, decrypts secrets (prompts for passphrase), and symlinks configs into `$HOME`. Platform is auto-detected via `uname -s`.

## Layout

```
dots/
├── common/       # Cross-platform configs (Stow packages)
│   ├── bash/     # .bashrc, .bash_profile, .bash_aliases
│   ├── git/      # .gitconfig, .gitignore_global
│   └── ssh/      # SSH config (public parts)
├── macos/        # macOS-specific overrides
├── linux/        # Linux-specific overrides
├── bsd/          # BSD-specific overrides
├── secrets/      # Encrypted files (dual artifacts: *.age + *.phrase.age)
└── scripts/      # setup.sh, encrypt.sh, decrypt.sh
```

Each subdirectory inside `common/` and the platform dirs is a Stow package. Files mirror `$HOME` — e.g., `common/bash/.bashrc` becomes `~/.bashrc`.

## Usage

```bash
./scripts/setup.sh                            # Full bootstrap
./scripts/setup.sh --restow                   # Re-stow packages (after git pull)
./scripts/setup.sh --adopt                    # Adopt existing files into repo
./scripts/setup.sh --unstow                   # Remove all managed symlinks
./scripts/encrypt.sh <plaintext> <output.age> # Encrypt a file
./scripts/decrypt.sh                          # Decrypt all secrets
```

## Secrets

Secrets are stored as two age artifacts per secret — `X.age` (age recipient key) and `X.phrase.age` (passphrase fallback) — since no age CLI can combine both in one file. Either can decrypt:

- **Fresh machine (no age key):** passphrase prompt
- **Established machine:** age identity at `~/.age/keys.txt` — no prompts

Encrypted files live in `secrets/` and map to home by subdirectory: `secrets/ssh/*` → `~/.ssh/`, `secrets/tokens/*` → `~/.config/tokens/`.

## Adding Platform-Specific Configs

Platform overrides go in `macos/`, `linux/`, or `bsd/` — not as conditionals in `common/`. Each platform dir uses the same Stow package structure mirroring `$HOME`.
