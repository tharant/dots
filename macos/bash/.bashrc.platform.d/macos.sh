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

# Homebrew (Apple Silicon: /opt/homebrew, Intel: /usr/local)
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

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

# Homebrew's bash 5 and the /etc/shells entry are handled by setup.sh.