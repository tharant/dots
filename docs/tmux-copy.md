# tmux-copy(1)

## Name

**tmux-copy** — copy stdin to the best available clipboard

## Synopsis

```
command | tmux-copy
```

Deployed as `~/bin/tmux-copy` by [dots-setup(1)](dots-setup.md) from
[`common/bin/bin/tmux-copy`](../common/bin/bin/tmux-copy).

## Description

Reads all of stdin and hands it to the first working clipboard mechanism.
Detection is by capability, not by platform — one unmodified copy works on
macOS, Linux, WSL2 and SSH hosts — and a candidate that fails (non-zero exit)
is simply skipped in favor of the next one:

| Order | Candidate | Where it applies |
| --- | --- | --- |
| 1 | `pbcopy` | macOS |
| 2 | `clip.exe` | WSL2 — run by absolute path `/mnt/c/Windows/System32/clip.exe`, and only when `/proc/version` says this is really a Microsoft-hosted kernel (a cross-mounted `/mnt/c` on bare-metal Linux does not count) |
| 3 | `wl-copy` | Wayland |
| 4 | `xclip` (CLIPBOARD selection) | X11 |
| 5 | OSC 52 fallback | no clipboard tool at all |

The fallback base64-encodes the data (busybox-compatible `base64`) and emits
an OSC 52 escape with the `c` clipboard selector and a BEL terminator, so
capable terminals still receive the copy even over ssh — in tmux this needs
`set-clipboard external` and `allow-passthrough on`, which `.tmux.conf`
already sets.

The clipboard helpers' output is not captured; they are silent on success and
their exit status is what decides fall-through.

Empty input skips every candidate (all are guarded by a non-empty check) and
falls through to the OSC 52 emission, which then transmits an empty payload.

## Exit status

0 in practice: every code path ends successfully, because the final fallback
is a plain `printf` that always succeeds, even with no clipboard tool
present. A failing clipboard candidate never aborts the script; its non-zero
status merely triggers the next candidate in line.

## Intended usage

`tmux-copy` exists so that `.tmux.conf` can yank into the *terminal client's*
native clipboard on every blessed platform with one binding — no per-platform
copy-command variants. `.tmux.conf` binds copy-mode `y` and `Enter` to
`copy-pipe-and-cancel "tmux-copy"`, so it is normally invoked by tmux, not
typed.

`clip-copy`, the shell function in
[`.bash_functions`](../common/bash/.bash_functions) deployed by
[dots-setup(1)](dots-setup.md), walks the *same detection ladder* but is
deliberately different in two ways: it is a shell function (working only in
interactive shells, not from tmux's `copy-pipe`), and it **fails with a
message when no clipboard tool exists** rather than falling back to OSC 52 —
typing a command that reports a missing tool is more useful than a silent
escape sequence a terminal may or may not honor. `tmux-copy` and
[loadavg(1)](loadavg.md) are the two shims in `common/bin/bin/`, following
the documentation contract in [CLAUDE.md](../CLAUDE.md).

## Examples

Yank in tmux (the normal path): in copy-mode select lines and press `y` —
`.tmux.conf` already pipes the selection through `tmux-copy`, and the yanked
text lands on the clipboard of the machine running the terminal.

From a shell:

```
$ printf 'hello clipboard' | tmux-copy
$ tail -n 100 /etc/apt/sources.list | tmux-copy
```

Over SSH with a capable terminal and no remote clipboard tools, the OSC 52
fallback runs and the local terminal interprets the escape — the copy lands
in your local clipboard.