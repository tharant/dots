# ~/.bash_profile — macOS login shell entry point
# Sources .bashrc for interactive config, then adds macOS-specific setup.

# Homebrew (Apple Silicon: /opt/homebrew, Intel: /usr/local)
if [[ -f /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Source interactive config
[[ -f ~/.bashrc ]] && source ~/.bashrc

# OrbStack integration (no-op if not installed)
source ~/.orbstack/shell/init.bash 2>/dev/null || :

# BSD ls colors (macOS ls uses LSCOLORS, not LS_COLORS)
export LSCOLORS=gxfxdxdxcxegedabadbxgx
