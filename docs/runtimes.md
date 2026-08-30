# runtimes(1)

## Name

**runtimes** — manage project runtimes declared in `.runtimesrc`

## Synopsis

```
runtimes <command> [args]
```

Deployed as `~/bin/runtimes` by [dots-setup(1)](dots-setup.md) from
[`common/bin/bin/runtimes`](../common/bin/bin/runtimes). The direnv half of
the integration — authoring `.envrc` files that call this CLI — is the
[feature guide](direnv-runtimes.md).

## Description

`runtimes` is the CLI half of the direnv integration: it reads a project's
`.runtimesrc`, resolves each declared runtime through its backend, and
records the concrete result in the project's `.runtimesrc.lock`. Three
backends, one resolution rule each:

| Runtime | Backend | Spec resolution |
|---|---|---|
| `python` | [uv](https://docs.astral.sh/uv/) | any uv-resolvable spec (`3.12`, `3.12.7`), installed via `uv python install` |
| `node` | [fnm](https://github.com/Schniz/fnm) | a major (`22`) resolves to the latest `vX.Y.Z` via `fnm ls-remote` at install time; a concrete `vX.Y.Z` (or `X.Y.Z`) is used verbatim |
| `java` | [sdkman](https://sdkman.io) | a major (`17`) resolves to the latest `<major>.x.y-amzn` (Corretto) via the sdkman version API, falling back to `<major>.x.y-tem` (Temurin) when a major has no Corretto build (`sdk list` is never used — it forces a pager); an exact candidate ID (`21.0.12+1.1-amzn`) is used verbatim |

`ensure` is the direnv hot path: it only reads local files, so a satisfied
project is a milliseconds-fast no-op. Anything missing or changed kicks off
a **detached** install (`nohup … &`) whose output goes to a per-project log —
`.envrc` evaluation never blocks on the network. A pid guard
(`~/.local/state/runtimes/pids/`) makes installs single-flight: while one
runs, further `ensure` calls print one status line and exit 0. When the
install finishes it writes `.runtimesrc.lock` atomically (temp file + rename),
so a project never sees a half-applied environment.

stdout is reserved for `path` output (machine-consumed by the direnvrc
helpers); every human-facing message goes to stderr.

### The lock file

`.runtimesrc.lock` holds one line per runtime, recording the resolved version
and the absolute store path:

```
python 3.12 3.12.12 ~/.local/share/uv/python/cpython-3.12.12-macos-x86_64-none
node 22 22.21.1 ~/.local/share/fnm/node-versions/v22.21.1/installation
java 17 17.0.20-amzn ~/.sdkman/candidates/java/17.0.20-amzn
```

The lock is written only when **every** entry in `.runtimesrc` is satisfied —
a failed line leaves the old lock in place (and `ensure` reports
`install incomplete … — lock not written` in the log), so the next `cd`
retries the whole install. The worker applies the same store-root rule the
direnv helpers apply on read: a backend result outside its store (e.g. a
project `.venv` resolved by `uv python find`) is skipped with a warning
instead of written, so the lock can never carry a path evaluation would
reject. `.envrc` evaluation reads the lock, never the network and never
resolution logic.

The lock was previously named `.runtimes.lock`; machines blessed before the
rename migrate automatically — `ensure` renames an old-name lock to
`.runtimesrc.lock` (content untouched, only in directories that have a
`.runtimesrc`) as its first act, so the migration happens on the next
`cd` into each project. Nothing else about the format or placement changed.

### Commands

- `runtimes ensure [dir]` — satisfy every runtime in `<dir>/.runtimesrc`
  (default: the current directory, also the fallback for a relative `dir`).
  Exits 0 immediately when there is no `.runtimesrc`, when the lock already
  covers every entry with a live store path, when an install is in flight
  (`install still in progress (…); log: …`), or after kicking off a new
  detached install (`installing python 3.12, node 22 (log: …)`). On BSD,
  prints `runtime auto-install unsupported on BSD; falling back to system
  runtimes`, checks `command -v` per name, and exits 0.
- `runtimes install <name> <version>` — foreground install of one runtime
  with visible progress; the same resolution and atomicity rules as `ensure`,
  but it fails (exit 1) instead of degrading. Refused outright on BSD.
- `runtimes status` — list installed runtimes per backend
  (`uv python list --only-installed`, fnm `node-versions/`, sdkman
  candidates except `current`) plus the store and state paths, and the
  project `.runtimesrc`/`.runtimesrc.lock` when the current directory has one.
- `runtimes path <name> <spec> [dir]` — print the runtime's bin dir
  (python, node) or `JAVA_HOME` (java) from `<dir>/.runtimesrc.lock` (default:
  current directory); this is what the direnvrc helpers consume. Exit 1 when
  the lock has no matching entry (`<name> <spec> not satisfied in <dir>
  (run: runtimes ensure <dir>)`) or when the entry points at a path that no
  longer exists.
- `runtimes template <name> [--force] [dest]` — expand the repo template
  `<templates-dir>/<name>` into `dest` (default: current directory).
  `{{VAR}}` tokens in file contents are substituted from the environment
  variables listed in the manifest's `substitute=` (unset vars are left in
  place with a warning). Existing files are never overwritten unless
  `--force` (`refusing to overwrite:…`). Manifest files matched by `ignore=`
  globs are skipped. Everything is staged first and moved per file, so the
  destination only ever gains whole files.

### Platform support

| Tier | Platforms | Behavior |
|---|---|---|
| Full | macOS (x86_64, aarch64), Debian/Ubuntu, Alpine x86_64, WSL2 (Debian/Alpine x86_64) | direnv, uv, fnm and sdkman installed by [dots-setup(1)](dots-setup.md); all three backends auto-install |
| Partial | Alpine/WSL aarch64 (musl) | python and java auto-install as usual; node has no arm64-musl build — the install dies with `no musl node build for <arch>: unofficial-builds ships x64-musl only`. Alpine x86_64 node comes from the unofficial-builds mirror via `FNM_NODE_DIST_MIRROR`/`FNM_ARCH=x64-musl` |
| Dotfiles only | FreeBSD and other `*BSD` | configs (including the direnv package) deploy, but runtime auto-install is unsupported: `ensure` degrades to system runtimes via `command -v` and exits 0; `install` refuses with an error |

## Options

- `-h`, `--help` — print usage to stderr and exit 0 (bare `runtimes` does the
  same).
- `--force` — with `template` only: overwrite existing files at the
  destination.

## Environment

- `HOME` — base for every default store, the state dir and `~/bin/runtimes`.
- `FNM_DIR` — fnm store; defaults to `~/.local/share/fnm`. Node installs land
  in `$FNM_DIR/node-versions/vX.Y.Z/installation`.
- `UV_PYTHON_INSTALL_DIR` — uv's python store; defaults to
  `~/.local/share/uv/python`. Honored by uv itself during installs; shown by
  `status`.
- `SDKMAN_DIR` — sdkman root; defaults to `~/.sdkman`. Java candidates live
  in `$SDKMAN_DIR/candidates/java/<id>`.

## Exit status

- `0` — success, or a path designed not to fail evaluation: `ensure` kicked
  off (or found running) a detached install; `ensure` on BSD fell back to
  system runtimes; `--help` was printed.
- `1` — an error: unknown command, wrong argument count, no such directory,
  unknown runtime name (supported: python, node, java), a backend failure
  (`uv`/`fnm`/sdkman missing, no release matching the spec), `path` on an
  unsatisfied runtime, or a template refusing to overwrite. A detached worker
  whose install was incomplete also exits 1 — after writing no lock.

## Files

- `.runtimesrc` — per-project runtime declarations, one `<name> <spec>` per
  line; `#` starts a comment.
- `.runtimesrc.lock` — per-project resolved versions + store paths, written by
  `ensure`'s detached worker.
- `~/.local/state/runtimes/logs/<hash>.log` — output of the detached install
  for a project (`<hash>` is a hash of the project directory path:
  `sha256sum`, `shasum -a 256`, or `cksum` — whichever exists).
- `~/.local/state/runtimes/pids/<hash>.pid` — single-flight guard for the
  detached install; a marker whose pid is dead is reclaimed.
- `~/.local/share/uv/python`, `$FNM_DIR/node-versions`,
  `$SDKMAN_DIR/candidates/java` — the per-backend stores.
- `templates/<name>/`, `templates/<name>.template` — in the repo (not stowed):
  the template tree and its manifest (`description=`, `substitute=`,
  `ignore=`). Located relative to the repo root, derived from the script's
  own location so the stowed symlink resolves into the clone.

## Intended usage

`runtimes` exists to be called by the direnv helpers
([feature guide](direnv-runtimes.md)): `use_runtimes` runs `runtimes ensure`
on every `.envrc` evaluation (fast no-op when satisfied) and `use_python` /
`use_node` / `use_java` consume `runtimes path` to wire `PATH`,
`JAVA_HOME` and the project venv. Humans rarely type `ensure` — typing
`runtimes status` to see what is installed (and whether the current project
has a lock yet), `runtimes install` to watch a single install in the
foreground, and reading the log path `ensure` prints are the interactive
entry points.

It follows the same pattern as [loadavg(1)](loadavg.md) and
[tmux-copy(1)](tmux-copy.md): a portable shim in `common/bin/bin/`, deployed
to `~/bin/`, absorbing the platform differences (here: which backend owns
which runtime, musl mirrors, the BSD tier) behind one interface, documented
under the documentation contract in [CLAUDE.md](../CLAUDE.md). It is written
for bash 3.2 (no associative arrays, no `mapfile`, no case-folding), runs
under `set -euo pipefail`, and needs only a BusyBox userland plus `curl` or
`wget`.

## Examples

Declare a project's runtimes and let direnv drive the CLI:

```bash
$ cd ~/code/foo
$ printf 'python 3.12\nnode 22\n' > .runtimesrc
$ runtimes ensure
==> runtimes: installing python 3.12, node 22 (log: ~/.local/state/runtimes/logs/1f2e….log)
$ runtimes ensure        # again, while the install runs
==> runtimes: install still in progress (python 3.12, node 22); log: ~/.local/state/runtimes/logs/1f2e….log
```

Inspect the stores and the current project:

```bash
$ just runtimes status
```

Consume a locked runtime the way the direnvrc helpers do (stdout only):

```bash
$ runtimes path python 3.12
/Users/you/.local/share/uv/python/cpython-3.12.12-macos-aarch64-none/bin
$ runtimes path java 17
/Users/you/.sdkman/candidates/java/17.0.20-amzn
```

## See also

[direnv + runtimes feature guide](direnv-runtimes.md) ·
[dots-setup(1)](dots-setup.md) · [loadavg(1)](loadavg.md) ·
[tmux-copy(1)](tmux-copy.md)