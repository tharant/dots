#!/usr/bin/env bash
set -euo pipefail

# Decrypt all *.age files from secrets/ to their target locations.
# Tries age identity key first, falls back to passphrase prompt.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="$REPO_DIR/secrets"
AGE_IDENTITY="${AGE_IDENTITY:-$HOME/.age/keys.txt}"

if ! command -v age &>/dev/null; then
    echo "Error: age is not installed."
    exit 1
fi

# Determine decryption method
AGE_ARGS=()
if [[ -f "$AGE_IDENTITY" ]]; then
    echo "Using age identity: $AGE_IDENTITY"
    AGE_ARGS=(-i "$AGE_IDENTITY")
else
    echo "No age identity found at $AGE_IDENTITY — will prompt for passphrase."
fi

# Mapping: secrets/subdir/filename.age -> target location
declare -A TARGET_MAP=(
    ["ssh"]="$HOME/.ssh"
    ["tokens"]="$HOME/.config/tokens"
)

decrypt_file() {
    local age_file="$1"
    local rel_path="${age_file#"$SECRETS_DIR"/}"
    local subdir="${rel_path%%/*}"
    local filename="${rel_path#*/}"
    filename="${filename%.age}"

    local target_dir="${TARGET_MAP[$subdir]:-}"
    if [[ -z "$target_dir" ]]; then
        echo "Warning: No target mapping for subdir '$subdir', skipping $rel_path"
        return
    fi

    local target="$target_dir/$filename"

    # Skip if target exists and is newer than source (unless FORCE)
    if [[ "${FORCE:-false}" != "true" && -f "$target" && "$target" -nt "$age_file" ]]; then
        echo "Skipping (up to date): $rel_path -> $target"
        return
    fi

    mkdir -p "$target_dir"

    echo "Decrypting: $rel_path -> $target"
    age -d "${AGE_ARGS[@]}" -o "$target" "$age_file"

    # Set restrictive permissions for SSH keys
    if [[ "$subdir" == "ssh" ]]; then
        chmod 600 "$target"
        chmod 700 "$target_dir"
    fi
}

# Find and decrypt all .age files
found=0
while IFS= read -r -d '' age_file; do
    decrypt_file "$age_file"
    found=$((found + 1))
done < <(find "$SECRETS_DIR" -name '*.age' -print0 2>/dev/null)

if [[ $found -eq 0 ]]; then
    echo "No .age files found in $SECRETS_DIR"
else
    echo "Decrypted $found file(s)."
fi
