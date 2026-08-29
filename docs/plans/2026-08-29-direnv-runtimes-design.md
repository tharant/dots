# direnv + runtimes: per-directory environments and managed runtimes

**Date:** 2026-08-29
**Branch:** `direnv`
**Status:** approved design, pending implementation

## Context

The old dev workflow this recreates: `cd` anywhere, drop a `.envrc` with folder-level
env vars; `.envrc`s stack up the directory tree (nearest wins, unspecified parent
values persist); runtimes (JDK, Python, Node) are specified per project and are
installed automatically the first time you `cd` in; projects can also scaffold
themselves from a template.

Decisions already made with the user:

1. **Global-clean lean**: runtime *binaries* live in one global, deduplicated store;
   project *dependencies* (`.venv`, `node_modules`) stay strictly project-local.
2. **sdkman stays** as the Java backend (no Temurin-direct downloader).
3. **BSD is dotfiles-only**: configs deploy, but runtime auto-install is unsupported
   there; the shim reports clearly and falls back to system runtimes.

## Goals

- Same workflow on macOS (x86_64 + aarch64), Debian/Ubuntu, Alpine (musl), WSL2.
- `cd` + `direnv allow` is the only per-project ceremony.
- Never leaves a machine or project in a broken intermediate state (atomic
  installs, no half-applied environments).
- Bootstrap keeps running under bash 3.2 on fresh macOS; shims and `.envrc`
  helpers are bash-3.2-safe and BusyBox-aware.
- Follows every repo convention (stow layout, platform layering, shellcheck
  gates, docs/man mirrors, Justfile style).

## Non-goals

- Replacing `mise`/`asdf`-style unified tooling (BSD support rules it out).
- Runtime auto-install on BSD (system runtimes only, `command -v` fallbacks).
- Managing project dependencies (pip/npm/cargo installs) — only interpreters,
  runtimes, and their activation.
- Windows-native support.

## User experience (target flow)

```bash
# once per machine:
curl -fsSL https://raw.githubusercontent.com/tharant/dots/main/scripts/setup.sh | bash
#   → direnv, uv, fnm, sdkman installed; direnv hook live in .bashrc

# per project:
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
#   → first prompt: "runtimes: installing python 3.12, java 17, node 22
#      (log: ~/.local/state/runtimes/logs/<hash>.log)"; installs run detached
#   → subsequent prompts: still installing (one status line, no hangs)
#   → when done: .runtimes.lock written → direnv reloads at next prompt;
#      PATH/JAVA_HOME/VIRTUAL_ENV all live
```

Optional project scaffolding: `use_template scalatra` in the same `.envrc`
(idempotent — only expands into an empty or template-less directory).

## File map

```
common/direnv/                        # new stow package → $HOME
├── .envrc                            # → ~/.envrc: comment-only starter (tree root)
└── .config/direnv/
    ├── direnv.toml                   # warn_timeout bumped, whitelist none
    └── direnvrc                      # sourced into every .envrc eval:
                                      #   use_runtimes, use_runtime, use_python,
                                      #   use_node, use_java, use_template
common/bin/bin/runtimes               # → ~/bin/runtimes: the runtime manager CLI
templates/                            # repo root, NOT stowed (outside common/)
├── scalatra/…                        # template trees (files + dirs)
└── scalatra.template                 # manifest: which vars substitute, ignore list
docs/dots-runtimes.md                 # per-tool doc mirror (new convention)
docs/man/runtimes.1                   # roff page (new convention; man-check linted)
docs/direnv-runtimes.md               # feature guide: .envrc + .runtimesrc authoring
```

Modified files: `common/bash/.bashrc` (hook move + nvm→fnm), `scripts/setup.sh`
(tool installers), `scripts/verify.sh` (new checks), `Justfile` (lint coverage +
recipes), `.githooks/pre-commit` (lint coverage), `.editorconfig` (shim section),
`README.md`, `CLAUDE.md` (tree line).

## `.runtimesrc` and `.runtimes.lock`

`.runtimesrc` — line format, no JSON, parseable with a bash-3.2 `while read`
loop, diffs well, matches `.tool-versions` mental model:

```
# comment lines allowed (leading #)
python 3.12        # version is any uv-resolvable spec (3.12, 3.12.7)
node 22            # major → resolved to latest vX.Y.Z at ensure time
java 17            # major → resolved to latest <major>.x.y-tem (sdkman) at ensure time
java 21.0.12+1.1-tem  # exact sdkman candidate IDs also accepted
```

`.runtimes.lock` — written into the project directory by `runtimes ensure`
once all runtimes for that project are satisfied; records **concrete resolved
versions + paths**:

```
python 3.12 3.12.12 ~/.local/share/uv/python/cpython-3.12.12-macos-x86_64-none
node 22 22.21.1 ~/.local/share/fnm/node-versions/v22.21.1/installation
java 17 17.0.20-tem ~/.sdkman/candidates/java/17.0.20-tem
```

The lock is what `.envrc` evaluation reads (never the network, never resolution
logic). `watch_file .runtimes.lock` makes direnv reload at the next prompt
when a background install completes — direnv is prompt-driven, not
event-driven, so this is the correct mechanism.

## `runtimes` CLI contract

`#!/usr/bin/env bash`, `set -euo pipefail`, bash-3.2-safe, shellcheck clean.
Header comment block documents purpose/detection order like `loadavg`/
`tmux-copy`. Help text on `-h|--help` and bare invocation. Style: `info`/
`warn`/`die` helpers to stderr, never stdout pollution (stdout is reserved for
machine-consumed output on `path`).

| Command | Behavior |
|---|---|
| `runtimes ensure [dir]` | Read `dir/.runtimesrc` (default `$PWD`). For each line: if runtime present in store AND lock entry matches spec → no-op (must be **milliseconds**). If anything missing/changed: kick off detached install (`nohup … &`, log to `~/.local/state/runtimes/logs/<sha-of-dir>.log`), print one status line to stderr, exit 0. Concurrency guard: a `.lock.pid`/flock-style marker prevents stacked installs. On completion the install writes `.runtimes.lock` atomically (temp file + `mv`). |
| `runtimes install <name> <version>` | Foreground install with visible curl progress. Same resolution + atomicity rules. |
| `runtimes status` | List store contents per backend + config paths. |
| `runtimes path <name> <spec>` | Print the concrete bin dir / `JAVA_HOME` for an installed runtime (exit 1 if not installed). Machine-consumed by `direnvrc` helpers. |
| `runtimes template <name> [dest]` | Expand `templates/<name>` into `dest` (default `$PWD`), refusing to overwrite non-template files. |

Cross-cutting rules:

- **Atomic installs**: download/extract to a staging dir (`mktemp -d`), final
  placement via single `mv`/symlink swap. Ctrl-C or network drop mid-install
  leaves nothing half-present.
- **Platform guard**: on BSD (`uname -s` matches `*BSD`), `ensure` prints
  "runtime auto-install unsupported on BSD; falling back to system runtimes"
  and exits 0 after checking `command -v` for each name — `.envrc` evaluation
  degrades, never fails.
- **Store locations** (per-backend defaults, never relocated after use):
  uv pythons `~/.local/share/uv/python`, fnm `$FNM_DIR` (default
  `~/.local/share/fnm`), sdkman `~/.sdkman/candidates/<name>/<id>`.
- Alpine node: when musl is detected (`ldd --version 2>&1 | grep -q musl`),
  installs set `FNM_NODE_DIST_MIRROR=https://unofficial-builds.nodejs.org/download/release`
  and `FNM_ARCH=x64-musl` for the download only (documented fnm limitation;
  no arm64-musl story — error clearly there).

## Runtime backends

### python → uv

- Install/verify: `uv python install <spec>` (idempotent); resolve with
  `uv python find <spec>` (exits nonzero when missing — handled).
- `.envrc` application (`use_python`): export `UV_PYTHON=<spec>` so every uv
  invocation (and anything reading it) targets the project interpreter;
  `PATH_add` the interpreter's `bin` dir from the lock line.
- **Project venv**: if `$PWD/.venv` is absent and the project has a `.runtimesrc`
  python entry, `use_python` creates it via
  `UV_NO_PROJECT=1 uv venv --python <resolved> --seed .venv` (fast, local),
  then activates: `export VIRTUAL_ENV=$PWD/.venv`, `PATH_add .venv/bin`,
  `watch_file .venv/pyvenv.cfg`. Creation happens during evaluation (it is
  local and sub-second) — the *download* of the interpreter never does.
- `uv python list --only-installed` for `status`.

### node → fnm

- Install: `fnm install <version>` (`--progress=never` in non-interactive
  contexts). Major specs resolved to concrete `vX.Y.Z` via `fnm ls-remote`.
- `.envrc` application (`use_node`): `PATH_add
  $FNM_DIR/node-versions/v<X.Y.Z>/installation/bin` straight from the lock.
  **Never `eval "$(fnm env …)"` in evaluation** — every eval mints a
  multishell symlink that fnm never garbage-collects (on macOS they persist
  in `~/Library/Caches/fnm_multishells` forever). Direct PATH pointing makes
  the leak structurally impossible.
- Interactive default (outside projects): `.bashrc` prepends
  `$FNM_DIR/aliases/default/../…` — see bash integration.

### java → sdkman

- Install: `sdkman_auto_answer=true` is set in `~/.sdkman/etc/config` by
  setup.sh; `runtimes` invokes `sdk install java <id>` non-interactively
  (exact candidate IDs only; partial majors resolved via
  `https://api.sdkman.io/2/candidates/java/<platform>/versions/list?current=&installed=`,
  never `sdk list`, which forces a pager).
- `.envrc` application (`use_java`): `export JAVA_HOME=<concrete version dir>`
  from the lock, `PATH_add "$JAVA_HOME/bin"`. Never the `current` symlink
  (cross-project interference), never sourcing `sdkman-init.sh` in evaluation
  (bash-4 requirement).

## `direnvrc` helpers (common/direnv/.config/direnv/direnvrc)

Sourced into every `.envrc` evaluation. Bash-3.2-safe. All output via
`log_status`/`log_error` (stderr) — stdout is the env dump and must stay
clean.

```bash
use_runtimes [file]        # find .runtimesrc (default $PWD; --find-up later),
                           # read it, call use_python/use_node/use_java per line,
                           # watch_file .runtimesrc + .runtimes.lock, run
                           # `runtimes ensure` first (fast no-op when satisfied)
use_runtime <name> <spec>  # thin dispatcher to the per-runtime helper
use_python <spec>          # as above; reads resolved version from lock if present
use_node <spec>
use_java <spec>
use_template <name>        # guarded scaffolding (below)
```

Evaluation contract: helpers only read local files and run `runtimes
ensure`/`runtimes path` (both fast, local-only). **No network, no
foreground installs during evaluation** — `DIRENV_WARN_TIMEOUT` (5s default)
only warns, it never kills; a hung eval hangs every prompt.

`direnv.toml`: `warn_timeout = "10s"` (headroom for the ensure no-op path on
slow disks). No `[whitelist]` — the allow model stays explicit `direnv allow`.

`~/.envrc` starter ships comment-only (an `.envrc` that exports nothing is a
no-op for every directory under `$HOME` without its own). It documents the
`source_up_if_exists` chaining convention; direnv's native nearest-`.envrc`
walk + `source_up_if_exists` in children gives the recursive parent/child
merge semantics of the old workflow (child evaluated after parent, child
exports override, parent values persist).

## Template system (`use_template`)

- `templates/<name>/` is the tree; `templates/<name>.template` is a manifest
  (key=value: `description=`, `substitute=` space-separated var names,
  `ignore=` space-separated file globs not to copy).
- `use_template <name>` refuses to run if `$PWD` contains anything besides
  the direnv artifacts (`.envrc`, `.runtimesrc`, `.runtimes.lock`, `.direnv/`)
  — explicit idempotency guard, since evaluation re-runs on every reload.
  Overwrite requires `runtimes template <name> --force`.
- Substitution: `{{VAR}}` tokens in file contents replaced from already-set
  env vars listed in the manifest (evaluation order = user's `.envrc` runs
  first, so `export PROJECT_NAME=foo` above `use_template scalatra` works).
- v1 ships one example template to prove the plumbing; scalatra-shaped tree
  comes later.

## `.bashrc` integration (common/bash/.bashrc)

Two changes, both in `common/` (no platform conditionals):

1. **Fix the dead direnv hook.** The hook already exists at the "Optional
   tools" block, but trueline (sourced later) does `unset PROMPT_COMMAND;
   PROMPT_COMMAND=_trueline_prompt_command` and never chains — so on every
   bash ≥4.3 machine the hook is silently discarded. Fix: move the guarded
   hook line to directly after the trueline block, before the SDKMAN tail:

   ```
   # trueline block (49-55)
   command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"
   #THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!   ← stays last
   ```

   direnv's own docs mandate hook placement after prompt-manipulating
   extensions; sdkman-init does not touch `PROMPT_COMMAND`, so the tail
   constraint still holds.

2. **Replace the NVM block with fnm.** The guarded `NVM_DIR` sources go away;
   replaced by a default-version exposure that avoids `fnm env` (leak-free,
   works pre-install):

   ```bash
   # fnm: expose the default node install when one is set (alias created by
   # `fnm default <version>`); per-project versions come via direnv .envrc.
   if [ -d "$HOME/.local/share/fnm/aliases" ]; then
       # shellcheck disable=SC2153  (alias dir is a dir of version symlinks)
       export PATH="$HOME/.local/share/fnm/aliases/default/bin:$PATH"  # dedup-guarded
   fi
   ```

   …guarded with the repo's canonical `case ":$PATH:"` dedup idiom, and
   existence-gated like the nvim clipboard guard so machines without fnm
   skip silently. SDKMAN block untouched.

## `setup.sh` integration

All new code follows existing idioms (`info/warn/error`, `FAILURES+=`,
`ensure_tool`, static-binary fallback shape of `install_age_binary`, arch
`case "$(uname -m)"`, bash-3.2-safe). Install tier: direnv is a **hard**
requirement (the stow package is useless without it); uv/fnm/sdkman are
best-effort (`FAILURES`, not fatal).

- **direnv**: added to platform package lists (brew / apk / apt / pkg). Debian
  stable ships 2.32.1 (2022) — acceptable; version parity not required for
  our stdlib usage (no `watch_dir`, no `use_flox`). Static fallback in
  `post_install_checks` mirrors `install_age_binary`: single binary asset
  `direnv.<os>-<arch>` from GitHub releases to `~/.local/bin` (pinned), for
  the day a platform lacks the package.
- **uv** (macOS/Linux/WSL only): standalone installer
  `curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh` —
  the env var is mandatory; without it the installer appends PATH lines to
  shell RCs, which are our stowed symlinks (dirty-tree hazard). Skipped on
  BSD.
- **fnm** (macOS/Linux/WSL only): GitHub release zips to `~/.local/bin` —
  `fnm-macos.zip` is a universal (x86_64+aarch64) binary; `fnm-linux.zip`
  (x86_64) and `fnm-arm64.zip` (aarch64) are static musl, run on Alpine and
  glibc alike. Unzip to a temp dir, `install -m 0755`. Skipped on BSD.
- **sdkman** (macOS/Linux/WSL only): dedicated `install_sdkman()` on the
  `install_homebrew` precedent — `curl -s https://get.sdkman.io | bash`
  (non-interactive), then **immediately strip the init snippets it appends**
  to `~/.bashrc`, `~/.bash_profile`, `~/.zshrc` — those are symlinks into
  this repo and the append dirties the working tree. Our `.bashrc` already
  ships identical init lines, so the stripped duplicate changes nothing.
  Then set `sdkman_auto_answer=true` (append if absent to
  `~/.sdkman/etc/config`). Non-fatal on failure. Skipped on BSD.

## `verify.sh` additions

New `# --- direnv/runtimes ---` section after secrets, existing primitives
(`pass`/`fail`), top-level blocks (not new functions):

1. `direnv installed` — `command -v` soft check (the direnv package ships).
2. `.bashrc` hook present **and ordered after trueline** — grep line numbers
   for the hook vs. the trueline source, fail if hook ≤ trueline.
3. `direnvrc` deployed with `use_runtimes` defined — content check
   (symlink existence is already covered by `check_symlinks` auto-discovery).
4. `~/bin/runtimes` executable (symlink covered by `check_symlinks`; add
   `-x` content check).
5. uv/fnm/sdkman — soft `command -v` checks, phrased as info-grade (BSD
   tier legitimately lacks them).

## Lint & gate coverage (closing the extensionless-shim gap)

Today `common/bin/bin/*` escapes **both** shellcheck gates (`just lint` finds
`scripts/*.sh` + `.bash*`/`.profile` dotfiles; `.githooks/pre-commit` matches
the same shapes). The new `runtimes` shim and `direnvrc` must be covered:

- `Justfile` lint: add a third `find` for `common/bin/bin/*` and
  `common/direnv/.config/direnv/*` (runtimes, direnvrc, direnv.toml is not
  shell — file list stays explicit).
- `.githooks/pre-commit`: add case arms `common/bin/bin/*` and
  `*/direnvrc)`.
- Both keep `-e SC1090,SC1091` (SC2148 stays only in lint).
- `.editorconfig`: add `[common/bin/bin/*]` + `[common/direnv/.config/direnv/*]`
  sections, `indent_style = space`, `indent_size = 4`.

## Docs

Per the new convention (loadavg/tmux-copy precedent):

- `docs/dots-runtimes.md` — CLI reference mirror of `runtimes` (subcommands,
  backends, lock file, platform support matrix), plus `docs/man/runtimes.1`
  roff source; both lint-clean under `just man-check`.
- `docs/direnv-runtimes.md` — feature guide: authoring `.envrc` +
  `.runtimesrc`, the tree-stacking semantics, templates, troubleshooting
  (`direnv allow` after edits, reload-at-next-prompt behavior).
- `README.md`: Layout tree line for `common/direnv/` + `templates/`, one
  feature section under Usage.
- `CLAUDE.md`: tree line for the new package + templates dir.

## Security & safety

- Never commit machine-local direnv state: allow-lists
  (`~/.local/share/direnv/allow`) are per-machine trust records, hashed on
  `.envrc` content — documented as a per-project user step, not shipped.
- No secrets in `.envrc`/`.runtimesrc` fixtures; `.gitignore` already covers
  nothing here (`.env.*` does not match `.envrc`) — example files in docs
  use placeholder values only.
- Runtime store and log paths stay clear of `keys.txt`/`*.key`/`id_*`
  gitignore patterns (they do).
- `set -euo pipefail` discipline in the shim; `runtimes ensure` always exits
  0 on "install kicked off in background" so evaluation never breaks.

## Risks / open items

- Debian apt's direnv 2.32.1 — our direnvrc must stick to stdlib present in
  2.32 (`source_up_if_exists` is old; `watch_dir` is not used).
- fnm has no arm64-musl node builds (unofficial-builds mirror) — Alpine
  aarch64 node is a documented gap, clear error message.
- uv/fnm release-cadence churn — pin installers loosely (latest stable),
  constrain CLI usage to the stable surface (`python install/find/list`,
  `venv`).
- sdkman's `current` symlink and `JAVA_HOME` export in interactive shells
  remain as-is (global default); per-project overrides come only from direnv.