# Dotfiles task runner
# Run `just` or `just --list` to see available recipes.

set shell := ["bash", "-euo", "pipefail", "-c"]

# List available recipes
default:
  @just --list

# --- Core ---

# Full bootstrap: install deps, clone, decrypt, stow
setup:
  ./scripts/setup.sh

# Re-stow all packages (use after git pull)
restow:
  ./scripts/setup.sh --restow

# Remove all symlinks managed by stow
unstow:
  ./scripts/setup.sh --unstow

# Adopt existing files into the repo, then re-stow
adopt:
  ./scripts/setup.sh --adopt

# Run verification checks on current deployment
verify:
  ./scripts/verify.sh

# Encrypt a plaintext file
encrypt FILE:
  ./scripts/encrypt.sh "{{ FILE }}"

# Decrypt all secrets
decrypt:
  ./scripts/decrypt.sh

# --- Dev ---

# Run shellcheck on all shell scripts and bash dotfiles
lint:
  #!/usr/bin/env bash
  set -euo pipefail
  files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find scripts -name '*.sh' -print0)
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find common linux macos bsd -type f \( -name '.bash*' -o -name '.profile' \) -print0 2>/dev/null)
  echo "Checking ${#files[@]} files..."
  shellcheck -e SC1090,SC1091,SC2148 "${files[@]}"
  echo "All files passed."

# Scaffold a new stow package directory
add-package PLATFORM NAME:
  mkdir -p "{{ PLATFORM }}/{{ NAME }}"
  @echo "Created {{ PLATFORM }}/{{ NAME }}/ — add dotfiles mirroring \$HOME layout."

# --- Info ---

# Quick symlink health check (stow dry-run)
status:
  #!/usr/bin/env bash
  set -euo pipefail
  platform=$(uname -s)
  case "$platform" in
    Darwin) platform="macos" ;;
    Linux)  platform="linux" ;;
    *BSD)   platform="bsd" ;;
  esac
  for dir in common "$platform"; do
    [[ -d "$dir" ]] || continue
    for pkg in "$dir"/*/; do
      [[ -d "$pkg" ]] || continue
      name=$(basename "$pkg")
      if stow -d "$dir" -t "$HOME" --no-folding -n "$name" 2>&1 | grep -q 'WARNING'; then
        echo "CONFLICT $dir/$name"
      else
        echo "      ok $dir/$name"
      fi
    done
  done

# List stow packages by platform
list-packages:
  #!/usr/bin/env bash
  set -euo pipefail
  for dir in common macos linux bsd; do
    [[ -d "$dir" ]] || continue
    pkgs=()
    for pkg in "$dir"/*/; do
      [[ -d "$pkg" ]] || continue
      pkgs+=("$(basename "$pkg")")
    done
    if [[ ${#pkgs[@]} -gt 0 ]]; then
      echo "$dir: ${pkgs[*]}"
    fi
  done

# Compare encrypted vs decrypted file timestamps
diff-secrets:
  #!/usr/bin/env bash
  set -euo pipefail
  declare -A target_map=( ["ssh"]="$HOME/.ssh" ["tokens"]="$HOME/.config/tokens" )
  found=0
  while IFS= read -r -d '' age_file; do
    found=1
    rel="${age_file#secrets/}"
    subdir="${rel%%/*}"
    filename="${rel#*/}"
    filename="${filename%.age}"
    target_dir="${target_map[$subdir]:-}"
    [[ -z "$target_dir" ]] && continue
    target="$target_dir/$filename"
    if [[ ! -f "$target" ]]; then
      echo "MISSING  $rel -> $target"
    elif [[ "$age_file" -nt "$target" ]]; then
      echo "STALE    $rel (encrypted is newer)"
    else
      echo "      ok $rel"
    fi
  done < <(find secrets -name '*.age' -print0 2>/dev/null)
  [[ $found -eq 0 ]] && echo "(no .age files found)"
  true
