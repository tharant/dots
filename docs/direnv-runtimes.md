# direnv + runtimes: per-directory environments and managed runtimes

Feature guide for the direnv integration shipped in `common/direnv/` (stowed
to `~/.config/direnv/` and `~/.envrc`) and the [`runtimes`
CLI](dots-runtimes.md) (`~/bin/runtimes`). Together they recreate the old
workflow: `cd` anywhere, get folder-level env vars; `.envrc`s stack up the
directory tree; runtimes (python, node, java) are pinned per project and
installed automatically the first time you `cd` in.

Everything ships in this repo — [dots-setup(1)](dots-setup.md) installs
direnv (hard requirement) plus uv, fnm and sdkman (best-effort, skipped on
BSD) and wires the direnv hook into `.bashrc` after the trueline block, so
the hook actually survives trueline's `PROMPT_COMMAND` reset.

## Quick start

```bash
mkdir ~/code/foo && cd ~/code/foo
cat > .runtimesrc <<'EOF'
python 3.12
java 17
node 22
EOF
cat > .envrc <<'EOF'
source_up_if_exists
use_runtimes
export FOO=bar
EOF
direnv allow
```

At the first prompt after `direnv allow`:

```
direnv: loading ~/code/foo/.envrc
runtimes: installing python 3.12, java 17, node 22 (log: ~/.local/state/runtimes/logs/1f2e….log)
```

The install runs **detached** — evaluation never blocks on it. Subsequent
prompts print one `install still in progress` status line while it runs. When
it finishes, the worker writes `.runtimes.lock`, and `use_runtimes`'s
`watch_file` makes direnv re-evaluate `.envrc` at the **next prompt** —
`PATH`, `JAVA_HOME`, `VIRTUAL_ENV` and `UV_PYTHON` are then live. direnv is
prompt-driven, not event-driven, so "reload at the next prompt" is the
designed behavior, not a delay to work around.

The only per-project ceremony ever needed again is `direnv allow` after
editing `.envrc`.

## Authoring `.runtimesrc`

One `<name> <spec>` pair per line, diffable like `.tool-versions`. `#`
starts a comment (full-line or trailing):

```
# comment lines allowed (leading #)
python 3.12          # any uv-resolvable spec: 3.12, 3.12.7, …
node 22              # a major → resolved to latest vX.Y.Z at install time
java 17              # a major → resolved to latest <major>.x.y-tem (sdkman)
java 21.0.12+1.1-tem # exact sdkman candidate IDs also accepted
```

Supported names: `python`, `node`, `java` (anything else logs
`unknown runtime '…'`). Resolution is the CLI's job —
[runtimes(1)](dots-runtimes.md) — and happens only at install time; `.envrc`
evaluation reads the resulting `.runtimes.lock` and never the network.

`.runtimes.lock` sits next to `.runtimesrc` and records the concrete
resolved version + store path per line (absolute paths, so it is
machine-local by nature). Deleting the lock forces a re-ensure on the next
`cd` — useful after a store wipe or to force a re-resolve.

## Authoring `.envrc`

The helpers are defined in `~/.config/direnv/direnvrc` (stowed from
`common/direnv/.config/direnv/direnvrc`) and sourced into every `.envrc`
evaluation. They intentionally shadow direnv's stdlib
virtualenv-flavoured `use_python`.

### Helpers

- `use_runtimes [file]` — apply the runtimes declared in a `.runtimesrc`
  (default: `$PWD/.runtimesrc`; a directory argument works too). Runs
  `runtimes ensure` first (a milliseconds-fast no-op when the lock already
  satisfies the rc), then applies line by line: python via `use_python`, node
  via `use_node`, java via `use_java`. `watch_file` is set on both
  `.runtimesrc` (spec edits) and `.runtimes.lock` (background install
  completion) — each triggers a re-evaluation at the next prompt.
- `use_runtime <name> <spec>` — thin dispatcher to the per-runtime helper.
- `use_python <spec>` — adds the interpreter's bin dir to `PATH`, exports
  `UV_PYTHON=<spec>` so every uv invocation targets the project
  interpreter, and creates + activates a project-local `.venv` (below).
- `use_node <spec>` — adds the locked installation's bin dir to `PATH`
  straight from the lock. Never `eval "$(fnm env …)"` in an evaluation:
  every eval would mint an fnm multishell symlink that fnm never
  garbage-collects.
- `use_java <spec>` — exports `JAVA_HOME` from the concrete candidate dir in
  the lock — never sdkman's `current` symlink (cross-project interference)
  — and adds `$JAVA_HOME/bin` to `PATH`.
- `use_template <name>` — scaffold `$PWD` from a repo template (below).

Everything the helpers print goes through direnv's `log_status`/`log_error`
(stderr) — stdout is the environment dump direnv evaluates and stays clean.
Evaluation reads local files only and runs `runtimes ensure`/`runtimes
path` (both fast, local-only); there is never a foreground download, so a
hung `DIRENV_WARN_TIMEOUT` (bumped to 10s in `~/.config/direnv/direnv.toml`)
cannot hang every prompt.

A typical project `.envrc` is three lines:

```bash
source_up_if_exists     # evaluate the parent .envrc first
use_runtimes            # apply .runtimesrc (creating .venv, wiring PATH/…)
export FOO=bar          # project exports last, overriding parents
```

### The venv

`use_python` creates `$PWD/.venv` **once**, only when the project declares
python in `.runtimesrc`, via
`UV_NO_PROJECT=1 uv venv --python <resolved> --seed .venv` (`UV_NO_PROJECT`
keeps uv from walking up into a parent `pyproject.toml`; `--seed` gives the
venv pip without a project). Creation is local and sub-second, so it
happens during evaluation — the interpreter *download* never does (that is
the detached `runtimes ensure` install). It then activates the venv:
`export VIRTUAL_ENV=$PWD/.venv`, `PATH_add .venv/bin`, and
`watch_file .venv/pyvenv.cfg`. Dependencies stay strictly project-local
(`pip install` into `.venv`); only runtime binaries are global and deduped.

### Tree stacking

direnv walks up from the current directory and evaluates the **nearest**
`.envrc` it finds — that one, not the whole chain. Parent values merge in
only when the child opts in with `source_up_if_exists`: the parent is
evaluated first, so the child's exports override redefined vars while
unmentioned parent values persist.

The stowed `~/.envrc` is the tree root: it is **comment-only** (an `.envrc`
that exports nothing is a no-op), so every directory under `$HOME` without
its own `.envrc` evaluates it cleanly and inherits nothing. Its header
documents the chaining convention; put real exports in per-project (or
per-subtree) `.envrc` files instead of editing it.

## Templates (`use_template`)

`use_template <name>` expands a repo template into `$PWD` via
`runtimes template` ([runtimes(1)](dots-runtimes.md) has the full rules).

- `templates/<name>/` is the tree; `templates/<name>.template` is its
  manifest: `description=`, `substitute=` (space-separated var names),
  `ignore=` (space-separated globs skipped on expansion).
- `{{VAR}}` tokens in file contents are substituted from env vars **already
  set** — evaluation order means `export PROJECT_NAME=foo` earlier in the
  same `.envrc` works; an unset var is left in place with a warning.
- Idempotent by design: evaluation re-runs on every reload, so `use_template`
  skips (a normal status, not an error) when the directory holds anything
  besides the direnv artifacts (`.envrc`, `.runtimesrc`, `.runtimes.lock`,
  `.direnv/`). Overwriting requires `runtimes template <name> --force`.

`templates/example/` ships as the proof of plumbing: a README, a `src/`
file, and a `notes.local` the manifest ignores.

## Troubleshooting

- **`cd` does nothing** (no "loading .envrc" line): direnv only runs from its
  shell hook. The hook is installed after the trueline block in `.bashrc` —
  trueline resets `PROMPT_COMMAND` without chaining, so a hook placed before
  it is silently discarded. `just verify` checks both presence and order.
  Also confirm direnv itself is installed (`command -v direnv`).
- **`.envrc is blocked`**: direnv requires `direnv allow` in the project
  directory after every edit of `.envrc` (the allow record is a per-machine
  trust decision hashed on file content — intentionally not shipped). Use
  `direnv deny` to revoke.
- **The new runtime is installed but not applied yet**: remember direnv is
  prompt-driven. The detached install finishing writes `.runtimes.lock`,
  and the `watch_file` on it takes effect at the **next prompt** — press
  enter once. Editing `.runtimesrc` (or any `watch_file` target) reloads the
  same way.
- **`runtimes: installing …` appears on every prompt**: each prompt prints
  one `install still in progress` status line while the detached install
  runs — that is the single-flight guard doing its job. Follow the printed
  log path (`~/.local/state/runtimes/logs/<hash>.log`) to watch progress;
  `just runtimes status` shows the stores. A failed line leaves the old lock
  in place and the log ends with `install incomplete … — lock not written`;
  the next `cd` retries the whole install.
- **`runtimes command not found`** in the direnv status line: run
  `just setup` (the shim deploys to `~/bin/runtimes`, which `.bashrc` puts
  on `PATH`).
- **`<runtime> <spec> not installed yet — system <runtime> stays active`**:
  normal during the first install — the helpers degrade to the system
  runtime rather than failing evaluation; the locked runtime applies at the
  next reload.
- **Alpine aarch64 node fails**: musl has no official node builds and
  unofficial-builds ships `x64-musl` only — a documented gap; the install
  dies with a clear error. Python and java are unaffected.
- **BSD**: the integration deploys but does not auto-install. `use_runtimes`
  reports `runtime auto-install unsupported on BSD; falling back to system
  runtimes` and each name degrades to its system binary via `command -v`.

## See also

[runtimes(1)](dots-runtimes.md) — the CLI half: subcommands, backends, lock
file, platform matrix · [dots-setup(1)](dots-setup.md) — installs direnv,
uv, fnm, sdkman · [dots-verify(1)](dots-verify.md) — checks the hook, the
direnvrc and the shim