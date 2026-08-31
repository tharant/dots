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
│   ├── bin/           # ~/bin shims: loadavg, tmux-copy, runtimes, packages (capability-detecting)
│   ├── direnv/        # .config/direnv (direnvrc use_* helpers, direnv.toml), ~/.envrc root + ~/.runtimesrc defaults
│   ├── git/           # .gitconfig, .gitignore_global
│   ├── nvim/          # .config/nvim/init.lua (coc.nvim, clipboard-guarded)
│   ├── ssh/           # SSH config (public parts)
│   ├── sbt/           # .sbt/repositories (config leaf only — caches stay in $HOME)
│   ├── ivy2/          # .ivy2/ skeleton (config leaf only — caches stay in $HOME)
│   ├── tmux/          # .tmux.conf (single, identical on every platform)
│   ├── tmux-powerline/ # .config/tmux-powerline/: config.sh + themes/dots.sh
│   │                  #   (plugin itself cloned by setup.sh, pinned)
│   ├── trueline/      # .local/trueline/ (patched trueline.sh + .trueline.conf)
│   └── vim/           # .vimrc, .vim/ (vim-plug; plug.vim vendored)
├── macos/             # macOS overrides → .bashrc.platform.d/macos.sh
├── linux/             # Linux overrides  → .bashrc.platform.d/linux.sh
├── alpine/            # Alpine overrides → .bashrc.platform.d/alpine.sh
├── wsl/               # WSL2 overrides   → .bashrc.platform.d/wsl.sh
├── bsd/               # BSD overrides    → .bashrc.platform.d/bsd.sh
├── secrets/           # Encrypted files (dual artifacts: *.age + *.phrase.age)
├── scripts/           # setup.sh, encrypt.sh, decrypt.sh, verify.sh
└── templates/         # use_template scaffolding trees + manifests + the ~/.packages
                       # wishlist template (repo root, not stowed)
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
./scripts/verify.sh                           # Deployment health check (tools, symlinks, permissions, secrets, direnv)
```

The same operations are available through `just` (`just setup`, `just restow`, `just verify`, `just encrypt <file>`, `just lint`, …) — run `just` for the full list. On any blessed machine, [dots(1)](docs/dots.md) (`~/bin/dots`) is the single machine-side CLI for the same operations plus two composed ones: `dots sync` (pull → restow → verify) and `dots commit` (survey, encrypt/adopt/stage with a plaintext-secret gate, review, commit — never pushes).

### Per-directory environments + managed runtimes

[direnv](https://direnv.net/) applies folder-level env vars on `cd`; `.envrc`s chain up the tree by default (opt out with `no_source_up`; nearest wins, ancestor values persist). The tree-root `~/.envrc` applies stowed LTS defaults (`python 3.12`, `node 24`, `java 25`), so every directory gets runtimes with no project ceremony. Projects ship their own `.envrc` + `.runtimesrc` to pin different runtimes; the first `cd` after `direnv allow` installs detached through the [`runtimes`](docs/runtimes.md) shim (python via uv, node via fnm, java via sdkman) and the next prompt activates them — including a project-local `.venv`. Authoring is documented in the [direnv + runtimes guide](docs/direnv-runtimes.md).

## Documentation

Each script has a full manual — rendered (roff) and source (markdown), kept in
agreement with the code they document:

| Page | Script |
|---|---|
| [dots-setup(1)](docs/dots-setup.md) | `scripts/setup.sh` — bootstrap, restow, adopt, unstow |
| [dots-encrypt(1)](docs/dots-encrypt.md) | `scripts/encrypt.sh` — write the dual age artifacts |
| [dots-decrypt(1)](docs/dots-decrypt.md) | `scripts/decrypt.sh` — materialize secrets locally |
| [dots-verify(1)](docs/dots-verify.md) | `scripts/verify.sh` — deployment health check: tools, symlinks, permissions, secrets, direnv + runtimes |
| [loadavg(1)](docs/loadavg.md) | `~/bin/loadavg` — status-bar load shim (`common/bin`) |
| [tmux-copy(1)](docs/tmux-copy.md) | `~/bin/tmux-copy` — clipboard ladder + OSC 52 (`common/bin`) |
| [runtimes(1)](docs/runtimes.md) | `~/bin/runtimes` — managed runtimes CLI: uv/fnm/sdkman (`common/bin`) |
| [packages(1)](docs/packages.md) | `~/bin/packages` — package wishlist CLI: resolve + install `~/.packages` across apt/apk/dnf/pacman/pkg/brew (`common/bin`) |
| [dots(1)](docs/dots.md) | `~/bin/dots` — repo orchestration CLI: delegates every op, plus composed `sync` and gated interactive `commit` (never pushes) (`common/bin`) |

Install them as real manpages (see [docs/man/Makefile](docs/man/Makefile)):

```bash
just man-install     # symlinks docs/man/*.1 into ~/.local/share/man/man1
just man-check       # mandoc -T lint on all pages
```

Other reference docs live alongside: [bash startup order](docs/bash-startup-order.md), [stow adopt workflow](docs/stow-adopt-workflow.md), [mixed config+cache dotdirs (sbt, ivy2)](docs/stow-packages.md), [direnv + runtimes guide](docs/direnv-runtimes.md).

## Secrets

Each secret is stored as two age artifacts encrypting the same plaintext — `X.age` (age recipient key, from `secrets/recipients.txt`) and `X.phrase.age` (passphrase fallback) — since no age CLI can combine both in one file. Either can decrypt:

- **Fresh machine (no age key):** passphrase prompt
- **Established machine:** age identity at `~/.age/keys.txt` — no prompts

`secrets/recipients.txt` holds public keys only (safe to commit). Encrypted files live in `secrets/` and map to home by subdirectory: `secrets/ssh/*` → `~/.ssh/`, `secrets/tokens/*` → `~/.config/tokens/`. Decryption enforces `umask 077` and `0600`/`0700` permissions on all targets.

## Requirements for interactive use

- **bash ≥ 4.3** (installed by setup.sh; macOS stock bash 3.2 is detected and skipped for the trueline prompt, not broken)
- **Node ≥ 22.15 + Neovim ≥ 0.8 or Vim ≥ 9.0.0438** for coc.nvim; see `common/vim/.vim/MYDOTS.md` (on Debian bookworm, install nvim from upstream). Without node, vim skips coc and starts clean — node arrives via `runtimes install node 22` (fnm)
- A **Nerd Font** on the *terminal client* machine (for the tmux status and trueline glyphs); headless/SSH hosts need nothing. The tmux-powerline config declares it via `TMUX_POWERLINE_PATCHED_FONT_IN_USE=true`.
- `gh` (`gh auth login`) for the git credential helper on any target

## Adding Platform-Specific Configs

Platform overrides go in `macos/`, `linux/`, `alpine/`, `wsl/`, or `bsd/` — not as conditionals in `common/` (the sanctioned exceptions are the `~/.bashrc.platform.d` hook in `.bashrc` and `command -v` guards for genuinely optional tools). Each platform dir uses the same Stow package structure mirroring `$HOME`.

## Blessing a new test VM (WSL2 / OrbStack)

1. Create the machine (`orb create debian:trixie <name>` / `wsl --install -d Debian`), or for Alpine install bash/git/curl first.
2. Copy your age identity once: `~/.age/keys.txt` → `~/.age/keys.txt` on the VM (0600).
3. Run the Quick Start block. tmux, prompt, aliases, and the secrets pipeline come up identically to macOS.