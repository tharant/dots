# dots-encrypt(1)

## Name

`dots-encrypt` — hybrid-encrypt a plaintext file as paired age artifacts

## Synopsis

```
dots-encrypt <plaintext-file> [output.age]
```

## Description

`dots-encrypt` turns one plaintext file into **two** age artifacts that encrypt
the same content, so that either one alone can restore it:

| Artifact | Encrypted with | Used by |
|---|---|---|
| `<output>.age` | The public keys in `secrets/recipients.txt` (`age -R`) | Established machines holding the matching identity at `~/.age/keys.txt` |
| `<output>.phrase.age` | An interactive passphrase (`age -p`) | Fresh machines with no age identity yet, e.g. a `curl | bash` bootstrap |

The age file format cannot combine a recipient stanza with a passphrase stanza
(encrypting with both `-p` and `-R` is rejected), so two separate artifacts
replicate the "either one unlocks it" property.

The work happens in three stages, each guarding against leaving bad ciphertext
behind:

1. **Recipient encryption** runs first, so all passphrase prompting is
   confined to the final stage. On failure the script exits before writing
   anything else.
2. **Passphrase encryption** writes the `.phrase.age` copy. An exit trap removes
   this partial file whenever the script exits during the step, and on a failed
   passphrase encryption (a non-zero exit from `age -p`) the recipient copy is
   removed too. A signal-driven abort — Ctrl-C at the `age -p` prompt, the usual
   way to back out — is the exception: the trap still removes the passphrase
   copy, but the `rm` of the recipient copy belongs to the failure branch, which
   a signal skips, so the key-only artifact from stage 1 does survive an
   interrupt. Only a non-zero *exit* takes it away.
3. **Round-trip verification** decrypts both artifacts in turn (with
   `~/.age/keys.txt` for the first, and a re-entered passphrase for the second)
   and compares each result against the original with `diff -q`. Any decrypt
   failure or byte mismatch deletes *both* artifacts and exits non-zero, so a
   bad ciphertext is never left in the tree — let alone committed.

If verification passes, the two artifacts are staged and committed
automatically; commit failures are non-fatal.

### Output path inference

With only one argument, the destination is inferred from the input path:

| Input under | Output |
|---|---|
| `~/.ssh/*` | `secrets/ssh/<relative-path>.age` |
| `~/.config/tokens/*` | `secrets/tokens/<relative-path>.age` |

Anything else triggers `Could not infer target. Enter output path:` and reads
the answer from standard input; an empty answer is fatal. Because the answer is
read from standard input, piping input into the script can supply it. (The
prompt text itself is written to standard error, and bash's `read` only
displays it when standard input is a terminal.)

If the second argument is given but does not end in `.age`, the suffix is
appended. The passphrase copy is always written next to the recipient copy,
with the `.age` suffix replaced by `.phrase.age`: an output of `foo.age` gets a
sibling `foo.phrase.age`.

### Overwrites

Existing ciphertext is never overwritten silently. Before any encryption, both
target paths are checked; for each one that already exists the script prints

```
Warning: <relative path> exists. Overwrite? [y/N]
```

and aborts with `Aborted.` (exit status 1) unless the reply is exactly `y` or
`Y`. **There is no `--force` flag** — nothing bypasses this prompt. It is what
stands between a wrong-target overwrite and the loss of the mapping between a
committed artifact and the key it was made from.

## Options

No options are accepted; both arguments are positional.

- `<plaintext-file>` — file to encrypt. Must exist as a regular file. It is
  never modified or deleted by this script.
- `[output.age]` — optional destination for the recipient copy (see above).

## Environment

- `HOME` — resolves the two inference roots (`~/.ssh`, `~/.config/tokens`) and
  the identity path `~/.age/keys.txt`.
- `TMPDIR` — affects where the two `mktemp` scratch files used by verification
  land. They are removed on exit.

There are no dotfiles-specific environment variables.

## Exit status

- `0` — both artifacts written; the auto-commit succeeded or was skipped with a
  warning. If `~/.age/keys.txt` is absent on this machine, the age-key
  round-trip verification is skipped (see [Files](#files)), so exit status 0 can
  mean only the passphrase artifact was verified.
- `1` — no arguments at all (a usage line is printed; a third or later argument
  is silently ignored, not an error); input missing or not a regular file; `age` not on
  `PATH`; `secrets/recipients.txt` missing; no output path inferable and none
  entered at the prompt; overwrite declined; recipient encryption failure;
  passphrase encryption failure or abort; either verification (decrypt or
  `diff`) failure.

## Files

- `secrets/recipients.txt` — age public keys of every machine allowed to
  decrypt. Required to exist; if it is missing the script exits before doing
  any work, advising `age-keygen -o ~/.age/keys.txt` and adding the public key
  to this file.
- `~/.age/keys.txt` — age identity used to verify the recipient artifact. If it
  is absent on this machine, that verification is **skipped** with a warning
  suggesting `./scripts/decrypt.sh` be run on a machine that has the identity;
  the passphrase artifact is still verified. The private key itself must never
  be committed to this repository.
- `secrets/ssh/*`, `secrets/tokens/*` — default output locations, mirroring the
  targets that `dots-decrypt(1)` maps back on install.
- `<output>.age`, `<output>.phrase.age` — the two written artifacts. The script
  sets `umask 077` before doing any work, so both are created with mode `600` on
  the machine that runs it. That is the counterpart to what `dots-decrypt(1)`
  enforces on the plaintext it writes back (`600`, into a `700` directory) and to
  the mode `dots-verify(1)` checks private keys for — it reports a key that is
  not `600`, but it changes no modes; the enforcement on install is
  `dots-decrypt(1)`'s. The `600` mode does not travel with the ciphertext: git
  records only the executable bit (the artifacts are committed as `100644`), so
  a fresh clone checks them out as `0666 & ~umask` — `0644` under a normal
  umask — on every machine other than the one where `dots-encrypt` ran.
  Group- and world-readable ciphertext in a clone is therefore possible; what
  keeps the plaintext private is that only a holder of the age identity or the
  passphrase can decrypt, and that `dots-decrypt(1)` re-imposes `600` when it
  writes the material back to its target.

## Diagnostics

Progress and error messages go to standard output. The two interactive prompts
(the overwrite prompt and the `Could not infer target` prompt) are written to
standard error by bash's `read`, which also only displays them when standard
input is a terminal; their answers are always read from standard input. Notable
messages:

- `Warning: <relative path> exists. Overwrite? [y/N]` — see
  [Overwrites](#overwrites). Both paths are checked before any encryption; the
  second prompt only appears if the first is accepted.
- `Warning: No ~/.age/keys.txt on this machine — skipping age-key verify.` —
  the identity is not present here, so only the passphrase copy was round-trip
  checked.
- `Warning: could not stage <file> — commit manually.` /
  `Warning: files encrypted, but commit failed — commit manually.` — the
  auto-commit is deliberately non-fatal: on a fresh machine without a
  configured git identity, the ciphertext having already been written must not
  fail the script.

## Intended usage

This is the *write* half of the repo's secrets model: use it whenever you need
to add or update an encrypted secret in the repo — a new SSH key, a rotated
token, an edited credential. Its mirror image is [dots-decrypt(1)](dots-decrypt.md),
which reads these same artifacts back onto a machine during bootstrap
([dots-setup(1)](dots-setup.md) calls it during the `curl | bash` flow, and it
is also reachable via `just decrypt`). [dots-verify(1)](dots-verify.md) checks
that symlinks are in place and that each artifact has a plaintext counterpart
at its target after deployment — it never decrypts anything, so it can confirm
a target exists but not that it decrypts cleanly from these artifacts; it does
not create secrets.

The dual-artifact output is what makes the repo's bootstrap story work: the
key-only copy covers every machine that already has the age identity, while the
passphrase copy is what gets a brand-new machine — which has neither the
identity nor a prior clone — through `scripts/setup.sh`. After encrypting, the
two artifacts are staged and committed for you, so the usual loop is just:
edit the plaintext, run `dots-encrypt`, push. The `just encrypt FILE` wrapper
interpolates the file into its recipe quoted, so the target is inferred the
same way — provided the path you pass needs no tilde expansion (see
[Examples](#examples)).

## Examples

Encrypt an SSH private key, letting the script infer
`secrets/ssh/id_ed25519.age` plus its passphrase copy:

```
./scripts/encrypt.sh ~/.ssh/id_ed25519
```

Encrypt a token file to an explicit destination (the `.age` suffix is appended
if missing):

```
./scripts/encrypt.sh ~/.config/tokens/github.pat secrets/tokens/github.pat.age
```

Via the just wrapper:

```
just encrypt "$HOME/.ssh/id_ed25519"
```

The recipe interpolates its argument inside double quotes
(`./scripts/encrypt.sh "{{ FILE }}"`), so `just` performs no tilde expansion
and the argument reaches the script literally: a leading `~` is not expanded
by the recipe shell either, and the run fails with `Error: File not found`.
Supply a path that is already expanded — as above, or repo-relative — rather
than a bare tilde path.

Each run asks for the passphrase **three** times: `age -p` prompts for it
twice (entry, then confirmation) while encrypting the `.phrase.age` copy, and
a third prompt is needed when that copy is decrypted again during
verification.