# dots-setup(1)

## Name

**dots-setup** — bootstrap and manage the dots dotfiles deployment.

## Synopsis

```
dots-setup [--restow|--adopt|--unstow|--force|--verify|-h|--help]
dots-setup            # no args: full bootstrap (install deps, clone, decrypt, stow)
```

## Description

`setup.sh` is the entry point for every machine in the [dots](../README.md)
fleet. With no arguments it runs the full pipeline, in this order:

1. Install core packages (platform-specific, see below).
2. Run preflight checks (git present, curl present, bash under Alpine).
3. Clone the repo to `~/.dots` — or `git pull --ff-only` an existing clone
   (`--autostash` if the working tree is dirty; a failed pull keeps the
   current checkout). Either way it sets `core.hooksPath .githooks` so the
   shellcheck pre-commit hook stays active.
4. Decrypt secrets by invoking `scripts/decrypt.sh` (see
   [dots-decrypt](dots-decrypt.md)), passing the current `FORCE` value.
5. Stow every package into `$HOME`.

The script is written to be piped straight from `curl` into `bash` on a fresh
machine. When stdin is a pipe it reattaches stdin to `/dev/tty` (guarded by a
test open, so CI containers without a controlling terminal do not break)
because the age passphrase prompt and `chsh` need a real TTY. On a **bare
Alpine** box, bash/git/curl must exist first:

```
apk add bash git curl
./scripts/setup.sh       # or: wget -qO- <setup.sh url> | bash
```

**Privilege policy.** Individual privileged commands run as root when the
script already runs as root, otherwise through `sudo` if available, then
`doas`. If neither exists (and it is not root), the script warns up front.
The full and `--force` runs then abort right there ("Root privileges are
required but neither sudo nor doas is available") before any packages are
installed, so the package install, locale generation and `/etc/shells`
steps never run in those modes. `--restow`, `--adopt` and `--unstow` do no
`require_priv` check of their own: they proceed after the warning, and the
first step that needs root (installing `stow` when it is missing) fails,
reported by the ERR trap. Homebrew is never run with the privilege prefix.

**Detection.** `uname -s` maps Darwin→`macos`, Linux→`linux`, and anything
matching `*BSD`→`bsd`; anything else is fatal ("Unsupported platform"). On
Linux the distro ID comes from `/etc/os-release`. WSL is detected from
`WSL_DISTRO_NAME` or the kernel string in `/proc/version`; an OrbStack kernel
string on macOS is reported informationally only.

**Package managers.** Detection order: `brew`, `apt-get`, `dnf`, `pacman`,
`apk`, `pkg`. None found is fatal. `apt-get update` runs once, before the
first install. Batch installs are retried package by package when the batch
fails, so one missing or renamed package does not sink the whole set;
individual failures are recorded as non-fatal.

Per-platform behaviour:

- **macos** — installs Homebrew itself when `brew` is missing (official
  installer, `NONINTERACTIVE=1`, run as the invoking user); installs `bash age
  stow just tmux shellcheck git coreutils`, adds Homebrew's bash to
  `/etc/shells`, and makes it the login shell with `chsh` (both non-fatal if
  they fail). The prefix is derived from the `brew` binary path, falling back
  to `/opt/homebrew` (arm64) or `/usr/local`.
- **Alpine** — ensures the `community` repository is enabled in
  `/etc/apk/repositories` (derived from the `main` line and appended; if the
  file or the mirror line is missing, the failure is recorded and the step is
  skipped rather than fatal), refreshes apk indexes, then installs `bash
  coreutils findutils util-linux git age stow just tmux shellcheck shadow
  bash-completion ncurses-terminfo curl ca-certificates` — plus `sudo` when
  neither sudo nor doas is present.
- **Debian (apt-get)** — installs `git age stow tmux shellcheck bash coreutils
  less locales ca-certificates curl wl-clipboard xz-utils`, then extras:
  Node.js 22 from apt when the apt candidate is ≥ 22, otherwise the official
  `v22.23.2` tarball extracted into `/usr/local/lib/nodejs` (which the script
  creates with `mkdir -p` if missing) with `node`, `npm`, `npx` symlinked into
  `/usr/local/bin`. Then: `just` from apt when available,
  otherwise the upstream musl binary (`1.58.0`) into `/usr/local/bin`; and
  `en_US.UTF-8` generation via `locale-gen` (skipped with a recorded failure
  if `locale-gen` or `/etc/locale.gen` is missing).
- **Other Linux** (dnf/pacman/pkg) — `git age stow just tmux shellcheck bash
  coreutils curl ca-certificates`.
- **FreeBSD** — `git age stow just tmux shellcheck bash coreutils curl
  ca_root_nss` via `pkg`.

Post-install: `git curl just tmux shellcheck` are each verified (a missing
tool is a recorded non-fatal failure), a missing `stow` is **fatal**, and a
missing `age` falls back to the static release `v1.3.1` installed to
`~/.local/bin` (mode 0755), warning if that directory is not already on
`PATH`.

Stowing runs `stow -d <dir> -t $HOME --no-folding` over every package in
`common/`, then the platform package directory (`macos/`, `linux/`, `bsd/`),
then the `alpine/` layer on Alpine and the `wsl/` layer under WSL. Layers
whose directory does not exist are skipped silently. A package that fails to
stow is recorded as a failure and stowing continues with the remaining
packages.

## Options

| Flag | Effect |
| --- | --- |
| *(none)* | Full bootstrap: install packages, clone/pull, decrypt secrets, stow. |
| `--restow` | Re-stow all packages (`--restow`). Use after a `git pull`. Requires the repo to be cloned; installs `stow` if missing, otherwise installs nothing and does not decrypt. |
| `--adopt` | Adopt existing `$HOME` files into the repo in a single stow run (`--adopt`; there is no separate re-stow pass). Requires the repo to be cloned; installs `stow` if missing, otherwise installs nothing and does not decrypt. See the [stow adopt workflow](stow-adopt-workflow.md). |
| `--unstow` | Remove all managed symlinks (`--no-folding --delete`). Requires the repo to be cloned; installs `stow` first if missing. Success message: "All symlinks removed." |
| `--force` | Full pipeline with `FORCE=true` exported to `dots-decrypt`, so every secret is re-decrypted even when the target is newer than its artifact, then all packages re-stowed. There are no other freshness checks in this script to skip. |
| `--verify` | Run `scripts/verify.sh` against the current deployment and nothing else. Requires the repo. Run directly when executable, otherwise via `bash` with a warning. |
| `-h`, `--help` | Print usage, exit 0. |

Only the first argument is inspected. Any value other than the flags above, in
first position, is fatal: `Unknown option: <arg> (see --help)`. Arguments after
the first are never checked and are silently ignored —
`setup.sh --restow --force` runs `--restow` and discards `--force`, and
`setup.sh --verify --quiet` does the same. (`dots-encrypt` and `dots-decrypt`
document the same behaviour for their own surplus arguments.)

Note that `--restow`/`--adopt`/`--unstow` will install `stow` first if it is
missing (which may need privileges); `--verify` installs nothing. None of these
modes ever touches secrets, and only the full run and `--force` check
`require_priv` up front.

This page is authoritative for the flags. The usage text baked into
`setup.sh` itself (printed by `-h`/`--help`) is out of date: it omits
`-h`/`--help` even though the flags work and the script's error messages
point at `--help`, and it describes `--adopt` as "then re-stow" although
adoption is a single stow run.

## Environment

| Variable | Meaning | Default |
| --- | --- | --- |
| `DOTS_REPO_URL` | Repository cloned when `~/.dots/.git` does not exist. Never used to re-point an existing clone (it is pulled, not re-cloned). | `https://github.com/tharant/dots.git` |
| `DOTS_DIR` | Where the repo lives / is cloned. Read on every run to locate the clone — not only for the initial one — so it can also re-point the other modes at a checkout elsewhere. | `$HOME/.dots` |
| `FORCE` | Passed through to `dots-decrypt`; `--force` sets it to `true`. | `false` |
| `WSL_DISTRO_NAME` | Read during detection; non-empty marks the environment as WSL and enables the `wsl` stow layer. | — |
| `SHELL` | Read on macOS to decide whether `chsh` is needed for Homebrew's bash. | — |

## Exit status

- **0** — all requested steps completed and nothing was recorded in the
  failure list.
- **1** — a fatal error occurred, *or* one or more non-fatal steps failed.
  The fatal paths are: unsupported platform, no supported package manager,
  the Homebrew installer failing or setup.sh running as root (Homebrew
  refuses root), Alpine run without bash, no privileges when
  required, failed clone, GNU Stow still missing after install (or
  impossible to install in the `--restow`/`--adopt`/`--unstow` modes),
  unknown option, `verify.sh` missing — and, because the decrypt and verify
  steps are not conditional, a non-zero exit from `scripts/decrypt.sh`
  (full and `--force` runs) or from `scripts/verify.sh` (`--verify`) aborts
  the run through the ERR trap. Non-fatal failures (failed `git pull`,
  individually failed packages, missing expected tools, failed `chsh`,
  `/etc/shells` or locale generation, failed fallback downloads) are
  summarised as a WARNING list just before the exit.

The ERR trap also reports `Step failed with exit code N. Run with --help for
options.` and exits 1. A run can print plenty of WARNING lines and still exit
0 — only recorded *failures* flip the exit status.

## Files

- `~/.dots` — default repository location.
- `/etc/os-release` — Linux distro ID.
- `/proc/version` — WSL detection.
- `/etc/apk/repositories` — read, and extended with the community repo, on Alpine.
- `/etc/locale.gen` — enabled for `en_US.UTF-8` on Debian.
- `/etc/shells` — appended with Homebrew's bash on macOS.
- `~/.local/bin/age`, `~/.local/bin/age-keygen` — static age fallback (0755).
- `/usr/local/bin/just`, `/usr/local/lib/nodejs/` — static just / Node.js fallbacks (Debian).
- `scripts/decrypt.sh`, `scripts/verify.sh` — invoked for the decrypt and verify steps.
- `.githooks/` — set as `core.hooksPath` after clone or pull.

## Intended usage

`dots-setup` (this page) is the first contact with a machine: it performs the
platform, distro, package-manager and privilege detection itself, installs
toolchains, clones the repo, decrypts, and stows. The full run is the only
path that installs the whole dependency set (the `--restow`/`--adopt`/
`--unstow` modes will only install `stow` when it is missing), so those modes
assume a previous full run (or an already-installed `stow`).

Relationships to the other three siblings:

- **[dots-encrypt](dots-encrypt.md)** — the authoring counterpart: when you
  edit a secret on a working machine you re-encrypt it there, commit both
  age artifacts, and other machines pick the change up on their next
  `dots-setup` full run (or `--force`).
- **[dots-decrypt](dots-decrypt.md)** — invoked by `dots-setup` for the
  decrypt step of the full and `--force` runs; callable on its own for
  targeted re-decryption.
- **[dots-verify](dots-verify.md)** — invoked by `dots-setup --verify`;
  the full run does not call it, so verify remains opt-in on top of setup.

Reach for `dots-setup` when:

- bringing up a brand-new machine (`curl … | bash`, or `--force` when you
  also want the passphrase-driven decrypt to run again),
- refreshing a checkout after a `git pull` (`--restow`),
- reconciling files that already exist on the machine
  (`--adopt`, see the [stow adopt workflow](stow-adopt-workflow.md)),
- cleaning up (`--unstow`), or
- sanity-checking an existing deployment (`--verify`).

## Examples

Full bootstrap on a fresh machine (macOS, Linux or BSD):

```bash
curl -fsSL https://raw.githubusercontent.com/tharant/dots/main/scripts/setup.sh | bash
```

Two-step bootstrap on a bare Alpine container (bash, git and curl are needed
before the script itself can run):

```bash
apk add bash git curl
./scripts/setup.sh
```

After pulling new dotfiles into an existing checkout:

```bash
~/.dots/scripts/setup.sh --restow
```

Adopt config files that already exist in `$HOME`:

```bash
~/.dots/scripts/setup.sh --adopt
```

Tear down all managed symlinks:

```bash
~/.dots/scripts/setup.sh --unstow
```

Force a full re-decrypt (e.g. after rotating a passphrase or editing an
artifact) and re-stow:

```bash
~/.dots/scripts/setup.sh --force
```

Check the current deployment without changing anything:

```bash
~/.dots/scripts/setup.sh --verify
```

Clone the repo somewhere other than `~/.dots` — `DOTS_DIR` is read on every
run, wherever the script is launched from, so a later
`DOTS_DIR=$HOME/src/dots ~/.dots/scripts/setup.sh --restow` operates on
`~/src/dots`, not on the `~/.dots` clone the script was launched from. For
the very first run pass it to the bootstrap pipe:

```bash
curl -fsSL https://raw.githubusercontent.com/tharant/dots/main/scripts/setup.sh \
  | DOTS_DIR=$HOME/src/dots bash
```

Point the first run at a fork (likewise only used for the initial clone; an
existing clone at `DOTS_DIR` is pulled, never re-pointed):

```bash
curl -fsSL https://raw.githubusercontent.com/tharant/dots/main/scripts/setup.sh \
  | DOTS_REPO_URL=https://github.com/youruser/dots.git bash
```