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

1. **Never duplicate code between `.bash_profile` and `.bashrc`.** Source one from the other.
2. **`export` statements go in `.bash_profile`** — set once per login session.
3. **Aliases, functions, prompt go in `.bashrc`** — needed in every interactive shell.
4. **Platform-specific configs go in platform dirs** (`macos/bash/`, `linux/bash/`, `bsd/bash/`), not as `if/else` blocks in common configs.
5. **Guard `.bashrc` with `[[ $- == *i* ]]`** to skip expensive operations when sourced in non-interactive contexts.

## How This Maps to the Repo

```
common/bash/.bash_profile   →  ~/.bash_profile   (symlink via Stow)
common/bash/.bashrc          →  ~/.bashrc
common/bash/.bash_aliases    →  ~/.bash_aliases
common/bash/.bash_logout     →  ~/.bash_logout
macos/bash/.bashrc_local     →  ~/.bashrc_local   (platform overrides, sourced from .bashrc)
linux/bash/.bashrc_local     →  ~/.bashrc_local
```
