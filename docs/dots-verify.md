# dots-verify(1)

## Name

dots-verify — check the health of a deployed dots configuration

## Synopsis

```
dots-verify [--quiet]
```

## Description

`dots-verify` inspects the current machine against the contents of the dots
repository and prints one pass or failure per check. It is strictly read-only:
it changes nothing, so it is safe to run at any time.

The repository root is derived from the script's own location — the parent of
the directory containing `verify.sh` — so the same copy works when invoked
directly from a clone or through `just verify`. The platform directory is selected from `uname -s`: `Darwin` maps to
`macos`, `Linux` maps to `linux`, and any `*BSD` name maps to `bsd`. Any other
value is used verbatim as the platform name.

The script is written for the bash 3.2 that ships with macOS (no associative
arrays; the secrets target mapping is a `case` statement), and runs under
`set -euo pipefail`, so a failing command aborts it.

Five groups of checks are run, in this order:

### Required tools

`age`, `stow`, and `git` must each be found on `PATH`. One pass or failure
line is printed per tool.

### Symlinks: common and Symlinks: <platform>

Every regular file in each Stow package under `common/` and `<platform>/` must
be deployed at the same path relative to `$HOME` (e.g. `common/bash/.bashrc`
must appear as `~/.bashrc`). For each file the script requires that the target
exists, is a symlink, and resolves to the repository file — relative symlink
targets are converted to absolute paths before comparison. Failure messages
distinguish three cases:

- the target exists but is not a symlink
- the target is missing entirely
- the symlink points somewhere other than the repository (the message shows
  the resolved actual target next to the expected one)

If a package base directory does not exist, that whole group is skipped
silently. The directory walk excludes files named `*~`, `#*#`, `.git*`, and
`.DS_Store`. Those four names are a pragmatic approximation of GNU Stow's
default ignore list, not a match of it. The `*~` and `#*#` entries agree with
Stow — its built-in list ignores every name ending in `~` and every `#...#`
autosave file — but the other two diverge from Stow's behavior in both
directions, and one divergence bites today.

Stow's defaults ignore only the exact names `.git`, `.gitignore`, and
`.gitmodules` (along with `.cvsignore`, RCS, CVS, `.svn`, `.hg`, and `_darcs`),
not `.git*` in general. Any other `.git*` name — `.gitignore_global`,
`.github`, and so on — is deployed when a package is stowed, while the walk
skips it, so a broken or missing symlink for such a file goes unreported. This
does bite in this repository: `common/git/.gitignore_global` exists and gets
stowed to `~/.gitignore_global`, but the `.git*` exclusion keeps it out of the
walk, so `verify.sh` can never report a broken or missing `~/.gitignore_global`
symlink. `.DS_Store`, meanwhile, is not in Stow 2.4.1's built-in list at all,
so Stow would deploy one while the walk skips it — also unreported, though no
such file exists in this repository's packages today.

In the other direction, a top-level `README*`, `LICENSE*`, or `COPYING` in a
package is walked here even though Stow's path-anchored default ignores keep
it from being deployed, so a missing symlink for one would be reported
although Stow never created it. None of those exist in this repository's
packages either.

Note the coverage: only `common/` and `<platform>/` are walked.
`dots-setup(1)` additionally stows the `alpine/` layer under Alpine and the
`wsl/` layer under WSL; packages in those two layers are deployed to `$HOME`
but are **not** inspected by these symlink checks.

### File permissions

The `~/.ssh` directory must have mode `700`, and every regular file directly
inside it whose name matches `id_*` but not `*.pub` must have mode `600`. If
`~/.ssh` does not exist, a single failure is reported. Modes are read with GNU
`stat -c '%a'`, falling back to the BSD/macOS `stat -f '%Lp'` on platforms
that lack the GNU form.

### Decrypted secrets

Every `*.age` file under `secrets/` must have its plaintext counterpart
present. Passphrase fallback copies named `*.phrase.age` are skipped: they
exist only as vault copies of the corresponding `.age` file (see
[README](../README.md) for the dual-artifact scheme) and have no deployed
target of their own. The first path component below `secrets/` selects the
target directory — `ssh` → `~/.ssh`, `tokens` → `~/.config/tokens` — the
`.age` suffix is stripped from the filename, and the resulting path must exist
as a regular file there. An unmapped subdirectory is reported as a failure
("No target mapping for ...").

If the walk yields no secrets to check, a note reading
`(no .age files found)` is printed. The trigger is a counter of
non-passphrase `.age` files that is still zero when the walk ends —
`*.phrase.age` copies are skipped before it is incremented — so the note
appears both when `secrets/` is missing or holds no `.age` files at all and
when the tree holds nothing but `*.phrase.age` fallback copies. The wording
is a little loose in the second case (`.age` files do exist there), but the
note still reads `(no .age files found)`. It is informational and does not
count as a failure.

### direnv + runtimes

Seven checks covering the [direnv + runtimes
integration](direnv-runtimes.md):

- `direnv` on `PATH` — soft: `dots-setup(1)` installs it as a hard
  requirement, but `dots-verify` can legitimately run pre-bootstrap, so
  absence is reported (`direnv not found (soft check; setup.sh installs
  it)`), not failed.
- The direnv hook in `~/.bashrc` — hard: a missing `~/.bashrc`, a missing
  hook line (`direnv hook missing from …`), or a missing trueline source
  (`trueline source missing from … (cannot confirm hook order)`) fails.
  The hook must sit on a **later line** than the trueline source —
  trueline replaces `PROMPT_COMMAND` without chaining, silently discarding
  a hook placed before it — so a hook at or above the trueline line also
  fails, with both line numbers in the message.
- The repo's `common/direnv/.config/direnv/direnvrc` exists and defines
  `use_runtimes` — hard; the symlink deployment of that file is already
  covered by the symlink walk.
- `~/bin/runtimes` exists and is executable — hard (the executable bit
  lives on the repo file, tested through the deployed symlink).
- `uv` and `fnm` on `PATH` — soft (`<tool> not found (optional)`): they
  are best-effort installs and the BSD tier legitimately ships without
  them.
- sdkman — soft: installed when either `sdk` is on `PATH` or
  `~/.sdkman/` exists (the installer's `sdk` function is only loaded in
  interactive shells, so the install dir is the reliable presence signal).

## Options

- `--quiet` — suppress per-check output: the `==>` section banners, the green
  pass / red fail marks, and the `(no .age files found)` note. The final
  summary line is still printed, counters are still tallied, and the exit
  status is unaffected. `--quiet` is only recognized as the first argument;
  every other argument is ignored. There is no `--help` option.

## Environment

- `HOME` — base for all deployed targets: the symlink checks compare against
  `$HOME/<relative path>`, and the permissions and secrets checks inspect
  `~/.ssh` and `~/.config/tokens`.
- `REPO_DIR` — set by the script to the repository root (parent of the
  script's directory) and exported to child processes.
- `PATH` — searched when checking that `age`, `stow`, and `git` are
  installed, and for the soft `direnv`, `uv`, and `fnm` presence checks.

## Exit status

- `0` — every check passed.
- `1` — at least one check failed. A non-zero status can also result from the
  script aborting under `set -e`.

## Files

- `scripts/verify.sh` — the script itself; its location determines the
  repository root.
- `common/*/`, `<platform>/*/` — Stow packages whose contents are checked
  against `$HOME`.
- `secrets/*/*.age` — encrypted secrets checked for a decrypted counterpart.
- `~/.bashrc` — checked for the direnv hook, ordered after the trueline
  source.
- `common/direnv/.config/direnv/direnvrc` — content-checked for the
  `use_runtimes` helper.
- `~/bin/runtimes` — checked for existence and the executable bit.
- `~/.ssh` — checked for mode `700`, and for private keys matching `id_*`
  (not `*.pub`) with mode `600`.
- `~/.config/tokens` — target directory for secrets stored under
  `secrets/tokens/`.

## Intended usage

`dots-verify` is the read-only health check of the four sibling scripts: it
asks "is this machine deployed correctly?" without touching anything. It
answers the question you get after a `git pull` on an established machine
(run `just restow` via [dots-setup(1)](dots-setup.md) and then confirm nothing
is stale), after a fresh bootstrap, and before committing changes that alter
Stow packages or secret layout.

`dots-setup(1)` runs it via its `--verify` flag, falling back to `bash
verify.sh` if the script lost its executable bit; a full bootstrap does not
invoke it, so run `dots-setup --verify` (or `just verify`) after one to check
the result. The `just verify` recipe calls it directly. Its checks mirror what the other
scripts establish: the tool checks cover what `dots-setup(1)` installs, the
symlink checks cover what `dots-setup(1)` stows from `common/` and the
platform directory (and what [stow adopt](stow-adopt-workflow.md) folded
into the repo) — the `alpine/` and `wsl/` layers setup also stows are not
walked — the direnv + runtimes checks cover the hook placement the stowed
`.bashrc` ships, the direnvrc helpers and the `~/bin/runtimes` shim (with
soft presence for the best-effort backends), the permission
checks cover what `dots-decrypt(1)` enforces on private keys, and the
decrypted-secrets checks cover what `dots-decrypt(1)` produced from the
artifacts `dots-encrypt(1)` created.

Reach for it whenever you want a diff of reality against the repo — symlink
drift, wrong permissions on SSH keys, a secret that failed to decrypt
(broken key material or a wrong passphrase) shows up as "expected
`~/.ssh/...` (not found)". Because it is quiet and exit-status-driven under
`--quiet`, it also works as a gate in a hook or CI job.

## Examples

Check the current deployment and print every result:

```bash
./scripts/verify.sh
```

The same, from anywhere:

```bash
just verify
```

Use it as a quiet gate, acting only on the exit status:

```bash
./scripts/verify.sh --quiet || echo "deployment unhealthy"
```

After a `git pull`, re-stow first and then confirm nothing drifted:

```bash
just restow && just verify
```

## See also

[dots-setup(1)](dots-setup.md) · [dots-encrypt(1)](dots-encrypt.md) ·
[dots-decrypt(1)](dots-decrypt.md) · [stow adopt workflow](stow-adopt-workflow.md)