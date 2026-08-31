# packages(1)

[manpage](man/packages.1) · companion shim to [dots-setup](dots-setup.md)
and [runtimes](runtimes.md)

## Name

`packages` — resolve and install the `~/.packages` wishlist across package
managers

## Synopsis

```
packages <command> [args]
```

## Description

`packages` maintains a per-machine **package wishlist** at `~/.packages`.
[dots-setup](dots-setup.md) seeds the file from
`templates/packages/.packages` on first install — a minimal baseline of the
tools the bootstrap guarantees — and never touches it again. From then on
the file is owned by the user: it records both the baseline and every
package deliberately added since, and `packages update` resolves each
entry against whatever package managers are actually installed on the
machine (apt, apk, dnf, pacman, pkg, brew) and installs what is missing.

The point is a single plain-text source of truth per machine: a fresh
machine converges from a list of names with no per-platform bookkeeping,
and the file doubles as an (unordered) history of what the machine has
installed and what its bootstrap guarantees. Removals are possible but
**journaled**: every package this shim installs is recorded in
`~/.local/state/packages/installed`, and only journaled packages are ever
uninstalled (by `packages refresh`, prompted per name). A package you
installed by hand is never touched — deleting its line only stops
*managing* it.

Deployed as `~/bin/packages` by dots-setup from `common/bin/bin/packages`;
also reachable as `dots packages <cmd>` (see [dots](dots.md)) and
`just packages <cmd>`.

## Commands

| Command | Meaning |
| --- | --- |
| `status` | Report each entry's state (provided / installed / resolved / not here / no match). Read-only — no installs, no prompts, no writes. |
| `install` | Resolve + install every wishlist entry that is not installed yet. No index refresh, no cleanup. |
| `update` | `install`, plus refresh the backend indexes first (`apt-get update`, `brew update`, …) and clean them after (`brew cleanup`, `apt-get autoremove`, …). The full convergence. |
| `refresh` | Apply wishlist edits in both directions: uninstall journaled installs that are no longer in the file (prompted y/n), then `install`. Hand-installed packages are never touched. |
| `add <name> [@mgr:pkg ...]` | Append an entry to `~/.packages` and install it; an entry already in the wishlist is reported, not re-added. |
| `init [template]` | Seed `~/.packages` from the repo template; refuses to overwrite. |
| `-h`, `--help` | Usage. |

## Wishlist format

One entry per line; blank lines and `#` comments are ignored (inline
trailing comments work too). Tokens after the first are per-backend pins:

```
htop                  # exact name on every backend, resolution order
postgresql18          # Debian apt has postgresql-18; brew has postgresql@18
build-essential @apt:build-essential @apk:build-base @dnf:gcc-c++,make @brew:-
debian-desktop @apt:task-gnome-desktop @apk:- @dnf:- @pacman:- @brew:-
```

Resolution order is `apt apk dnf pacman pkg brew` (brew alone on macOS;
Linuxbrew is consulted after the system package manager). The first backend
offering the exact name — or a pinned alternative (`@apt:build-essential`)
— wins. `@mgr:-` excludes a backend for that entry (a name that exists
nowhere but Debian should not be offered on a Mac, and a
macOS-irrelevant entry should not nag there). Entries whose pins exclude
every backend on the current machine are reported as "not here", never as a
failure.

### Provided baseline

The names `age bash bc coreutils curl direnv fnm git just jq locales less
sdkman shellcheck stow tmux uv xz-utils` are what dots-setup guarantees.
Wishlist entries with those names are **silently skipped** — never
resolved, never installed twice — but should stay in the file: they are the
template's record of what the bootstrap provides on any machine.

### Resolution and the cache

An entry matching no backend exactly is resolved **once, interactively**:
search candidates across the permitted backends are listed (bounded), and
the operator picks a number to install, `s` to record a permanent local
skip, or `[Enter]` to leave unresolved. The decision is cached at
`~/.local/state/packages/resolutions` (one line per name:
`name⇥backend⇥package`, `-` backend = permanent skip) and applied silently
thereafter — a machine is asked at most once per name. Exact matches are
deterministic and are not cached. Prompts read stdin, falling back to
`/dev/tty`, so an update under `curl | bash` still prompts.

### The install journal

`install`, `update`, `add` and `refresh` append every package **this shim**
installs to `~/.local/state/packages/installed` (one line per name:
`name⇥backend⇥package`). [refresh](#-commands) is the only uninstall path
and reads only this file: when a journaled package is no longer an entry in
`~/.packages`, refresh offers to remove it (y per package, anything else
keeps it; with no terminal everything is kept and listed). Delete a journal
line and the machine forgets the package was ever shim-managed.

## Environment

| Variable | Effect | Default |
| --- | --- | --- |
| `DOTS_DIR` | Where to find the wishlist template | `~/.dots` |
| `PACKAGES_FILE` | Wishlist path override | `~/.packages` |
| `PACKAGES_STATE_DIR` | State directory (resolution cache + install journal) | `~/.local/state/packages` |

## Exit status

| Code | Meaning |
| --- | --- |
| 0 | Converged, or status completed. |
| 1 | Usage error, or a malformed wishlist entry (two names, bad pin). |
| 2 | Finished with one or more entries unresolved, install failures, or removal failures. |

## Files

- `~/.packages` — the wishlist (seeded by [dots-setup](dots-setup.md)).
- `~/.local/state/packages/resolutions` — cached resolutions / skip records;
  delete the file to forget every stored choice.
- `~/.local/state/packages/installed` — the install journal; the only thing
  `refresh` uninstalls from.
- `~/bin/packages` — the deployed shim (`common/bin/bin/packages`).
- `~/.dots/templates/packages/.packages` — the template (`init` falls back to
  the one in the checkout the shim was deployed from).

## Intended usage

This is the tool that turns a blessed machine into *your* machine. The
workflow it composes:

1. `setup.sh` installs the baseline (and, see [dots-setup](dots-setup.md),
   seeds `~/.packages` with exactly that baseline).
2. In day-to-day use, when you install a package you would want on the next
   machine too, record it: `echo htop >> ~/.packages && packages update`
   (or just `packages add htop`).
3. When you decide a machine no longer needs something, delete the line and
   run `packages refresh`: it uninstalls the packages this shim installed
   whose entries are gone (each prompted), then installs any new ones. If
   the package was installed by hand it stays, but it is no longer managed.
4. Every other machine catches up through `git pull`-like convergence: the
   wishlist lives in `$HOME` (not the repo — keep the repo's
   [template](man/dots-setup.1) minimal so a new machine stays lean), the
   resolutions and journal live in `~/.local/state`.

Comment out big or machine-specific entries (a desktop task, a database
server) so a fresh install stays minimal; uncomment when a machine needs
them. Use pins to spell out per-platform names up front for packages with
distro-specific naming (`build-essential`, `postgresql18`), so `update`
never has to ask.

It complements [runtimes](runtimes.md): `packages` manages system packages
from `~/.packages`; `runtimes` manages per-project language runtimes from a
project `.runtimesrc` (python via uv, node via fnm, java via sdkman).

## Examples

Grow the wishlist and converge:

```bash
echo -en "htop\nbuild-essential\nhttpie\nmariadb10\n" >> ~/.packages
packages update
```

Quick catch-up without the index refresh (the cheap everyday verb):

```bash
packages install
```

Inspect without installing anything:

```bash
packages status
```

Apply a wishlist pruning (each removal prompted):

```bash
vi ~/.packages
packages refresh
```

Add — and immediately install — one entry:

```bash
packages add httpie
```

Pin a per-backend name so no machine ever asks:

```bash
packages add postgresql18 @brew:postgresql@18
```

Related: [dots-setup](dots-setup.md) (seeds the wishlist), ·
[runtimes](runtimes.md) · [dots-verify](dots-verify.md)