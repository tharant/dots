# dots

Dotfiles for bash across macOS, Debian flavors, Alpine, WSL2, and (occasionally) BSD — deployed identically everywhere. Managed with [GNU Stow](https://www.gnu.org/software/stow/), encrypted secrets via [age](https://github.com/FiloSottile/age), and a bootstrap that auto-installs everything it needs.

## Quick Start

**New machine (one-liner):**

```bash
curl -fsSL https://raw.githubusercontent.com/tharant/dots/main/scripts/setup.sh | bash
```

**After cloning:**

```bash
./scripts/setup.sh
```

This installs all dependencies (git, bash 5, age, GNU Stow, just, tmux, shellcheck, core tools), clones the repo to `~/.dots`, decrypts secrets (age key if present, else passphrase prompt — prompts attach to the real TTY even under `curl | bash`), and symlinks configs into `$HOME`.

**Alpine first step** (busybox-only base — the one-liner needs bash, git, and curl first):

```sh
apk add bash git curl && curl -fsSL https://raw.githubusercontent.com/tharant/dots/main/scripts/setup.sh | bash
```

## Supported Targets

| Platform | Stow layers applied | Notes |
|---|---|---|
| macOS Sequoia+ | `common/` + `macos/` | brew bash 5 registered in `/etc/shells` by setup.sh |
| Debian bookworm/trixie | `common/` + `linux/` | `just` on bookworm comes from a GitHub release binary; node 22 from upstream tarball if apt's is older |
| Alpine 3.22+ | `common/` + `linux/` + `alpine/` | setup.sh ensures the `community` repo, `bash`, `shadow`, `ncurses-terminfo` |
| WSL2 (Debian/Alpine) | as above + `wsl/` | Windows PATH trimmed, `clip.exe`-aware clipboard |
| FreeBSD | `common/` + `bsd/` | best effort, not a priority |

Detection: `uname -s` (platform), `/etc/os-release` (distro), `/proc/version` + `$WSL_DISTRO_NAME` (WSL), `uname -r` (OrbStack, informational).

## Layout

```
dots/
├── common/            # Cross-platform configs (Stow packages)
│   ├── bash/          # .bashrc, .bash_aliases, .bash_functions, ...
│   ├── bin/           # ~/bin shims: loadavg, tmux-copy (capability-detecting)
│   ├── git/           # .gitconfig, .gitignore_global
│   ├── nvim/          # .config/nvim/init.lua (coc.nvim, clipboard-guarded)
│   ├── ssh/           # SSH config (public parts)
│   ├── tmux/          # .tmux.conf (single, identical on every platform)
│   ├── trueline/      # .local/trueline/ (patched trueline.sh + .trueline.conf)
│   └── vim/           # .vimrc, .vim/ (vim-plug; plug.vim vendored)
├── macos/             # macOS overrides → .bashrc.platform.d/macos.sh
├── linux/             # Linux overrides  → .bashrc.platform.d/linux.sh
├── alpine/            # Alpine overrides → .bashrc.platform.d/alpine.sh
├── wsl/               # WSL2 overrides   → .bashrc.platform.d/wsl.sh
├── bsd/               # BSD overrides    → .bashrc.platform.d/bsd.sh
├── secrets/           # Encrypted files (dual artifacts: *.age + *.phrase.age)
└── scripts/           # setup.sh, encrypt.sh, decrypt.sh, verify.sh
```

Each subdirectory inside `common/` and the platform dirs is a Stow package. Files mirror `$HOME` — e.g., `common/bash/.bashrc` becomes `~/.bashrc`.

### The platform layer

Platform overrides must **not** be conditionals in `common/`. Instead, each platform package ships a `bash/.bashrc.platform.d/<name>.sh` file, and `.bashrc` sources every file in `~/.bashrc.platform.d/`. Layers compose (an Alpine WSL2 distro gets both `alpine.sh` and `wsl.sh`), and non-login interactive shells get the same environment as login shells.

## Usage

```bash
./scripts/setup.sh                            # Full bootstrap
./scripts/setup.sh --restow                   # Re-stow packages (after git pull)
./scripts/setup.sh --adopt                    # Adopt existing files into repo
./scripts/setup.sh --unstow                   # Remove all managed symlinks
./scripts/encrypt.sh <plaintext> <output.age> # Encrypt a file
./scripts/decrypt.sh                          # Decrypt all secrets
./scripts/verify.sh                           # Check symlink + permissions health
```

The same operations are available through `just` (`just setup`, `just restow`, `just verify`, `just encrypt <file>`, `just lint`, …) — run `just` for the full list.

## Documentation

Each script has a full manual — rendered (roff) and source (markdown), kept in
agreement with the code they document:

| Page | Script |
|---|---|
| [dots-setup(1)](docs/dots-setup.md) | `scripts/setup.sh` — bootstrap, restow, adopt, unstow |
| [dots-encrypt(1)](docs/dots-encrypt.md) | `scripts/encrypt.sh` — write the dual age artifacts |
| [dots-decrypt(1)](docs/dots-decrypt.md) | `scripts/decrypt.sh` — materialize secrets locally |
| [dots-verify(1)](docs/dots-verify.md) | `scripts/verify.sh` — symlink + permissions health check |

Install them as real manpages (see [docs/man/Makefile](docs/man/Makefile)):

```bash
just man-install     # symlinks docs/man/*.1 into ~/.local/share/man/man1
just man-check       # mandoc -T lint on all pages
```

Other reference docs live alongside: [bash startup order](docs/bash-startup-order.md), [stow adopt workflow](docs/stow-adopt-workflow.md).

## Secrets

Each secret is stored as two age artifacts encrypting the same plaintext — `X.age` (age recipient key, from `secrets/recipients.txt`) and `X.phrase.age` (passphrase fallback) — since no age CLI can combine both in one file. Either can decrypt:

- **Fresh machine (no age key):** passphrase prompt
- **Established machine:** age identity at `~/.age/keys.txt` — no prompts

`secrets/recipients.txt` holds public keys only (safe to commit). Encrypted files live in `secrets/` and map to home by subdirectory: `secrets/ssh/*` → `~/.ssh/`, `secrets/tokens/*` → `~/.config/tokens/`. Decryption enforces `umask 077` and `0600`/`0700` permissions on all targets.

## Requirements for interactive use

- **bash ≥ 4.3** (installed by setup.sh; macOS stock bash 3.2 is detected and skipped for the trueline prompt, not broken)
- **Node ≥ 22.15 + Neovim ≥ 0.8 or Vim ≥ 9.0.0438** for coc.nvim; see `common/vim/.vim/MYDOTS.md` (on Debian bookworm, install nvim from upstream)
- A **Nerd Font** on the *terminal client* machine (for the tmux status and trueline glyphs); headless/SSH hosts need nothing
- `gh` (`gh auth login`) for the git credential helper on any target

## Adding Platform-Specific Configs

Platform overrides go in `macos/`, `linux/`, `alpine/`, `wsl/`, or `bsd/` — not as conditionals in `common/` (the sanctioned exceptions are the `~/.bashrc.platform.d` hook in `.bashrc` and `command -v` guards for genuinely optional tools). Each platform dir uses the same Stow package structure mirroring `$HOME`.

## Blessing a new test VM (WSL2 / OrbStack)

1. Create the machine (`orb create debian:trixie <name>` / `wsl --install -d Debian`), or for Alpine install bash/git/curl first.
2. Copy your age identity once: `~/.age/keys.txt` → `~/.age/keys.txt` on the VM (0600).
3. Run the Quick Start block. tmux, prompt, aliases, and the secrets pipeline come up identically to macOS.