# trash(1)

[manpage](man/trash.1) · alternative to `rm` that uses the platform trash

## Name

`trash` — move files to the platform trash instead of deleting them

## Synopsis

```
trash [OPTION]... FILE...
trash --empty-trash [-f] [--all]
```

## Description

`trash` is an `rm`-compatible front end that **moves** each operand to the
platform's trash instead of unlinking it. Operand handling, directory rules,
error reporting and option precedence follow
[rm(1)](https://man.openbsd.org/rm.1) as closely as a move can: a directory
still needs `-r`, `-d` accepts only empty directories, nonexistent operands
fail unless `-f` is given, and `.`/`..` are always refused. The difference is
that the data survives in a trash directory and can usually be restored from
the file manager.

Deployed as `~/bin/trash` by [dots-setup](dots-setup.md) from
[`common/bin/bin/trash`](../common/bin/bin/trash).

### Where files go

| Platform | `auto` / `system` backend | Layout | Restore |
|---|---|---|---|
| macOS | `~/.Trash`; other volumes use `/.Trashes/<uid>` | entries directly in the directory | Finder shows the items; "Put Back" metadata is written only with `TRASH_MACOS_FINDER=1` |
| Linux | `$XDG_DATA_HOME/Trash` (default `~/.local/share/Trash`); other volumes use `/.Trash/<uid>` or `/.Trash-<uid>` | freedesktop.org layout: `files/` plus `info/*.trashinfo` | Nautilus, Dolphin, Thunar, etc. can restore, because each entry records its original path |
| BSD | `~/.trash` | entries directly in the directory | restore manually |

The `home` backend always uses `$TRASH_DIR` when set, otherwise `~/.trash`,
on every platform. `auto` picks the system facility where one exists (Linux
and macOS) and the home backend elsewhere; `system` behaves the same as
`auto` on BSD, which has no system trash.

For a target on a different filesystem, Linux and macOS try the volume's own
trash first, so the move stays a rename and the item can be restored in
place. If the volume has no usable trash (read-only, unsupported filesystem,
or the `home` backend was forced), `trash` copies the tree and then removes
the original. Name collisions inside a trash directory are resolved with a
`.1`, `.2`, … suffix; the `.trashinfo` name is kept in step with the entry.

### Safety guards

These are checked before anything moves; they apply even with `-f`:

- `.` and `..` are refused as the final path component (the same rule as
  `rm`).
- `/` is refused. Unlike `rm --no-preserve-root`, it cannot be overridden:
  every trash directory is inside `/`, so moving (or, worse, copying and
  deleting) the root filesystem is never attempted. The flag is accepted for
  command-line compatibility only.
- A path that contains the trash directory is refused — `$HOME`, an XDG data
  parent such as `~/.local`, or a mount point whose per-volume trash lives
  inside it. This is what makes `trash -r ~` fail instead of creating a
  recursion.
- A directory that is itself a mount point is refused (`rm` reports the same
  case as "Device or resource busy"). Renaming a mount point is impossible,
  and attempting the copy fallback could duplicate an entire filesystem.

### Prompts and option precedence

`-i` prompts once per operand (a whole directory moves atomically, so there
is no per-file "descend" prompt). A declined prompt is not an error; the
command exits 0, matching `rm -i`. A path that is not writable also gets a
one-off prompt when stdin is a terminal and neither `-f` nor an explicit
`--interactive` option was given.

`-I` asks once before moving more than three operands, or before a recursive
directory operand.

`-f` and `-i` are applied left to right, so the last one controls prompting
(`-fi` prompts, `-if` does not). As with GNU `rm`, `-f` keeps its other
effect regardless of order: nonexistent operands stay silent.

## Options

| Option | Meaning |
|---|---|
| `-f`, `--force` | Ignore nonexistent operands and never prompt. |
| `-i`, `--interactive` | Prompt before every move. |
| `-I` | Prompt once before more than three operands, or a recursive directory. |
| `--interactive=WHEN` | `never`, `once`, or `always`; `never` also skips the `--empty-trash` confirmation. |
| `-r`, `-R`, `--recursive` | Move directories and their contents. |
| `-d`, `--dir` | Move empty directories; a non-empty directory is still an error. |
| `-v`, `--verbose` | Print `trashed 'FILE' -> 'DEST'` for each move and a count for each emptied trash. |
| `--backend=WHEN` | `auto` (default), `system`, or `home`. |
| `--empty-trash` | Empty the trash; lists the locations and asks for confirmation. |
| `--all` | With `--empty-trash`, also empty per-volume trashes. |
| `--preserve-root` | Refuse `/` (the default). |
| `--no-preserve-root` | Accepted for `rm` compatibility; `/` is still refused. |
| `--help` | Print usage and exit. |
| `--version` | Print the version and exit. |

Unknown options, including `rm` flags that have no meaning for a move
(`-x`, `--one-file-system`), are rejected rather than silently ignored.

## Emptying the trash

`trash --empty-trash` prints every location it is about to clear, then asks
`Are you sure? [y/N]` on stderr and reads the answer from stdin. With the
default `auto` backend it clears the system trash **and** `~/.trash` if that
directory has anything in it (either may have been used by this tool);
`--backend=system` limits it to the system trash, `--backend=home` to the
home trash.

`--all` adds per-volume trashes: `/Volumes/*/.Trashes/<uid>` on macOS, and on
Linux the `.Trash-<uid>`, `.Trash/<uid>` and `.Trashes/<uid>` directories of
mounted filesystems listed in `/proc/mounts`. Pseudo-filesystems and network
or generic FUSE mounts (NFS, CIFS/SMB, SSHFS, AFS, 9P) are skipped, only
existing directories are considered, and other users' trashes are never
touched.

The confirmation needs a terminal. Without one, the command refuses and
exits 1 unless `-f` (or `--interactive=never`) was given, which skips the
question. Decline the prompt and the exit status is 1 with nothing deleted;
an already-empty trash is reported and exits 0.

## Environment

| Variable | Effect | Default |
|---|---|---|
| `TRASH_DIR` | Location used by the `home` backend (a leading `~/` is expanded) | `~/.trash` |
| `XDG_DATA_HOME` | Parent of the Linux home trash (`…/Trash`) | `~/.local/share` |
| `TRASH_MACOS_FINDER` | `1` moves through Finder, which records "Put Back" metadata; GUI session only, falls back to a direct move | unset (direct move) |

## Exit status

| Code | Meaning |
|---|---|
| 0 | Every operand moved (or deliberately skipped by `-i`/`-I`), or the trash was already empty. |
| 1 | Usage error, at least one operand could not be moved, or `--empty-trash` was declined/interrupted or a deletion failed. |

## Files

- `$XDG_DATA_HOME/Trash/files/`, `$XDG_DATA_HOME/Trash/info/` — Linux home
  trash entries and their `.trashinfo` metadata.
- `<mount>/.Trash/<uid>`, `<mount>/.Trash-<uid>` — Linux per-volume trashes.
- `~/.Trash`, `<mount>/.Trashes/<uid>` — macOS trashes.
- `$TRASH_DIR`, `~/.trash` — home backend.

## Intended usage

Use `trash` wherever losing the data would be annoying: exploratory
deletions, cleaning a build tree you may need again, or replacing `rm` in
interactive shells. A common setup is an alias in your shell config:

```sh
alias rm='trash'
```

Scripts are unaffected by interactive aliases, so `command rm` and
`/bin/rm` still make deletions permanent. To make a deletion irreversible,
empty the trash explicitly — there is deliberately no `--restore` here,
because Linux file managers already restore from the `.trashinfo` records and
macOS Finder owns the Trash UI. Prefer the `home` backend when you want a
single, portable directory (for example on a shared or synced home), and the
system backend when you want file-manager integration.

## Examples

Move one file and one directory:

```sh
trash notes.txt
trash -r build/
```

Prompt before each of a glob, like `rm -i`:

```sh
trash -i *.tmp
```

Move an empty directory without `-r`:

```sh
trash -d empty-dir
```

Show where everything went:

```sh
trash -v old-*.log
```

Use a single portable trash directory regardless of platform:

```sh
TRASH_DIR=~/trash-bin trash --backend=home report.pdf
```

Empty the home and per-volume trashes without the question:

```sh
trash --empty-trash --all -f
```
