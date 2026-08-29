# Bash Startup File Loading Order

## How Bash Decides Which Files to Read

Bash loads different config files depending on the shell type:

| Shell Type | How You Get It | Files Read (in order) |
|---|---|---|
| **Interactive login** | SSH, `bash -l`, macOS Terminal/iTerm2 tabs | `/etc/profile` then first found of `~/.bash_profile` / `~/.bash_login` / `~/.profile`; on exit: `~/.bash_logout` |
| **Interactive non-login** | New terminal on Linux, running `bash` | `/etc/bash.bashrc` then `~/.bashrc` |
| **Non-interactive** | Scripts (`bash script.sh`) | Only `$BASH_ENV` if set |
| **Remote (SSH command)** | `ssh host 'command'` | `~/.bashrc` (SSH special case) |

### macOS Gotcha

Terminal.app and iTerm2 open **login shells** for every new tab/window. This is different from Linux, where new terminal windows open non-login shells. The practical effect: on macOS, `~/.bash_profile` runs on every tab, while `~/.bashrc` only runs if `.bash_profile` sources it.

### Login vs Non-Login: The Key Distinction

```
Login shell:       /etc/profile → ~/.bash_profile → (on exit) ~/.bash_logout
Non-login shell:   /etc/bash.bashrc → ~/.bashrc
```

Bash reads `.bash_profile` **or** `.bashrc` — never both automatically. This is why `.bash_profile` must explicitly source `.bashrc` if you want the same config in both shell types.

## Our Repo's Convention

### `~/.bash_profile` — Login shell entry point

Minimal file. Sources `.bashrc` and sets login-only environment variables:

```bash
# Source .bashrc for interactive config
[[ -f ~/.bashrc ]] && source ~/.bashrc

# Login-only env vars (set once per session)
export EDITOR="vim"
```

### `~/.bashrc` — Main interactive config

All interactive shell setup lives here: prompt, PATH additions, functions, sourcing `.bash_aliases`.

```bash
# Guard: skip for non-interactive shells
[[ $- == *i* ]] || return

# ... prompt, PATH, functions ...

# Source aliases
[[ -f ~/.bash_aliases ]] && source ~/.bash_aliases
```

### `~/.bash_aliases` — Alias definitions

Sourced from `.bashrc`. Keeps aliases in a separate file for readability.

### `~/.bash_logout` — Login shell cleanup

Runs when a login shell exits. Optional; used for cleanup tasks like clearing temp files.

## Rules to Prevent Conflicts

1. **Never duplicate code between `.bash_profile` and `.bashrc`.** Source one from the other (the platform `.bash_profile` files are 5-line `source ~/.bashrc` shims).
2. **`export` statements go in the platform `.bashrc.platform.d/<name>.sh` files** — they load in every interactive shell, login or not, so exports set there are always present.
3. **Aliases, functions, prompt go in `.bashrc`** (and `common/bash/.bash_*`) — needed in every interactive shell.
4. **Platform-specific configs go in platform dirs** (`macos/bash/`, `linux/bash/`, `alpine/bash/`, `wsl/bash/`, `bsd/bash/`), each shipping `bash/.bashrc.platform.d/<name>.sh` — not as `if/else` blocks in common configs.
5. **Guard `.bashrc` with `[[ $- == *i* ]]`** to skip expensive operations when sourced in non-interactive contexts. Platform files load right after this guard.

## How This Maps to the Repo

```
common/bash/.bash_profile          →  ~/.bash_profile   (symlink via Stow)
common/bash/.bashrc                →  ~/.bashrc
common/bash/.bash_aliases           →  ~/.bash_aliases
common/bash/.bash_logout            →  ~/.bash_logout
macos/bash/.bashrc.platform.d/macos.sh  →  ~/.bashrc.platform.d/macos.sh
linux/bash/.bashrc.platform.d/linux.sh  →  ~/.bashrc.platform.d/linux.sh
alpine/bash/.bashrc.platform.d/alpine.sh →  ~/.bashrc.platform.d/alpine.sh
wsl/bash/.bashrc.platform.d/wsl.sh      →  ~/.bashrc.platform.d/wsl.sh
bsd/bash/.bashrc.platform.d/bsd.sh      →  ~/.bashrc.platform.d/bsd.sh
```

`.bashrc` sources every file in `~/.bashrc.platform.d/` (alphabetical order), so layers compose — a WSL2-Alpine distro gets both `alpine.sh` and `wsl.sh`. setup.sh decides which platform packages to stow: `common` + `macos|linux|bsd`, plus `alpine` when `/etc/os-release` says Alpine, plus `wsl` when WSL is detected.
