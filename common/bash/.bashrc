# shellcheck shell=bash
# ~/.bashrc — Interactive shell config (sourced by .bash_profile)
# Keep platform-specific config in the macos/, linux/, bsd/, alpine/ and wsl/
# packages (stowed to ~/.bashrc.platform.d/), not here.

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Platform-specific overrides (stowed from macos/, linux/, bsd/, alpine/, wsl/ packages)
if compgen -G "$HOME/.bashrc.platform.d/*.sh" > /dev/null; then
    for _platform_sh in "$HOME"/.bashrc.platform.d/*.sh; do
        [[ -s "$_platform_sh" ]] && source "$_platform_sh"
    done
    unset -v _platform_sh
fi

# Prompt
export PS1="\n\[\033[1;37m\]\u@\h:\[\033[0;32m\]\w/\[\033[1;37m\]\n$ \[\033[0m\]"

# History
export HISTFILE=~/.bash_history
export PROMPT_COMMAND='history -a'
shopt -s cdspell

# PATH
export PATH="${PATH}:$HOME/bin:$HOME/bin/ssh-hosts"

# Source modular configs
[[ -s ~/.bash_sensible ]] && source ~/.bash_sensible
[[ -s ~/.bash_functions ]] && source ~/.bash_functions
[[ -s ~/.bash_aliases ]] && source ~/.bash_aliases

# ssh-agent (guard for existing socket)
if [[ -z "${SSH_AUTH_SOCK-}" ]] || [[ ! -S "${SSH_AUTH_SOCK}" ]]; then
  eval "$(ssh-agent -t 1d)"
fi

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Optional tools (guarded)
command -v kubectl &>/dev/null && source <(kubectl completion bash)
command -v direnv &>/dev/null && eval "$(direnv hook bash)"
command -v aws_completer &>/dev/null && complete -C aws_completer aws

# Trueline prompt (requires bash >= 4.3, e.g. brew-installed on macOS)
if [[ -f ~/.local/trueline/.trueline.conf ]]; then
  if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )); then
    source ~/.local/trueline/.trueline.conf
  else
    echo "trueline: needs bash >= 4.3 (you have ${BASH_VERSION}); keeping the default prompt." 1>&2
  fi
fi

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"