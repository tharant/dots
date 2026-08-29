# loadavg(1)

## Name

**loadavg** — one-line load average for the tmux status bar

## Synopsis

```
loadavg
```

Deployed as `~/bin/loadavg` by [dots-setup(1)](dots-setup.md) from
[`common/bin/bin/loadavg`](../common/bin/bin/loadavg).

## Description

Prints the 1, 5 and 15-minute load averages on a single line, space-separated,
with no decoration. It exists for tmux's status bar: the status segment in
`.tmux.conf` invokes it as `#($HOME/bin/loadavg)` and supplies all color,
spacing and labels itself, while this script supplies only the three numbers.

It takes no options and reads no input; a status-line refresh simply runs it
once per interval.

## Files

- `/proc/loadavg` — primary source on Linux, including WSL2 and OrbStack: the
  first three fields are printed verbatim.
- `sysctl -n vm.loadavg` — used everywhere else (macOS, FreeBSD). Darwin and
  BSD wrap the value in braces (like `( 1.00 0.50 0.25 )`), so the awk program
  prints fields 2 through 4.

## Exit status

0 on success. Any shell error (missing `awk`, neither `/proc/loadavg` nor
`sysctl` available) leaves the status segment empty for that refresh; with
`set -u` in effect an unexpected unset variable aborts with status 2.

## Intended usage

`loadavg` and its sibling [tmux-copy(1)](tmux-copy.md) are the two shims in
`common/bin/bin/`, deployed to `~/bin/` by
[dots-setup(1)](dots-setup.md). They exist so that a single,
platform-free `.tmux.conf` can contain status-line functions that would
otherwise need per-platform variants — the platform-specific part (reading
the load on Linux vs. macOS, reaching the clipboard on Wayland vs. WSL2) is
isolated in the shim in `common/bin/` instead.

If you add another script that a config file must invoke, follow the same
pattern and its documentation contract: a shell shim in `common/bin/bin/`,
documented as a manpage pair (see the documentation contract section in
[CLAUDE.md](../CLAUDE.md)).

## Examples

What it writes (with colors supplied by `.tmux.conf`):

```
$ ~/bin/loadavg
0.72 0.55 0.48
```

The tmux status segment that consumes it (unchanged across all platforms,
because the shim absorbs the differences):

```
set-option -g status-right '#[fg=colour8,bg=black]#[fg=white,bg=colour8] #($HOME/bin/loadavg) ...'
```