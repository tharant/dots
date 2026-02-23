#!/usr/bin/env bash
set -euo pipefail

# Encrypt a file using both passphrase and age recipient key (hybrid mode).
# Usage: ./scripts/encrypt.sh <plaintext-file> [output.age]
# If output is omitted, it is inferred from the input path.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
RECIPIENTS_FILE="$REPO_DIR/secrets/recipients.txt"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <plaintext-file> [output.age]"
    exit 1
fi

INPUT="$1"

if [[ ! -f "$INPUT" ]]; then
    echo "Error: File not found: $INPUT"
    exit 1
fi

if ! command -v age &>/dev/null; then
    echo "Error: age is not installed. Install with: brew install age / apt install age / pkg install age"
    exit 1
fi

# Reverse TARGET_MAP: source directory -> secrets subdirectory
declare -A REVERSE_MAP=(
    ["$HOME/.ssh"]="ssh"
    ["$HOME/.config/tokens"]="tokens"
)

# Determine output path
if [[ $# -ge 2 ]]; then
    OUTPUT="$2"
else
    # Auto-infer from input path
    INPUT_ABS="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
    OUTPUT=""
    for src_dir in "${!REVERSE_MAP[@]}"; do
        if [[ "$INPUT_ABS" == "$src_dir"/* ]]; then
            rel="${INPUT_ABS#"$src_dir"/}"
            OUTPUT="$REPO_DIR/secrets/${REVERSE_MAP[$src_dir]}/${rel}.age"
            break
        fi
    done

    if [[ -z "$OUTPUT" ]]; then
        read -rp "Could not infer target. Enter output path: " OUTPUT
        if [[ -z "$OUTPUT" ]]; then
            echo "Error: No output path provided."
            exit 1
        fi
    fi
fi

mkdir -p "$(dirname "$OUTPUT")"

AGE_ARGS=(-p)

if [[ -f "$RECIPIENTS_FILE" ]]; then
    AGE_ARGS+=(-R "$RECIPIENTS_FILE")
    echo "Encrypting with passphrase + age recipient key (hybrid mode)"
else
    echo "Warning: No recipients.txt found. Encrypting with passphrase only."
    echo "Run 'age-keygen' and add the public key to secrets/recipients.txt for hybrid mode."
fi

age "${AGE_ARGS[@]}" -o "$OUTPUT" "$INPUT"
echo "Encrypted: $OUTPUT"

# Verify by decrypting to a temp file and diffing
TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

echo "Verifying encryption round-trip (re-enter passphrase)..."
if ! age -d -o "$TMPFILE" "$OUTPUT"; then
    echo "Error: Verification decryption failed."
    rm -f "$OUTPUT"
    exit 1
fi

if ! diff -q "$INPUT" "$TMPFILE" >/dev/null 2>&1; then
    echo "Error: Decrypted file does not match original. Removing bad encrypted file."
    rm -f "$OUTPUT"
    exit 1
fi

echo "Verification passed."

# Auto-commit
REL_OUTPUT="${OUTPUT#"$REPO_DIR"/}"
git -C "$REPO_DIR" add "$OUTPUT"
git -C "$REPO_DIR" commit -m "Add encrypted secret: $REL_OUTPUT"
echo "Committed: $REL_OUTPUT"
