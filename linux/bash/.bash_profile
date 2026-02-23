# ~/.bash_profile — Linux login shell entry point
# Sources .bashrc for interactive config, then adds Linux-specific setup.

# Source interactive config
[[ -f ~/.bashrc ]] && source ~/.bashrc

# Linux-specific sourcing
[[ -s ~/.bash_linux ]] && source ~/.bash_linux

# LS_COLORS
export LSCOLORS=gxfxdxdxcxegedabadbxgx
export LS_COLORS="di=36;40:ln=35;40:so=33;40:pi=33;40:ex=32;40:bd=34;46:cd=34;43:su=0;41:sg=0;43:tw=31;40:ow=36;40:"
[[ -f "$HOME/.ls_colors" ]] && eval "$(dircolors -b "$HOME/.ls_colors")"

# Linuxbrew
[[ -s /home/linuxbrew/.linuxbrew/bin/brew ]] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
[[ -r "/home/linuxbrew/.linuxbrew/etc/profile.d/bash_completion.sh" ]] && . "/home/linuxbrew/.linuxbrew/etc/profile.d/bash_completion.sh"

# Linux-specific PATH
export PATH="$HOME/.local/bin:$PATH"

# Trueline prompt (overrides default PS1)
[[ -f ~/.trueline.conf ]] && source ~/.trueline.conf

# AWS completion
complete -C '/usr/local/bin/aws_completer' aws

# Shellfish (iPad terminal)
[[ -f "$HOME/.shellfishrc" ]] && source "$HOME/.shellfishrc"

# SDKMAN (must be at end)
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
