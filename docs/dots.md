# dots(1)

## Name

`dots` — orchestration CLI for the dots dotfiles repo

## Synopsis

```
dots <command> [args...]
```

## Description

`dots` is the machine-side entry point for the repo, installed as `~/bin/dots`
by stow (source: `common/bin/bin/dots`). It delegates every existing operation
one-for-one to `scripts/*.sh` and the `docs/man` Makefile, mirrors the two
read-only `just` recipes (`status`, `list-packages`), and adds two composed
commands, `sync` and `commit`.

It is strictly an orchestrator: stow invocation, age encryption, and git
operations are sequenced and gated here, never re-implemented. All human
output goes to standard error; standard output is reserved for command
payloads.

The repo checkout is resolved from the path of the `dots` binary itself
(symlinks are followed without `readlink -f`, so the stowed `~/bin/dots` and a
checkout invocation of `common/bin/bin/dots` behave identically), and
`DOTS_DIR` is exported to that tree before delegating, so the scripts act on
the same checkout the command was resolved from rather than the default
`~/.dots`. Like [runtimes(1)](runtimes.md), it is portable bash — no
associative arrays, no `mapfile`, no `read -i` — written to run under macOS
`/bin/bash` 3.2 as well as any interactive bash.

## Commands

Delegating commands `exec` the matching script and take its exit status; their
options and diagnostics are those of the target script.

| Command | Runs | Notes |
|---|---|---|
| `setup` | `scripts/setup.sh` | full bootstrap — [dots-setup(1)](dots-setup.md) |
| `restow` | `scripts/setup.sh --restow` | |
| `adopt` | `scripts/setup.sh --adopt` | wholesale adopt; for per-file adoption use `dots commit` |
| `unstow` | `scripts/setup.sh --unstow` | |
| `verify` | `scripts/verify.sh` | [dots-verify(1)](dots-verify.md) |
| `encrypt <file> [out.age]` | `scripts/encrypt.sh` | [dots-encrypt(1)](dots-encrypt.md) |
| `decrypt` | `scripts/decrypt.sh` | [dots-decrypt(1)](dots-decrypt.md) |
| `status` | stow dry-run, host's stow layers only | other platforms' packages are skipped — they collide by design with what is stowed here (e.g. `.bash_profile`), so probing them is always noise |
| `list-packages` | — | prints `base/pkg` lines; mirrors `just list-packages` |
| `packages <cmd>` | `common/bin/bin/packages <cmd>` | passthrough to the wishlist CLI (`status` / `install` / `update` / `refresh` / `add`); see [packages(1)](packages.md) |
| `man-check` / `man-install` / `man-uninstall` | `make -C docs/man <target>` | |
| `sync` | composed (below) | pull → restow → verify |
| `commit [-m <msg>]` | composed (below) | survey → plan → review → commit; **never pushes** |

### dots sync

Updates the deployment in one step: `git pull --ff-only` (with `--autostash`
when the working tree is dirty), then restow, then verify. A restow or verify
failure is reported but does not stop the later steps; the command exits
non-zero if either failed. A failed pull aborts before anything is restowed.

### dots commit

Turns "I edited my configs, now what?" into one guided commit. It never
pushes, and plaintext secrets can never pass through it.

**Survey and plan.** The tree is surveyed read-only: untracked and
worktree-modified paths (plus ignored paths, via `--ignored=matching`) minus
editor/OS/cache noise; plaintext files inside `secrets/` that are not `.age`
artifacts; files in `~/.ssh` and `~/.config/tokens` without a committed
`X.age` + `X.phrase.age` pair; and stray managed-looking files in `$HOME` that
fit an existing stow package (searched only inside package anchor
directories, never across all of `$HOME`). Paths already staged are reported
informationally — included in the commit but never re-added or reset. Where no
terminal is available, the plan is printed and the command exits 2 without
changing anything.

**Confirmation.** Each item is prompted `y/n/a/q`: `a` accepts the remainder
of its group, `q` aborts. Aborting — and any later failure — restores the
index to its pre-command state by resetting exactly the paths this command
staged; pre-existing staged entries are preserved, and nothing is ever
committed after an abort.

**Execute.** Accepted items are carried out before staging, so everything
lands in a single commit:

- *encrypt* items run `scripts/encrypt.sh --no-commit`
  ([dots-encrypt(1)](dots-encrypt.md) with its auto-commit skipped) and the
  resulting artifact pair is staged as part of the commit.
- *adopt* items are copied into the package (`cp -p`), then one scoped `stow`
  per affected package is offered so the symlinks follow. The wholesale
  `dots adopt` remains available for machines that want everything adopted at
  once; see the [stow adopt workflow](stow-adopt-workflow.md).

**Plaintext gate.** After staging, the *staged index* itself is checked — not
the worktree. Every file staged under `secrets/` must be a `.age` artifact
whose first line is the age magic (`age-encryption.org/v1`) and which has a
`.phrase.age` twin (the repo's dual-artifact invariant), with only
`recipients.txt` and trivial dotfiles exempt; and no file anywhere in the
staged tree may carry a plaintext-secret basename (`id_*`, `*.pem`, `*.key`,
`*.secret`, `.env*`, excepting `*.pub` and `.env.example`). A violation is a
hard refusal: offenders are listed and the command exits 1 with the index left
as staged, so nothing is lost by correcting it (`git reset -- <path>`).

**Review, message, commit.** `git diff --cached --stat` is shown, followed by
an optional pagered full diff. After confirmation, a commit message is
generated from the accepted items — subject `configs: <packages>; +N secrets
(<subdirs>)` with a bulleted body — written to a temporary file. The default
flow seeds the editor with it via `git commit -t` (so the default is a genuine
starting buffer; an emptied buffer aborts with the index intact); declining
the edit commits with `git commit -F`. On success a `git log -1 --stat`
summary is printed and a reminder that nothing was pushed.

## Options

- `-m <msg>` / `--message <msg>` — `commit` only: commit with the given
  message instead of the generated one. Survey, encryption gate, and diff
  review still run.

## Environment

- `DOTS_DIR` — exported as the resolved repo root before delegating, so
  `scripts/setup.sh` acts on the same checkout (overriding its `~/.dots`
  default for the child process only).
- `EDITOR` — used by `git commit -t` in `commit` (git's own default applies
  when unset).
- `DOTS_NO_COMMIT` — not set by `dots` itself; its semantics come from
  [dots-encrypt(1)](dots-encrypt.md), whose `--no-commit` flag `dots commit`
  supplies itself.

## Exit status

- `0` — the requested operation completed; for `commit`: committed, or the
  working tree was clean.
- `1` — delegated script failed; unknown command; for `commit`: any preflight
  failure (merge conflicts, aborted detached HEAD), abort, plaintext-gate
  refusal, or failed commit (e.g. the pre-commit shellcheck hook); the index
  is preserved in that state for `commit`.
- `2` — `commit` run without a TTY: the plan was printed, nothing was changed.

## Files

- `common/bin/bin/dots` — the shim; stowed to `~/bin/dots`.
- `scripts/setup.sh`, `scripts/verify.sh`, `scripts/encrypt.sh`,
  `scripts/decrypt.sh` — the delegation targets
  ([dots-setup(1)](dots-setup.md), [dots-verify(1)](dots-verify.md),
  [dots-encrypt(1)](dots-encrypt.md), [dots-decrypt(1)](dots-decrypt.md)).
- `common/bin/bin/packages` — the [packages(1)](packages.md) passthrough
  target.

## Intended usage

`dots` is the *machine* surface of the repo: the one command to reach for on
any blessed machine, sitting next to [runtimes(1)](runtimes.md) in `~/bin`.
`just` remains the *repo-developer* surface — its recipes invoke the scripts
in-place in the checkout you are editing — while `dots` resolves the checkout
from its own symlink, so the same muscle memory works whether `~/bin/dots` is
stowed or you are inside a scratch clone. The two composed commands are the
everyday loop: `dots commit` after editing or adding configs (it finds new
plaintext secrets and adopts strays for you, and it will not let a plaintext
secret into history), and `dots sync` to pull someone else's commit and get
the machine back to a verified deployment. Everything else keeps the script's
own behavior, so [dots-setup(1)](dots-setup.md), [dots-verify(1)](dots-verify.md),
[dots-encrypt(1)](dots-encrypt.md), and [dots-decrypt(1)](dots-decrypt.md)
remain the reference for what actually runs.

## Examples

Guided commit of config edits and any newly appeared secrets:

```
dots commit
```

Scripted commit with a fixed message (gates still apply):

```
dots commit -m "vim: tighten clipboard guard"
```

Pull, re-stow, and verify on a blessed machine:

```
dots sync
```

Pre-flight conflict check before a restow:

```
dots status
```

Through `just`:

```
just dots commit
just dots sync
```
Related: [packages(1)](packages.md) (the wishlist CLI behind
`dots packages <cmd>`) · [runtimes(1)](runtimes.md)
