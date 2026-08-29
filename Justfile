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

# --- Manpages (docs/man) ---

# Lint all manpages (mandoc -T lint)
man-check:
  cd docs/man && make check

# Install manpage symlinks into ~/.local/share/man/man1
man-install:
  cd docs/man && make install

# Remove the installed manpage symlinks
man-uninstall:
  cd docs/man && make uninstall

# --- Dev ---

# Run shellcheck on all shell scripts and bash dotfiles
lint:
  #!/usr/bin/env bash
  set -euo pipefail
  if ! command -v shellcheck >/dev/null 2>&1; then
    echo "lint: shellcheck is not installed — skipping."
    echo "  (install with: brew install shellcheck | apt install shellcheck | apk add shellcheck)"
    exit 0
  fi
  files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find scripts -name '*.sh' -print0)
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find common macos linux bsd alpine wsl -type f \( -name '.bash*' -o -name '.profile' \) -print0 2>/dev/null)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "lint: nothing to check."
    exit 0
  fi
  echo "Checking ${#files[@]} files..."
  shellcheck -e SC1090,SC1091,SC2148 "${files[@]}"
  echo "All files passed."

# Scaffold a new stow package directory
add-package PLATFORM NAME:
  #!/usr/bin/env bash
  set -euo pipefail
  case "{{ PLATFORM }}" in
    common|macos|linux|bsd|alpine|wsl) ;;
    *) echo "add-package: unknown platform '{{ PLATFORM }}' (expected one of: common macos linux bsd alpine wsl)"; exit 1 ;;
  esac
  mkdir -p "{{ PLATFORM }}/{{ NAME }}"
  echo "Created {{ PLATFORM }}/{{ NAME }}/ — add dotfiles mirroring \$HOME layout."

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
      # stow's exit code is the source of truth; print its actual warnings
      if out=$(stow -d "$dir" -t "$HOME" --no-folding -n "$name" 2>&1); then
        echo "      ok $dir/$name"
      else
        echo "CONFLICT $dir/$name"
        printf '%s\n' "$out" | sed 's/^/        /'
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
  target_dir_for() {
    case "$1" in
      ssh)    echo "$HOME/.ssh" ;;
      tokens) echo "$HOME/.config/tokens" ;;
      *)      echo "" ;;
    esac
  }
  found=0
  while IFS= read -r -d '' age_file; do
    rel="${age_file#secrets/}"
    # Passphrase fallback copies decrypt to the same target as X.age
    case "$rel" in
      *.phrase.age) continue ;;
    esac
    found=1
    subdir="${rel%%/*}"
    filename="${rel#*/}"
    filename="${filename%.age}"
    target_dir="$(target_dir_for "$subdir")"
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
