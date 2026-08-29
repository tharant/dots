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

# Homebrew's bash 5 and the /etc/shells entry are handled by setup.sh.