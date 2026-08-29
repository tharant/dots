# shellcheck shell=bash
# ~/.bashrc.platform.d/linux.sh — Linux overrides (stowed from linux/bash)

# Locale: use en_US.UTF-8 only if it is actually generated, otherwise fall back
# to C.UTF-8 (common on minimal/container images).
if locale -a 2> /dev/null | grep -qiE '^en_US\.(utf-?8)$'; then
  export LANG="en_US.UTF-8"
else
  export LANG="C.UTF-8"
  echo "linux.sh: en_US.UTF-8 not available, using C.UTF-8 (run 'sudo locale-gen en_US.UTF-8')" 1>&2
fi

# LS_COLORS prefer the user's database, then system defaults, then a hand-built
# fallback for systems without dircolors (e.g. minimal Alpine images).
if command -v dircolors > /dev/null 2>&1; then
  if [[ -r "$HOME/.ls_colors" ]]; then
    eval "$(dircolors -b "$HOME/.ls_colors")"
  else
    eval "$(dircolors -b)"
  fi
else
  export LS_COLORS="di=36;40:ln=35;40:so=33;40:pi=33;40:ex=32;40:bd=34;46:cd=34;43:su=0;41:sg=0;43:tw=31;40:ow=36;40:"
fi

# Linux-specific sourcing
[[ -s ~/.bash_linux ]] && source ~/.bash_linux

# Shellfish (iPad terminal)
[[ -f "$HOME/.shellfishrc" ]] && source "$HOME/.shellfishrc"

# Linuxbrew
if [[ -s /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  [[ -r "/home/linuxbrew/.linuxbrew/etc/profile.d/bash_completion.sh" ]] && . "/home/linuxbrew/.linuxbrew/etc/profile.d/bash_completion.sh"
fi

# Linux-specific PATH (idempotent)
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac