# shellcheck shell=bash
# tmux-powerline configuration — sourced by the plugin before themes/segments
# on every status refresh (see ~/.config/tmux-powerline/tmux-powerline/config_file.sh).
# Paired with themes/dots.sh, which follows the vim DotTheme choice in
# ~/.vim/.theme (gruvbox | codedark).

# Load this repo's theme from this package's themes/ dir. The plugin never
# defaults TMUX_POWERLINE_DIR_USER_THEMES — without these lines it silently
# falls back to upstream default.sh. Values are re-expanded with `eval` by the
# plugin, hence the upstream-generated single-quoted form.
# shellcheck disable=SC2016  # single quotes are intentional: eval-deferred
export TMUX_POWERLINE_DIR_USER_THEMES='"${XDG_CONFIG_HOME:-$HOME/.config}/tmux-powerline/themes"'
# shellcheck disable=SC2016  # single quotes are intentional: eval-deferred
export TMUX_POWERLINE_DIR_USER_SEGMENTS='"${XDG_CONFIG_HOME:-$HOME/.config}/tmux-powerline/segments"'

# Nerd Font is a repo-wide requirement (trueline, vim-airline already assume it).
export TMUX_POWERLINE_PATCHED_FONT_IN_USE="true"
export TMUX_POWERLINE_THEME="dots"

# Bar layout. status-interval 5s, not the upstream default of 1: every refresh
# re-sources config + theme + every segment process (uptime, git, ifconfig),
# so 1s buys nothing visible and burns cycles.
export TMUX_POWERLINE_STATUS_VISIBILITY="on"
export TMUX_POWERLINE_STATUS_INTERVAL="5"
export TMUX_POWERLINE_STATUS_JUSTIFICATION="centre"
export TMUX_POWERLINE_STATUS_LEFT_LENGTH="60"
export TMUX_POWERLINE_STATUS_RIGHT_LENGTH="180"
export TMUX_POWERLINE_WINDOW_STATUS_SEPARATOR=""

# --- Segment knobs ---
# Hostname: short form (matches the fallback bar's #h), laptop glyph is
# supplied by the hostname segment itself.
export TMUX_POWERLINE_SEG_HOSTNAME_FORMAT="short"

# Session/window/pane in the leftmost pill.
export TMUX_POWERLINE_SEG_TMUX_SESSION_INFO_FORMAT="#S:#I.#P"

# Matches the formats the old .tmux.conf status bar used (12h clock, US date).
export TMUX_POWERLINE_SEG_DATE_FORMAT="%m/%d/%y"
export TMUX_POWERLINE_SEG_TIME_FORMAT="%I:%M %p"

# Battery: plain percentage (the plugin's heart style is noisy next to the
# other numeric pills).
export TMUX_POWERLINE_SEG_BATTERY_TYPE="percentage"

# Weather via yr.no (curl + jq, both installed by setup.sh; cache refreshes
# in the background every 30 min so the bar never blocks).
export TMUX_POWERLINE_SEG_WEATHER_DATA_PROVIDER="yrno"
export TMUX_POWERLINE_SEG_WEATHER_UNIT="c"
export TMUX_POWERLINE_SEG_WEATHER_UPDATE_PERIOD="1800"
export TMUX_POWERLINE_SEG_WEATHER_ICON_STYLE="nerdfonts"

# Git branch shown for the active pane's cwd, truncated like the old bar's
# vim statusline.
export TMUX_POWERLINE_SEG_VCS_BRANCH_MAX_LEN="24"