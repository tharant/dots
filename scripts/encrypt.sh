#!/usr/bin/env bash
set -euo pipefail
umask 077

# Encrypt a file as two age artifacts:
#   <output>.age         — encrypted to the recipients in secrets/recipients.txt
#   <output>.phrase.age  — encrypted with a passphrase (fresh-machine fallback)
# Either artifact can decrypt the original: established machines use the age
# identity at ~/.age/keys.txt, a fresh curl|bash machine uses the passphrase.
# Usage: ./scripts/encrypt.sh <plaintext-file> [output.age]

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
    echo "Error: age is not installed. Install with: brew / apt / apk / pkg install age"
    exit 1
fi

if [[ ! -f "$RECIPIENTS_FILE" ]]; then
    echo "Error: $RECIPIENTS_FILE not found."
    echo "Run 'age-keygen -o ~/.age/keys.txt' and add the public key to secrets/recipients.txt."
    exit 1
fi

# Reverse TARGET_MAP: source directory -> secrets subdirectory
# (a case statement instead of an assoc array keeps this bash 3.2 compatible)
# Determine output path
if [[ $# -ge 2 ]]; then
    OUTPUT="$2"
else
    # Auto-infer from input path
    INPUT_ABS="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
    sub_dir=""
    rel=""
    case "$INPUT_ABS" in
        "$HOME"/.ssh/*)
            sub_dir="ssh"
            rel="${INPUT_ABS#"$HOME"/.ssh/}"
            ;;
        "$HOME"/.config/tokens/*)
            sub_dir="tokens"
            rel="${INPUT_ABS#"$HOME"/.config/tokens/}"
            ;;
    esac

    if [[ -n "$sub_dir" ]]; then
        OUTPUT="$REPO_DIR/secrets/$sub_dir/$rel.age"
    else
        OUTPUT=""
    fi

    if [[ -z "$OUTPUT" ]]; then
        read -rp "Could not infer target. Enter output path: " OUTPUT
        if [[ -z "$OUTPUT" ]]; then
            echo "Error: No output path provided."
            exit 1
        fi
    fi
fi

case "$OUTPUT" in
    *.age) ;;
    *) OUTPUT="$OUTPUT.age" ;;
esac
PHRASE_OUTPUT="${OUTPUT%.age}.phrase.age"

# Refuse to silently overwrite ciphertext — a wrong-target overwrite loses the
# mapping between the committed artifact and the key it was made from.
for f in "$OUTPUT" "$PHRASE_OUTPUT"; do
    if [[ -e "$f" ]]; then
        rel_f="${f#"$REPO_DIR"/}"
        read -rp "Warning: $rel_f exists. Overwrite? [y/N] " reply
        case "$reply" in
            y|Y) ;;
            *) echo "Aborted."; exit 1 ;;
        esac
    fi
done

mkdir -p "$(dirname "$OUTPUT")"

echo "Encrypting to recipients (age key)"
# Run the non-interactive recipient encryption first so the passphrase prompt
# happens exactly once, at the end.
if ! age -R "$RECIPIENTS_FILE" -o "$OUTPUT" "$INPUT"; then
    echo "Error: recipient encryption failed."
    exit 1
fi
echo "Encrypted: ${OUTPUT#"$REPO_DIR"/}"

# If the passphrase step is aborted, don't leave a lone key-only artifact behind
trap 'rm -f "$PHRASE_OUTPUT"' EXIT

echo "Encrypting with passphrase (fallback for fresh machines)"
if ! age -p -o "$PHRASE_OUTPUT" "$INPUT"; then
    echo "Error: passphrase encryption failed; removed $PHRASE_OUTPUT"
    rm -f "$OUTPUT"
    exit 1
fi
trap - EXIT
echo "Encrypted: ${PHRASE_OUTPUT#"$REPO_DIR"/}"

# Verify both artifacts round-trip to the original plaintext
TMPFILE="$(mktemp)"
TMPFILE2="$(mktemp)"
trap 'rm -f "$TMPFILE" "$TMPFILE2"' EXIT

echo "Verifying age-key artifact..."
if [[ -f "$HOME/.age/keys.txt" ]]; then
    if ! age -d -i "$HOME/.age/keys.txt" -o "$TMPFILE" "$OUTPUT"; then
        echo "Error: age-key artifact does not decrypt. Removing bad files."
        rm -f "$OUTPUT" "$PHRASE_OUTPUT"
        exit 1
    fi
    if ! diff -q "$INPUT" "$TMPFILE" >/dev/null 2>&1; then
        echo "Error: Decrypted file does not match original. Removing bad encrypted files."
        rm -f "$OUTPUT" "$PHRASE_OUTPUT"
        exit 1
    fi
else
    echo "Warning: No ~/.age/keys.txt on this machine — skipping age-key verify."
    echo "Run ./scripts/decrypt.sh on a machine with the identity to confirm."
fi

echo "Verifying passphrase artifact (re-enter passphrase)..."
TMPFILE="$TMPFILE2"
if ! age -d -o "$TMPFILE" "$PHRASE_OUTPUT"; then
    echo "Error: passphrase artifact does not decrypt. Removing bad files."
    rm -f "$OUTPUT" "$PHRASE_OUTPUT"
    exit 1
fi
if ! diff -q "$INPUT" "$TMPFILE" >/dev/null 2>&1; then
    echo "Error: Decrypted file does not match original. Removing bad encrypted files."
    rm -f "$OUTPUT" "$PHRASE_OUTPUT"
    exit 1
fi

echo "Verification passed."

# Auto-commit (non-fatal: a missing git identity on a fresh machine should not
# fail the script after the .age files have already been written)
REL_OUTPUT="${OUTPUT#"$REPO_DIR"/}"
REL_PHRASE="${PHRASE_OUTPUT#"$REPO_DIR"/}"
if ! git -C "$REPO_DIR" add "$OUTPUT" "$PHRASE_OUTPUT"; then
    echo "Warning: could not stage $REL_OUTPUT — commit manually."
elif ! git -C "$REPO_DIR" commit -m "Add encrypted secret: $REL_OUTPUT (+ passphrase copy)"; then
    echo "Warning: files encrypted, but commit failed — commit manually."
else
    echo "Committed: $REL_OUTPUT, $REL_PHRASE"
fi