#!/bin/bash

# No -v: BusyBox ls rejects it and BSD ls means something different by it
alias ls='ls --color=auto -AcF'
alias grep='grep --color=auto'
# Alpine's mandoc has no -P; only use a pager if `most` is actually installed
command -v most &>/dev/null && alias man='man -P most'
alias rm='rm -i'
alias mv='mv -i'
alias cp='cp -i'

alias timestamp="date '+%Y%m%d-%H%M%S'"
alias unixtime="date '+%s'"

command -v highlight &>/dev/null && alias hl='highlight --style xoria256 --out-format xterm256'

alias rsync='rsync --progress'
command -v parallel &>/dev/null && alias parallel='parallel --will-cite'
alias cal='cal -y $(date "+%Y")'

alias dtest='dd if=/dev/zero of=file bs=20k count=100k conv=fdatasync; rm -f file'
# A broken `cat` is the worst kind of failure, so no alias without bat
command -v bat &>/dev/null && alias cat='bat --style="plain" --italic-text=always --theme="Monokai Extended" --color=auto --tabs=2 --paging=never'
