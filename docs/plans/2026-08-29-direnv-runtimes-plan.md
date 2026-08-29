# direnv + runtimes: implementation plan

**Design:** `docs/plans/2026-08-29-direnv-runtimes-design.md` (same directory)
**Branch:** `direnv` (worktree `dots-direnv`, based on `origin/main` @ `d3f8b08`)

Tasks are partitioned by file ownership — no two tasks write the same file —
so they can run in parallel. Every task ends with: `just lint` clean (with the
new coverage), `shellcheck` clean on its own files, `bash -n` under
`/bin/bash` 3.2 where applicable, and one commit on `direnv`.

## T1 — `common/direnv` stow package

Files: `common/direnv/.config/direnv/direnvrc`, `common/direnv/.config/direnv/direnv.toml`, `common/direnv/.envrc`

- `direnvrc`: `use_runtimes`, `use_runtime`, `use_python`, `use_node`,
  `use_java`, `use_template` per design contract; bash-3.2-safe; output only
  via `log_status`/`log_error`; `watch_file` on `.runtimesrc` + `.runtimes.lock`.
- `direnv.toml`: `warn_timeout = "10s"` only.
- `.envrc` starter: comment-only, documents the `source_up_if_exists` chain.
- Verify: `stow -d common -t "$HOME" --no-folding -n direnv` dry-run clean
  (in a sandbox `HOME`, not the real one); shellcheck via the new lint paths.
- Commit: `direnv: stow package with direnvrc helpers and .envrc starter`

## T2 — `runtimes` shim

Files: `common/bin/bin/runtimes` (executable bit!)

- CLI per design contract: `ensure`, `install`, `status`, `path`, `template`;
  subcommand help; `info/warn/die` to stderr; stdout reserved for `path`.
- Backends: python→uv (`python install/find`, `UV_NO_PROJECT=1`), node→fnm
  (`ls-remote` resolution, `node-versions/vX.Y.Z/installation` layout,
  musl mirror workaround), java→sdkman (API version listing, exact candidate
  IDs, `sdkman_auto_answer`).
- Atomicity: staging dirs + `mv`; background installs via `nohup` with log to
  `~/.local/state/runtimes/logs/`; single-flight guard; lock write is
  temp-file + rename.
- BSD guard: auto-install refused with a clear message, `command -v`
  fallback, exit 0.
- Verify: `shellcheck -s bash common/bin/bin/runtimes`; `/bin/bash -n`;
  smoke-run `runtimes -h`, `runtimes status` on this Mac.
- Commit: `runtimes: cross-platform runtime manager shim (uv/fnm/sdkman)`

## T3 — `.bashrc` integration

Files: `common/bash/.bashrc` only.

- Move guarded direnv hook after the trueline block (dead-hook fix), keep
  SDKMAN tail last (comment preserved verbatim).
- Replace NVM block with the alias-based fnm default exposure (dedup-guarded,
  existence-gated).
- Verify: source the file under `bash --norc -i` sandbox; confirm
  `PROMPT_COMMAND` contains `_direnv_hook` *after* `_trueline_prompt_command`;
  shellcheck clean.
- Commit: `bashrc: revive direnv hook after trueline; fnm replaces nvm`

## T4 — `setup.sh` installers

Files: `scripts/setup.sh` only.

- `install_direnv` (pkg lists + static fallback), `install_uv`
  (`UV_NO_MODIFY_PATH=1`), `install_fnm` (release zips, universal macos),
  `install_sdkman` (curl installer + snippet strip from
  `~/.bashrc`/`.bash_profile`/`.zshrc` + `sdkman_auto_answer=true`).
- Tiering: direnv hard, others best-effort `FAILURES`; all skipped on BSD
  except direnv.
- Verify: `bash -n` under `/bin/bash`; shellcheck clean; `--help` output
  unchanged otherwise.
- Commit: `setup.sh: install direnv, uv, fnm, sdkman (tiered, BSD-aware)`

## T5 — `verify.sh` checks

Files: `scripts/verify.sh` only.

- `# --- direnv/runtimes ---` section per design: direnv presence, hook
  order-after-trueline check, direnvrc content check, shim executable check,
  soft uv/fnm/sdkman checks.
- Verify: run against a sandbox `$HOME` (both pass and fail cases).
- Commit: `verify.sh: direnv + runtimes health checks`

## T6 — gates, templates

Files: `Justfile` (lint recipe + new recipes), `.githooks/pre-commit`,
`.editorconfig`, `templates/*`.

- Lint coverage: `common/bin/bin/*` + `*/direnvrc` in both lint and pre-commit.
- `.editorconfig` sections for shim + direnvrc paths.
- `templates/example/` + manifest to prove `use_template`/`runtimes template`.
- Justfile recipes: `runtimes CMD='*'` passthrough (new `# --- Runtimes ---`
  section, one-line comments, existing style).
- Verify: `just lint` now includes and passes the shim; `just man-check`
  unaffected.
- Commit: `lint/gates: cover shims + direnvrc; templates dir; just recipes`

## T7 — docs (runs after T1–T6)

Files: `docs/dots-runtimes.md`, `docs/man/runtimes.1`,
`docs/direnv-runtimes.md`, `README.md`, `CLAUDE.md`.

- Per-tool doc mirror + roff page (man-check clean), feature guide, README
  Layout lines + feature section, CLAUDE.md tree line.
- Commit: `docs: runtimes CLI reference, direnv feature guide, README/CLAUDE updates`

## Cross-cutting

- Nothing in this plan touches the shared checkout at
  `~/development/personal/dots` — all work in the `dots-direnv` worktree.
- Final gate before PR: `just lint`, `just verify` (sandboxed), `just
  man-check`, plus a review workflow over the full branch diff
  (bash-3.2 audit, portability audit, adversarial correctness pass).