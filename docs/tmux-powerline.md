# tmux statusline (tmux-powerline)

The primary tmux status bar is the
[erikw/tmux-powerline](https://github.com/erikw/tmux-powerline) plugin, kept
in an upstream repo rather than vendored. This page is a
reference for how the dots repo wires it up; the plugin's own
docs cover its internals.

## Name

tmux-powerline — plugin-managed tmux status bar for the dots repo

## Files

| Path | What it is |
| --- | --- |
| `~/.config/tmux-powerline/tmux-powerline/` | The plugin clone, created by [dots-setup](dots-setup.md) at the commit pinned by `TMUX_POWERLINE_PIN` in `scripts/setup.sh` |
| `~/.config/tmux-powerline/config.sh` | User config (Stowed from [`common/tmux-powerline/`](../common/tmux-powerline/.config/tmux-powerline/config.sh)): theme choice, `status-interval`, per-segment knobs |
| `~/.config/tmux-powerline/themes/dots.sh` | The repo's theme (Stowed from [`common/tmux-powerline/`](../common/tmux-powerline/.config/tmux-powerline/themes/dots.sh)) |
| `common/tmux/.tmux.conf` | The loader: guarded `run-shell` of `main.tmux` as the last line, plus the inline fallback bar |

## How it loads

`.tmux.conf` does **not** use tpm. Its final lines are:

```
if-shell -F "test -x $HOME/.config/tmux-powerline/tmux-powerline/main.tmux" \
    "run-shell 'bash $HOME/.config/tmux-powerline/tmux-powerline/main.tmux'"
```

- The guard keeps a machine that was Stowed without running setup.sh working
  (see the fallback below) instead of producing an empty status bar.
- `run-shell` commands queued from a config file are dispatched after the
  file is parsed, so the plugin's settings land after the fallback's options
  and before the first draw.

The plugin's `main.tmux` overrides `status-left/right`, both lengths,
`status`, `status-interval`, `status-justify`, `status-style`,
`message-style`, the window-status formats and the separator. It reads
`#(.../powerline.sh left|right)` subprocesses on every `status-interval`
refresh (5s here — the upstream default of 1s re-forks every segment process
per second for no visible benefit).

## Fallback bar

The hand-rolled airline-style bar that predates the plugin is kept inline in
`.tmux.conf`. Every option it sets is also set by `main.tmux`, so:

- plugin installed → its values win, because the guarded `run-shell` runs
  after the whole config file has been parsed;
- plugin missing → the inline bar remains (fed by the `#($HOME/bin/loadavg)`
  shim, [loadavg(1)](loadavg.md)).

No conditionals, no platform splits: `.tmux.conf` stays identical on every
platform.

## Theme: `dots`

`themes/dots.sh` is the one custom file of consequence. It:

- reads `~/.vim/.theme` (what [.vimrc](../common/vim/.vimrc)'s `:DotTheme
  gruvbox|codedark` command writes; gruvbox is the default), falling back to
  the gruvbox palette if the file is missing — the tmux bar, the vim
  statusline and the trueline prompt therefore switch palette together;
- defines the `TMUX_POWERLINE_SEPARATOR_*` glyphs **itself** (a custom theme
  inherits nothing from upstream `default.sh`; omitting the separators yields
  a bar with no triangles). Nerd Font glyphs are built with `printf '\xee\x82\xb0'`
  -style UTF-8 byte escapes so the private-use-area code points stay
  byte-exact;
- capability-probes for a battery (`/sys/class/power_supply`,
  `pmset -g batt`, FreeBSD `sysctl hw.acpi.battery.life`) and only includes
  the `battery` segment where one exists — otherwise the upstream segment
  prints its ADAPTER glyph on battery-less desktops;
- sets the left segments (`tmux_session_info`, `hostname`), the right
  segments (`load`, battery?, `weather`, `lan_ip`, `wan_ip`, `vcs_branch`,
  `date_day`, `date`, `time`), and the window pill arrays.

Segment knobs live in `config.sh` (hostname/session formats, date/time
formats, weather provider, VCS branch truncation, …). The full knob list is
in the plugin's `segments/*.sh` at the pin.

## Dependencies

- tmux ≥ 2.9 (upstream requirement), bash ≥ 3.2 (plugin supports macOS stock
  bash).
- `jq` + `curl` for the `weather` segment (`yrno` provider, background
  cache refresh every 30 min so the bar never blocks).
- `curl` + `bc` for the `wan_ip` segment's freshness check (also
  background-refreshed at the pinned commit — synchronous in releases ≤
  3.2.0, which is why the pin should not be moved backwards).
- A Nerd Font on the terminal client (`TMUX_POWERLINE_PATCHED_FONT_IN_USE`
  in `config.sh`).

All of these are installed by [dots-setup](dots-setup.md) on every platform.

## Updating the plugin

The clone is pinned in `scripts/setup.sh`:

```
TMUX_POWERLINE_PIN="6cfa41c7696f0d530450d509b1e07ce3d778bd4b"   # main HEAD at integration time
```

- `./scripts/setup.sh --restow` (or `just restow`) fetches and hard-resets
  the clone to the pin; offline machines keep their current checkout.
- To move the pin: pick a commit, verify the segments/config knobs the
  theme and `config.sh` reference still exist upstream (`segments/*.sh`,
  `config/defaults.sh`, `lib/config_file.sh`), update `TMUX_POWERLINE_PIN`,
  and run `--restow`. Don't move the pin to ≤ 3.2.0 (synchronous WAN IP
  fetch blocks the bar).
- The pin is bumped deliberately, not blindly: a new pin changes segment and
  theme files under `~/.config/tmux-powerline/tmux-powerline`.

## Intended usage

Nothing to invoke by hand day-to-day: setup.sh installs the clone, stow links
config + theme, and `.tmux.conf` loads the plugin on server start. Reach for
this page when changing segments/colors (edit
`common/tmux-powerline/`, then `just restow` + reload tmux config), or when
the bar renders oddly after a pin bump.

## Diagnostics

```
~/.config/tmux-powerline/tmux-powerline/doctor.sh   # resolved paths/settings + live tmux options
bash ~/.config/tmux-powerline/tmux-powerline/powerline.sh left | cat -v   # standalone render; cat -v shows raw glyph bytes
TMUX_POWERLINE_DEBUG_MODE_ENABLED=true bash ~/.config/tmux-powerline/tmux-powerline/powerline.sh right
```

If a standalone render fails, fix it before reloading tmux — the plugin
sources `config.sh` with `errexit`, so a broken config can leave the bar
half-applied.

## Documentation note

`config.sh` and `themes/dots.sh` are **configuration, not scripts**: no
flags, no CLI, no exit status — so they carry no manpage pair under the
documentation contract in [CLAUDE.md](../CLAUDE.md). The shipped scripts the
bar touches — [loadavg(1)](loadavg.md) (fallback bar) and
[tmux-copy(1)](tmux-copy.md) — keep their manpages.