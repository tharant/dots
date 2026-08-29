# shellcheck shell=bash
# ~/.bashrc.platform.d/alpine.sh — Alpine/musl overrides (stowed from alpine/bash)

# musl has no en_US.UTF-8, ever; C.UTF-8 is the only UTF-8 locale it provides.
export LANG="C.UTF-8"

# setup.sh installs bash, shadow (usermod/chsh) and ncurses-terminfo, and sets
# the login shell. Nothing here may assume coreutils/GNU tools: no dircolors,
# no g-prefixed coreutils, and BusyBox ls does not accept -v.