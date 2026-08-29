#!/usr/bin/env bash
set -euo pipefail

# Decrypt all secrets/ artifacts to their target locations.
# Each secret is stored as two age artifacts:
#   X.age         — encrypted to the recipients in secrets/recipients.txt
#   X.phrase.age  — passphrase-encrypted fallback for fresh machines
# Decryption order: try the age identity on X.age, then the passphrase on
# X.phrase.age, then (legacy single-artifact secrets) the passphrase on X.age.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="$REPO_DIR/secrets"
AGE_IDENTITY="${AGE_IDENTITY:-$HOME/.age/keys.txt}"

if ! command -v age &>/dev/null; then
    echo "Error: age is not installed."
    exit 1
fi

# Age identity args (empty means no identity on this machine)
AGE_ARGS=()
if [[ -f "$AGE_IDENTITY" ]]; then
    echo "Using age identity: $AGE_IDENTITY"
    AGE_ARGS=(-i "$AGE_IDENTITY")
else
    echo "No age identity found at $AGE_IDENTITY — will prompt for passphrase."
fi

# Mapping: secrets/subdir/filename.age -> target location
# (a case statement instead of an assoc array keeps this bash 3.2 compatible)
target_dir_for() {
    case "$1" in
        ssh) echo "$HOME/.ssh" ;;
        tokens) echo "$HOME/.config/tokens" ;;
        *) echo "" ;;
    esac
}

# Decrypt one artifact to a temp file, verify the write succeeded, then move it
# into place. Passes any age args through. Leaves $target untouched on failure.
decrypt_artifact() {
    local artifact="$1"
    shift
    local tmp
    tmp="$(mktemp "${target}.XXXXXX")"
    if ! age -d "$@" -o "$tmp" "$artifact"; then
        rm -f "$tmp"
        return 1
    fi
    chmod 600 "$tmp"
    mv "$tmp" "$target"
}

decrypt_file() {
    local age_file="$1"
    local rel_path="${age_file#"$SECRETS_DIR"/}"
    local subdir="${rel_path%%/*}"
    local filename="${rel_path#*/}"
    filename="${filename%.age}"
    # Ignore the passphrase copies themselves (handled via their sibling below)
    case "$filename" in
        *.phrase) return ;;
    esac

    local target_dir
    target_dir="$(target_dir_for "$subdir")"
    if [[ -z "$target_dir" ]]; then
        echo "Warning: No target mapping for subdir '$subdir', skipping $rel_path"
        return
    fi

    target="$target_dir/$filename"
    main="$age_file"
    phrase="${age_file%.age}.phrase.age"

    # Skip if target exists and is newer than every artifact (unless FORCE)
    if [[ "${FORCE:-false}" != "true" && -f "$target" && "$target" -nt "$main" \
          && ( ! -e "$phrase" || "$target" -nt "$phrase" ) ]]; then
        echo "Skipping (up to date): $rel_path -> $target"
        return
    fi

    mkdir -p "$target_dir"
    chmod 700 "$target_dir"

    echo "Decrypting: $rel_path -> $target"
    local ok=0
    if [[ ${#AGE_ARGS[@]} -gt 0 && -f "$main" ]]; then
        if decrypt_artifact "$main" "${AGE_ARGS[@]}"; then
            ok=1
        else
            echo "  Identity did not match, falling back to passphrase..."
        fi
    fi
    if [[ $ok -eq 0 ]]; then
        if [[ -f "$phrase" ]]; then
            if ! decrypt_artifact "$phrase"; then
                echo "Error: passphrase decryption failed for $rel_path"
                return 1
            fi
        elif [[ -f "$main" ]]; then
            # Legacy single-artifact secret (passphrase-only .age)
            if ! decrypt_artifact "$main"; then
                echo "Error: passphrase decryption failed for $rel_path"
                return 1
            fi
        else
            echo "Error: no artifacts found for $rel_path"
            return 1
        fi
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