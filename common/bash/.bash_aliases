#!/bin/bash

alias ls='ls --color=auto -AcFv'
alias grep='grep --color=auto'
alias man='man -P most'
alias rm='rm -i'
alias mv='mv -i'
alias cp='cp -i'

alias timestamp="date '+%Y%m%d-%H%M%S'"
alias unixtime="date '+%s'"

alias hl='highlight --style xoria256 --out-format xterm256'

alias rsync='rsync --progress'
alias parallel='parallel --will-cite'
alias cal='cal -y $(date "+%Y")'

alias dtest='dd if=/dev/zero of=file bs=20k count=100k conv=fdatasync; rm -f file'
alias cat='bat --style="plain" --italic-text=always --theme="Monokai Extended" --color=auto --tabs=2 --paging=never'
