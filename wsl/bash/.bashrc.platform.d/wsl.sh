# shellcheck shell=bash
# ~/.bashrc.platform.d/wsl.sh — WSL2 overrides (stowed from wsl/bash)

# Only act inside WSL; harmless no-op (and safe to stow by accident) elsewhere.
if ! grep -qi microsoft /proc/version 2> /dev/null; then
  return 0
fi

# Trim the Windows PATH entries that WSL interop appends: they slow command
# lookup markedly. Anything genuinely needed from the Windows side is reached
# by absolute path instead (see the clip alias below).
_wsl_path_new=""
IFS=':' read -r -a _wsl_path_parts <<< "${PATH}"
for _wsl_path_dir in "${_wsl_path_parts[@]}"; do
  [[ -n "${_wsl_path_dir}" ]] || continue
  case "${_wsl_path_dir}" in
    /mnt/[a-z]|/mnt/[a-z]/*) continue ;;
  esac
  case ":${_wsl_path_new}:" in
    *":${_wsl_path_dir}:"*) continue ;;
  esac
  _wsl_path_new="${_wsl_path_new:+${_wsl_path_new}:}${_wsl_path_dir}"
done
export PATH="${_wsl_path_new}"
unset -v _wsl_path_new _wsl_path_parts _wsl_path_dir

# Clipboard, by absolute path so it works despite the PATH trim above.
if [[ -x /mnt/c/Windows/System32/clip.exe ]]; then
  alias clip='/mnt/c/Windows/System32/clip.exe'
fi

# The durable fixes live in /etc/wsl.conf, not here: [interop] appendWindowsPath
# (stops Windows PATH injection at the source) and [boot] systemd=true.
# WSLg's DISPLAY/WAYLAND_DISPLAY are left untouched.