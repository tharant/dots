# shellcheck shell=bash
# ~/.bashrc.platform.d/macos.sh — macOS overrides (stowed from macos/bash)

# Locale (LC_ALL is deliberately not forced: it changes sort/glob semantics)
export LANG="en_US.UTF-8"

# Terminal.app injects a bare LC_CTYPE=UTF-8, which only exists as a locale
# name elsewhere (e.g. Linux); on macOS it makes perl/git emit locale warnings.
# Drop it unless "UTF-8" is genuinely a selectable locale here.
if [[ "${LC_CTYPE-}" == "UTF-8" ]] && ! locale -a 2> /dev/null | grep -qx 'UTF-8'; then
  unset LC_CTYPE
fi

# Package managers: Homebrew (Apple Silicon: /opt/homebrew; legacy Intel
# installs: /usr/local) and MacPorts (/opt/local, the Intel default since
# Homebrew dropped Intel). Whichever is installed goes on PATH; with both, the
# one setup.sh would pick (scripts/setup.sh macos_select_pkg_mgr) goes first:
# Homebrew on Apple Silicon, MacPorts on Intel, or DOTS_MACOS_PKG_MGR if set.
_dots_brew=""
if [[ -x /opt/homebrew/bin/brew ]]; then
  _dots_brew=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then
  _dots_brew=/usr/local/bin/brew
fi
[[ -n "$_dots_brew" ]] && eval "$("$_dots_brew" shellenv)"

if [[ -x /opt/local/bin/port ]]; then
  _dots_port_first=true
  if [[ -n "$_dots_brew" ]]; then
    case "${DOTS_MACOS_PKG_MGR-}" in
      port) ;;
      brew) _dots_port_first=false ;;
      *) [[ "$(sysctl -n hw.optional.arm64 2> /dev/null)" == "1" ]] && _dots_port_first=false ;;
    esac
  fi
  # Re-adding moves an existing entry rather than duplicating it
  _dots_path=":$PATH:"
  _dots_path="${_dots_path//:\/opt\/local\/bin:/:}"
  _dots_path="${_dots_path//:\/opt\/local\/sbin:/:}"
  _dots_path="${_dots_path#:}"
  _dots_path="${_dots_path%:}"
  if [[ "$_dots_port_first" == "true" ]]; then
    export PATH="/opt/local/bin:/opt/local/sbin${_dots_path:+:$_dots_path}"
  else
    export PATH="${_dots_path:+$_dots_path:}/opt/local/bin:/opt/local/sbin"
  fi
  unset _dots_path _dots_port_first
fi
unset _dots_brew

# Homebrew privacy: no analytics, no install/update hints; mirrors the env
# setup.sh exports for its own bootstrap run (scripts/setup.sh).
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1

# OrbStack integration (no-op if not installed)
[[ -s "$HOME/.orbstack/shell/init.bash" ]] && source "$HOME/.orbstack/shell/init.bash"

# BSD ls colors (macOS ls uses LSCOLORS, not LS_COLORS)
export LSCOLORS=gxfxdxdxcxegedabadbxgx

# hide dotfiles in finder
hide-dots() {
	defaults write com.apple.finder AppleShowAllFiles FALSE && killall -KILL Finder
}

# show dotfiles in finder
show-dots() {
	defaults write com.apple.finder AppleShowAllFiles TRUE && killall -KILL Finder
}

# macOS man(1) omits ~/.local/share/man from its default path — add it so the
# dots manpages installed by `just man-install` (see docs/man/Makefile) resolve.
# An explicit MANPATH *replaces* the default path, so preserve the existing
# value; the empty element expands to the default path on macOS man and on
# Linux man-db alike.
case ":${MANPATH-}:" in
  *":$HOME/.local/share/man:"*) ;;
  *) export MANPATH="$HOME/.local/share/man:${MANPATH:+:$MANPATH}" ;;
esac

# The package manager's bash 5 and its /etc/shells entry are handled by setup.sh.