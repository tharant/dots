# Stow packages in mixed config+cache dotfiles

Some tool dotdirs keep real config and machine-local churn in the same place —
`~/.sbt` (config file + hundreds of MB of `boot/` and `java9-rt-ext-*` caches),
`~/.ivy2`, and many others. This repo's policy for them: **track config leaves
only, let caches accumulate in place**.

## The rule: leaf files only

A stow package for a mixed dotdir may contain **regular files at exact `$HOME`
paths, never directories a tool mutates at runtime** — not even empty ones.

Example — `common/sbt`:

```
common/sbt/.sbt/repositories      # config leaf (symlinked into ~/.sbt/)
```

Never add to a package:

- `boot/`, `staging/`, `cache/`, `java9-rt-ext-*/` — tool caches
- files the tool rewrites (locks, state files, registries) — packaging them
  means every run of the tool dirties git or the symlinked file
- anything machine-specific (a `~/.sbt` on one machine may reference paths that
  only exist there)

## Why this works without extra machinery

Every stow invocation in `setup.sh` runs with `--no-folding`
(`scripts/setup.sh:1063,1071`):

- Stow never replaces the `$HOME` dotdir with a symlink to the package — the
  real directory stays a real directory.
- Tracked config files deploy as **leaf symlinks inside it**.
- Everything the tool creates at runtime lands beside them as real files and
  dirs — invisible to git, and invisible to `verify.sh`, which only checks
  targets corresponding to repo files
  (`scripts/verify.sh` `check_symlinks`: extra non-symlink entries in a stowed
  dotdir never fail).

So the repo carries zero cache weight and the dotdir behaves identically to the
un-managed case for everything sbt (or ivy, or any tool) scatters into it.

## Adoption rules (`setup.sh --adopt`)

Filling a skeleton package from a machine that carries real config is the
standard [adopt workflow](stow-adopt-workflow.md), with two mixed-dir
protections already built in:

- `backup_stow_conflicts` (`scripts/setup.sh:1019-1043`) moves pre-existing
  plain **files** at stow target paths into `~/.dots-backup-<timestamp>/`
  before adopting — content is never destroyed.
- Directories are refused: the pre-adoption backup and stow itself both refuse
  on a directory occupying a target path, so a cache tree can never be swept
  into the repo by an over-eager adopt. Caches stay home by construction.

Adopt is run **on the machine that has the config** (this repo is identical
everywhere; machines with more tooling contribute their config back):

```bash
git pull && ./scripts/setup.sh --adopt   # there, not on cache-only machines
```

## Placement of tracked leaves

Package choice follows the existing per-tool convention: one package per tool
(`common/sbt`, `common/ivy2`, …), layout mirroring `$HOME`. If a tracked leaf
belongs conceptually to shell startup (env exports, variables like
`SDKMAN_DIR` in `common/bash/.bashrc`), it goes there — not inside the tool
package.

## Gitignore exemptions

Belt-and-braces: any path a tool writes at runtime *inside a package path* gets
an explicit `.gitignore` entry so accidental stashing of cache into the package
still can't be committed. The precedent is
`common/vim/.vim/.theme` (theme choice is written at runtime through the stow
symlink and is per-machine); sbt/ivy2 cache paths are listed the same way.

## Accidental adopt of the wrong thing

If a cache path ever does get adopted into the repo:

```bash
git rm -r --cached common/sbt/.sbt/boot
unstow + restow or delete the package path
mv the real cache back into ~/.sbt
```

The `.gitignore` section above is the tripwire — the cache dir will show as
untracked, not silently committed, if it ever lands in the package.

## Related

- [dots-setup(1)](dots-setup.md) — bootstrap, restow, adopt, unstow
- [dots-verify(1)](dots-verify.md) — what symlink checks do and don't see
- [stow adopt workflow](stow-adopt-workflow.md) — manual adopt walkthrough