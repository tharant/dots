# shellcheck shell=bash
# "dots" theme for tmux-powerline.
#
# Follows the vim DotTheme choice in ~/.vim/.theme (`:DotTheme gruvbox` /
# `:DotTheme codedark` in .vimrc writes it; gruvbox is the default), so the
# tmux status bar, the vim statusline and the trueline prompt all shift
# palette together. Sourced once per powerline.sh render (and once when
# main.tmux applies the settings), so keep it cheap.
#
# A custom theme must define everything itself — the separator glyphs, the
# default bg/fg colors, the DEFAULT_*_SEPARATORs and both segment arrays.
# Nothing is inherited from upstream themes/default.sh.

# shellcheck disable=SC2034
# The palette/separator/array variables produced here are consumed by the
# tmux-powerline core (lib/powerline.sh) via sourcing this file, so most
# assignments are legitimately "unused" from this file's own point of view.

_tpl_theme=gruvbox
if [ -r "${HOME}/.vim/.theme" ]; then
	_tpl_theme=$(tr -d '[:space:]' <"${HOME}/.vim/.theme")
fi

case "${_tpl_theme}" in
codedark)
	# VS Code Dark+ (vim-code-dark / tomasiser/vim-code-dark)
	TPL_BG="#1e1e1e" # status bar base        (editor.background)
	TPL_PILL="#252526" # recessed pill        (sideBar.background)
	TPL_PILL_HI="#333333" # brighter pill      (badge background)
	TPL_FG="#d4d4d4" # primary text           (editor.foreground)
	TPL_FG_DIM="#858585" # secondary text
	TPL_ACCENT="#569cd6" # blue badge         (variable language color)
	TPL_GREEN="#4ec9b4"
	TPL_YELLOW="#dcdcaa"
	TPL_ORANGE="#ce9178"
	TPL_PURPLE="#c586c0"
	;;
*)
	# Gruvbox dark (morhetz/gruvbox)
	TPL_BG="#282828" # bg0
	TPL_PILL="#3c3836" # bg1
	TPL_PILL_HI="#504945" # bg2
	TPL_FG="#ebdbb2" # fg1
	TPL_FG_DIM="#928374" # gray
	TPL_ACCENT="#83a598" # blue (bright set)
	TPL_GREEN="#b8bb26"
	TPL_YELLOW="#fabd2f"
	TPL_ORANGE="#fe8019"
	TPL_PURPLE="#d3869b"
	;;
esac
unset -v _tpl_theme

# Separators. Nerd Font glyphs are built with printf byte escapes rather than
# as typed literals: private-use-area characters are exactly what editors and
# copy paths tend to mangle, and this keeps them byte-exact (UTF-8 of
# U+E0B0..U+E0B3 — same triangles the old .tmux.conf bar and vim-airline use).
if type tp_patched_font_in_use >/dev/null 2>&1 && tp_patched_font_in_use; then
	TMUX_POWERLINE_SEPARATOR_LEFT_BOLD=$(printf '\xee\x82\xb2')
	TMUX_POWERLINE_SEPARATOR_LEFT_THIN=$(printf '\xee\x82\xb3')
	TMUX_POWERLINE_SEPARATOR_RIGHT_BOLD=$(printf '\xee\x82\xb0')
	TMUX_POWERLINE_SEPARATOR_RIGHT_THIN=$(printf '\xee\x82\xb1')
else
	TMUX_POWERLINE_SEPARATOR_LEFT_BOLD="◀"
	TMUX_POWERLINE_SEPARATOR_LEFT_THIN="❮"
	TMUX_POWERLINE_SEPARATOR_RIGHT_BOLD="▶"
	TMUX_POWERLINE_SEPARATOR_RIGHT_THIN="❯"
fi

TMUX_POWERLINE_DEFAULT_BACKGROUND_COLOR=${TMUX_POWERLINE_DEFAULT_BACKGROUND_COLOR:-$TPL_BG}
TMUX_POWERLINE_DEFAULT_FOREGROUND_COLOR=${TMUX_POWERLINE_DEFAULT_FOREGROUND_COLOR:-$TPL_FG}
TMUX_POWERLINE_DEFAULT_LEFTSIDE_SEPARATOR=${TMUX_POWERLINE_DEFAULT_LEFTSIDE_SEPARATOR:-$TMUX_POWERLINE_SEPARATOR_RIGHT_BOLD}
TMUX_POWERLINE_DEFAULT_RIGHTSIDE_SEPARATOR=${TMUX_POWERLINE_DEFAULT_RIGHTSIDE_SEPARATOR:-$TMUX_POWERLINE_SEPARATOR_LEFT_BOLD}

# Left: session/window/pane pill, then the hostname badge in the accent color.
TMUX_POWERLINE_LEFT_STATUS_SEGMENTS=(
	"tmux_session_info $TPL_PILL $TPL_FG"
	"hostname $TPL_ACCENT $TPL_BG"
)

# Battery only where a battery exists — the upstream segment prints its
# Nerd-Font ADAPTER glyph on battery-less desktops, so capability-probe
# instead of listing the segment unconditionally.
_tpl_battery=""
if [ -d /sys/class/power_supply ]; then
	for _tpl_ps in /sys/class/power_supply/*; do
		if [ -r "${_tpl_ps}/type" ] && grep -q Battery "${_tpl_ps}/type" 2>/dev/null; then
			_tpl_battery="battery $TPL_PILL_HI $TPL_ORANGE"
			break
		fi
	done
elif [ "$(uname -s)" = "Darwin" ] && pmset -g batt 2>/dev/null | grep -qi 'InternalBattery'; then
	_tpl_battery="battery $TPL_PILL_HI $TPL_ORANGE"
elif [ "$(uname -s)" = "FreeBSD" ] && [ -n "$(sysctl -n hw.acpi.battery.life 2>/dev/null)" ]; then
	_tpl_battery="battery $TPL_PILL_HI $TPL_ORANGE"
fi

# Right: mem/cpu/load (tmux-mem-cpu-load, replaces the old load pill — the
# binary already reports the same three load averages), battery?, weather, IPs,
# vcs branch, then the date cluster capped by an accent-colored time pill.
# Alternating pill/hi backgrounds keep neighboring segments readable against
# the bar.
TMUX_POWERLINE_RIGHT_STATUS_SEGMENTS=(
	"tmux_mem_cpu_load $TPL_PILL_HI $TPL_GREEN"
	#"weather $TPL_PILL $TPL_ACCENT"
	"lan_ip $TPL_PILL_HI $TPL_FG_DIM"
	#"wan_ip $TPL_PILL_HI $TPL_FG_DIM"
	#"vcs_branch $TPL_PILL $TPL_PURPLE"
	"date_day $TPL_PILL_HI $TPL_YELLOW"
	"date $TPL_PILL $TPL_FG"
	"time $TPL_ACCENT $TPL_BG"
)
# Insert the battery after the load pill when this machine has one.
if [ -n "$_tpl_battery" ]; then
	TMUX_POWERLINE_RIGHT_STATUS_SEGMENTS=(
		"${TMUX_POWERLINE_RIGHT_STATUS_SEGMENTS[@]:0:1}"
		"$_tpl_battery"
		"${TMUX_POWERLINE_RIGHT_STATUS_SEGMENTS[@]:1}"
	)
fi
unset -v _tpl_battery _tpl_ps

# Window flow: active window is a light inverse pill (default fg as the
# background), inactive windows are plain; both taper right with a thin cap,
# mirroring the old bar's window pills.
TMUX_POWERLINE_WINDOW_STATUS_CURRENT=(
	"#[$(tp_format inverse)]"
	"$TMUX_POWERLINE_DEFAULT_LEFTSIDE_SEPARATOR"
	" #I#F "
	"$TMUX_POWERLINE_SEPARATOR_RIGHT_THIN"
	" #W "
	"#[$(tp_format regular)]"
	"$TMUX_POWERLINE_DEFAULT_LEFTSIDE_SEPARATOR"
)
TMUX_POWERLINE_WINDOW_STATUS_STYLE=("$(tp_format regular)")
TMUX_POWERLINE_WINDOW_STATUS_FORMAT=(
	"#[$(tp_format regular)]"
	"  #I#{?window_flags,#F, } "
	"$TMUX_POWERLINE_SEPARATOR_RIGHT_THIN"
	" #W "
)
