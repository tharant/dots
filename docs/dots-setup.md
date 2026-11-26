# dots-setup(1)

## Name

**dots-setup** — bootstrap and manage the dots dotfiles deployment.

## Synopsis

```
dots-setup [--restow|--adopt|--unstow|--force|--verify|-h|--help]
dots-setup            # no args: full bootstrap (install deps, clone, decrypt, stow,
                      #   seed ~/.packages)
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
6. Seed `~/.packages` from the repo template, if the machine has no wishlist
   yet (see the [packages](packages.md) shim).

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
reported by the ERR trap. Homebrew is never run with the privilege prefix;
MacPorts (`port`, `installer`) always is.

**Output policy.** The terminal carries only the `==>` status lines.
Package-manager (`apt-get`, `brew`, `port`, `dnf`, `pacman`, `apk`, `pkg` —
including the one-time `apt-get update` / `port selfupdate`), installer
(Homebrew, MacPorts, uv, sdkman),
locale-generation and git (clone/pull) output is captured in a per-run audit
log at `~/.local/state/dots/setup-<timestamp>.log`, whose path is announced
at the start of every run. A captured step that fails prints the last 20
lines of the log so the error itself stays on the terminal, and the
end-of-run failure summary names the log. Stow and decrypt output is not
captured: stow conflicts are immediately actionable, and the decrypt prompts
need the terminal.

**Detection.** `uname -s` maps Darwin→`macos`, Linux→`linux`, and anything
matching `*BSD`→`bsd`; anything else is fatal ("Unsupported platform"). On
Linux the distro `ID` and `ID_LIKE` come from `/etc/os-release` (read in a
subshell, so its variables do not leak into the script); distro checks match
either, so derivatives are recognised by family — e.g. postmarketOS
(`ID_LIKE=alpine`) gets the Alpine treatment and Rocky/Alma/CentOS
(`ID_LIKE` containing `rhel`/`centos`) the EL one. Outside macOS, `/sbin`,
`/usr/sbin` and `/usr/local/sbin` are appended to `PATH` for the run when
missing — a non-root sshd/su/cron `PATH` is just `/usr/bin:/bin`, where
Alpine's `/sbin/apk` would be invisible. WSL is detected from
`WSL_DISTRO_NAME` or the kernel string in `/proc/version`; an OrbStack kernel
string on macOS is reported informationally only.

**Package managers.** On macOS the choice is between Homebrew (`brew`) and
MacPorts (`port`) — see the macos entry below. Elsewhere the detection order
is `apt-get`, `dnf`, `zypper`, `pacman`, `apk`, `pkg`, then `brew` — the
system package manager always wins over a Linuxbrew on `PATH` — and none
found is fatal. Once per run, before the first install, the index is
refreshed: `apt-get update`, `zypper refresh`, `pacman -Syu` (a full upgrade:
`-Sy` followed by `-S` is an unsupported partial upgrade on Arch) and on
MacPorts `port selfupdate`. apt runs with `DEBIAN_FRONTEND=noninteractive`,
zypper with `--non-interactive --no-recommends`, pacman with `--needed`. Batch installs are retried package by package when the batch
fails, so one missing or renamed package does not sink the whole set;
individual failures are recorded as non-fatal.

Per-platform behaviour:

- **macos** — picks the package manager. Homebrew no longer supports Intel
  Macs, so the rule is:
  - only one of `brew` / `port` installed → use it (an existing Homebrew on
    an Intel Mac is kept, with a warning suggesting MacPorts);
  - both installed → Homebrew on Apple Silicon, MacPorts on Intel;
  - neither → bootstrap Homebrew on Apple Silicon, MacPorts on Intel;
  - `DOTS_MACOS_PKG_MGR=brew|port` forces the choice — except that Homebrew
    is never *installed* on an Intel Mac (fatal).

  Apple Silicon is detected from `sysctl hw.optional.arm64` (hardware, so a
  Rosetta shell still counts as Apple Silicon). Installed managers are found
  on `PATH` or at their standard prefixes (`/opt/homebrew`, `/usr/local`,
  `/opt/local`) and put on `PATH` for the run.

  **Homebrew**: exports `HOMEBREW_NO_ANALYTICS=1` and `HOMEBREW_NO_ENV_HINTS=1`
  (Homebrew must not call home; the macos platform layer sets the same vars
  for interactive shells), installs Homebrew itself when missing (official
  installer, `NONINTERACTIVE=1`, run as the invoking user; fatal as root).
  **MacPorts**: ensures the Xcode Command Line Tools (headless
  `softwareupdate -i`, falling back to the `xcode-select --install` dialog
  and a fatal "re-run" message), downloads the latest
  `MacPorts-<version>-<macOS major>-<name>.pkg` from the
  `macports/macports-base` GitHub releases, refuses it unless `pkgutil
  --check-signature` reports an Apple-issued Developer ID signature, and
  installs it with `installer -pkg … -target /` (all fatal on failure).

  Then, with either manager, installs `bash age stow just tmux shellcheck git
  coreutils direnv jq bc`, adds that manager's bash (`/opt/homebrew/bin/bash`,
  or next to an existing `brew`; `/opt/local/bin/bash` for MacPorts) to
  `/etc/shells`, and makes it the login shell with `chsh` (both non-fatal if
  they fail).
- **Alpine** — ensures the `community` repository is enabled in
  `/etc/apk/repositories` (derived from the `main` line and appended; if the
  file or the mirror line is missing, the failure is recorded and the step is
  skipped rather than fatal), refreshes apk indexes, then installs `bash
  coreutils findutils util-linux git age stow just tmux shellcheck direnv shadow
  bash-completion ncurses-terminfo curl ca-certificates` — plus `sudo` when
  neither sudo nor doas is present.
- **Debian (apt-get)** — installs `git age stow tmux shellcheck bash coreutils
  less locales ca-certificates curl wl-clipboard xz-utils direnv`, then extras:
  Node.js 22 from apt when the apt candidate is ≥ 22, otherwise the official
  `v22.23.2` tarball extracted into `/usr/local/lib/nodejs` (which the script
  creates with `mkdir -p` if missing) with `node`, `npm`, `npx` symlinked into
  `/usr/local/bin`. Then: `just` from apt when available,
  otherwise the upstream musl binary (`1.58.0`) into `/usr/local/bin`; and
  `en_US.UTF-8` generation via `locale-gen` — resolved through `PATH` with
  `/usr/sbin/locale-gen` as an absolute-path fallback, because `/usr/sbin` is
  not always on `PATH` (OrbStack syncs the Mac's `PATH` into its machines;
  non-login shells) even when the `locales` package is installed (skipped with
  a recorded failure if neither is found, or if `/etc/locale.gen` is missing).
- **Other Linux** (dnf, zypper, pacman) — `git age stow just tmux shellcheck
  bash coreutils direnv curl ca-certificates jq bc tar gzip` (tar/gzip because
  minimal EL and openSUSE images lack them). On the RHEL family (dnf
  with `ID`/`ID_LIKE` `rhel` or `centos`: Rocky, Alma, CentOS Stream, RHEL)
  EPEL is enabled first — `epel-release` from the distro's repos, else the
  `epel-release-latest-<major>` rpm from dl.fedoraproject.org — plus CRB
  (`crb enable`, `subscription-manager` on RHEL, else `dnf config-manager`
  for `crb`/`powertools`), because age, stow and shellcheck live there.
  Both steps are non-fatal. EPEL still lacks `direnv` (EL9/EL10) and `just`
  (EL9): the static fallbacks below cover them.
- **FreeBSD** — `git age stow just tmux hs-ShellCheck bash coreutils direnv
  curl ca_root_nss jq` via `pkg` (FreeBSD names the ShellCheck package
  `hs-ShellCheck`; `bc` is part of the base system).

Post-install: `tmux-mem-cpu-load` is installed for the tmux-powerline
mem/cpu segment — the Homebrew formula or MacPorts port on macOS, the
`pkg` package on FreeBSD, built
from source at the pinned upstream release (`v3.8.3`) on Linux, where
neither Debian nor Alpine packages it. The build installs the native C++
toolchain plus cmake — `build-essential` on apt, `build-base` on apk,
`gcc-c++ make` on dnf and zypper, `base-devel` on pacman — and installs the binary into
`/usr/local/bin`. Any other package manager or platform skips it with a
recorded non-fatal failure — on failure the
segment simply drops out of the status bar. On Linux a still-missing
`just` falls back to the upstream static musl binary (`1.58.0`) and a
still-missing `shellcheck` (openSUSE Leap 16 has no package) to the upstream
static binary (`v0.11.0`), both into `/usr/local/bin`, whatever the package
manager. Then `git curl just tmux
shellcheck` are each verified (a missing
tool is a recorded non-fatal failure), a missing `stow` is **fatal**, a
missing `age` falls back to the static release `v1.3.1` installed to
`~/.local/bin` (mode 0755), and a missing `direnv` falls back to the static release `v2.37.1`
the same way — but as a **hard** requirement: if the fallback also fails the
run aborts ("direnv is required for the direnv integration but could not be
installed"), because the direnv stow package is useless without its hook
binary. Fallbacks into `~/.local/bin` (age, direnv, uv, fnm) put that
directory on `PATH` for the rest of the run — so `dots-decrypt` finds a
fallback `age` — instead of warning about it; `.bashrc` adds it for
interactive shells. Finally, an `install: <tool>` failure recorded by a
package retry is dropped again when a fallback put `<tool>` on `PATH`
(e.g. `just`/`direnv` on EL), so a covered package does not flip the exit
status.

**Runtime managers.** After the post-install checks (macOS, Linux and WSL
only — BSD is dotfiles-only and skips this step with an informational
message) the run installs the three backends behind the
[runtimes](runtimes.md) shim, each best-effort and recorded as a non-fatal
failure on error, never aborting the run:

- **uv** (python backend) via the official installer, run with
  `UV_NO_MODIFY_PATH=1` so it never appends PATH lines to the shell RCs
  (on a deployed machine those are stowed symlinks — a dirty-tree hazard);
  binary at `~/.local/bin/uv`.
- **fnm** (node backend) from the upstream `v1.39.0` release zips:
  `fnm-macos.zip` is a universal (x86_64 + aarch64) binary, `fnm-linux.zip`
  / `fnm-arm64.zip` are static musl binaries that run on Alpine and glibc
  alike; `unzip` is installed on demand; binary at `~/.local/bin/fnm`.
- **sdkman** (java backend) via the official installer. The installer
  appends its init snippet to `~/.bashrc`, `~/.bash_profile` or `~/.zshrc`
  — each file is snapshotted before the install and restored right after
  (the .bashrc this repo ships already contains the identical snippet, so
  the strip changes nothing functionally). Afterwards
  `sdkman_auto_answer=true` is set in `~/.sdkman/etc/config` so the
  `runtimes` shim's non-interactive `sdk install` never prompts.

Stowing runs `stow -d <dir> -t $HOME --no-folding` over every package in
`common/`, then the platform package directory (`macos/`, `linux/`, `bsd/`),
then the `alpine/` layer on Alpine and the `wsl/` layer under WSL. Layers
whose directory does not exist are skipped silently. A package that fails to
stow is recorded as a failure and stowing continues with the remaining
packages.

Before each package is stowed (in the full, `--force` and `--restow` runs,
but not `--adopt` or `--unstow`), any plain regular file sitting at one of
the package's target paths is moved aside into
`~/.dots-backup-<timestamp>/`, preserving its path relative to `$HOME` — so a
fresh distro's `/etc/skel` defaults (Debian seeds `~/.bashrc` and
`~/.bash_logout`) no longer abort the whole package. Symlinks and directories
are never moved; those remain conflicts stow is right to refuse. Nothing is
deleted — each move is reported as it happens and the backup directory is
named in a summary line when anything was backed up.

Finally, the package wishlist `~/.packages` is seeded from
`templates/packages/.packages` when the machine does not have one yet — a
minimal baseline (the tools this run guarantees), never overwritten once it
exists. The user owns the file from there: remove
[`#` comments](packages.md) and run `packages update` to add packages; the
full run never installs anything from the wishlist itself.

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
| `DOTS_MACOS_PKG_MGR` | macOS only: `brew` or `port` forces the package manager (any other value is fatal). Homebrew is still never installed on an Intel Mac. | unset (auto-detect) |
| `SHELL` | Read on macOS to decide whether `chsh` is needed for the package manager's bash. | — |

## Exit status

- **0** — all requested steps completed and nothing was recorded in the
  failure list.
- **1** — a fatal error occurred, *or* one or more non-fatal steps failed.
  The fatal paths are: unsupported platform, no supported package manager,
  the Homebrew installer failing or setup.sh running as root (Homebrew
  refuses root), Homebrew requested on an Intel Mac without one installed,
  an invalid `DOTS_MACOS_PKG_MGR`, missing Xcode Command Line Tools or a
  failed MacPorts download / signature check / install, Alpine run without bash, no privileges when
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
- `~/.local/state/dots/setup-<timestamp>.log` — per-run audit log holding
  the captured package-manager/installer/git output (kept across runs).
- `~/.dots-backup-<timestamp>/` — pre-existing `$HOME` files moved aside to
  unblock stowing (full, `--force` and `--restow` runs); restore by hand if
  needed.
- `/etc/os-release` — Linux distro ID.
- `/proc/version` — WSL detection.
- `/etc/apk/repositories` — read, and extended with the community repo, on Alpine.
- `/etc/locale.gen` — enabled for `en_US.UTF-8` on Debian.
- `/etc/shells` — appended with the Homebrew or MacPorts bash on macOS.
- `/opt/local` — MacPorts prefix (installed on Intel Macs).
- `~/.local/bin/age`, `~/.local/bin/age-keygen` — static age fallback (0755).
- `~/.local/bin/direnv` — static direnv fallback (0755).
- `/usr/local/bin/shellcheck` — static shellcheck fallback (any Linux without a package).
- `~/.local/bin/uv`, `~/.local/bin/fnm` — runtime-manager installs (macOS/Linux/WSL).
- `~/.sdkman/` — sdkman install, with `sdkman_auto_answer=true` in `etc/config`.
- `/usr/local/bin/just` — static just fallback (any Linux without a `just` package).
- `/usr/local/lib/nodejs/` — Node.js tarball fallback (Debian).
- `~/.packages` — seeded from `templates/packages/.packages` in the full
  and `--force` runs when absent; the [packages](packages.md) wishlist.
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