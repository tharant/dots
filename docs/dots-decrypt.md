# dots-decrypt(1)

## Name

**dots-decrypt** — decrypt all age artifacts in the dots repo to their target locations

## Synopsis

```
dots-decrypt
```

Invoked as `./scripts/decrypt.sh` from a checkout of the repository, or as
`just decrypt`. Takes no command line arguments — any arguments given are
ignored. All behavior is controlled by environment variables.

## Description

Every secret in the repository is stored under `secrets/` as **two age
artifacts** encrypting the same plaintext:

| Artifact | Encrypted to | Used on |
| --- | --- | --- |
| `X.age` | the recipients in `secrets/recipients.txt` | established machines holding the matching private identity |
| `X.phrase.age` | a passphrase | fresh machines with no identity yet (the `curl \| bash` bootstrap) |

`dots-decrypt` walks `secrets/`, finds every `*.age` file, and decrypts each
one to a target file in the home directory. The target is chosen by the first
path component below `secrets/`:

| Artifact | Target |
| --- | --- |
| `secrets/ssh/X.age` | `~/.ssh/X` |
| `secrets/tokens/X.age` | `~/.config/tokens/X` |

For each artifact the script tries, in order:

1. the age identity (if one exists on this machine) against `X.age`;
2. the passphrase against `X.phrase.age`;
3. the passphrase against `X.age` itself — this covers legacy secrets that
   were stored as a single passphrase-only artifact.

Passphrase copies (`X.phrase.age`) are never decrypted on their own; they are
skipped as primary artifacts and only consulted as the fallback for their
sibling.

Each decryption is written to a temporary file created next to the target, the
temporary file is `chmod`ed 600, and only then is it renamed over the target.
If `age` fails, the temporary file is removed and the existing target is left
untouched. The target directory is created with `mkdir -p` if needed and is
set to mode 0700 before anything is decrypted into it.

Unless `FORCE` is set, an artifact whose target already exists and is strictly
newer than **both** of its artifacts is skipped with the message
`Skipping (up to date): ...`. Concretely, decryption is skipped when the
target exists, the target is newer than `X.age`, and there is no passphrase
copy — or the target is also newer than `X.phrase.age`. The comparison is a
freshness check on modification times, not a content check: if you edit a
decrypted file directly, it becomes newer than the artifacts and will not be
overwritten on the next run.

## Options

None. The script takes no flags or subcommands; the equivalent of "force" is
supplied through the `FORCE` environment variable (and through
[dots-setup(1)](dots-setup.md)'s `--force` flag, which propagates it).

## Environment

- `AGE_IDENTITY` — path to the age identity file. Defaults to
  `~/.age/keys.txt`. If that file does not exist the script prints
  `No age identity found at <path> — will prompt for passphrase.` and relies
  on the passphrase fallback instead.
- `FORCE` — set to `true` to re-decrypt even when the freshness check would
  skip the artifact. Any other value, including unset, leaves the check
  active.
- `HOME` — used to resolve the default identity path (`~/.age/keys.txt`) and
  every target directory (`~/.ssh`, `~/.config/tokens`).

## Exit status

- **0** — all artifacts were processed. This includes the cases where no
  `.age` files were found at all and where every target was skipped as up to
  date.
- **other than 0** — the script runs with `set -e` and stops at the first
  failure, with status 1. This is the case when `age` is not installed, a
  decryption failed (wrong passphrase, aborted prompt, corrupt artifact), a
  rename failed, or no artifact existed for a `.age` file; the exit status of
  `age` itself is swallowed (a failing decryption is caught by an `if !`
  guard and turned into `return 1`) and never propagates to the caller.
  Artifacts later in the `secrets/` tree are not processed, and targets
  already written stay in place.

## Files

- `scripts/decrypt.sh` — the script itself. It derives `secrets/` from its own
  location, so the working directory is irrelevant; the only requirement is
  that the script file itself live in a checkout of the repository (for
  example invoked by absolute path, as [dots-setup(1)](dots-setup.md) does).
- `secrets/*.age`, `secrets/*/*.age` — encrypted artifacts. Artifacts in
  subdirectories with no target mapping are warned about and skipped.
- `secrets/recipients.txt` — age public key(s) used by
  [dots-encrypt(1)](dots-encrypt.md); not read by this script, but it defines
  which identities can decrypt the `X.age` copies.
- `~/.age/keys.txt` — default age identity, generated with
  `age-keygen -o ~/.age/keys.txt`. This key must never be committed to the
  repo.
- `~/.ssh/`, `~/.config/tokens/` — target directories for the `ssh/` and
  `tokens/` secret subdirectories. Created with `mkdir -p` if missing, and
  forced to mode 0700 with `chmod 700` before every artifact that is actually
  decrypted into them — an existing directory with looser permissions is
  silently tightened, and a run in which every target is skipped as up to
  date leaves the mode alone.

## Intended usage

`decrypt.sh` is one of four sibling scripts — [setup](dots-setup.md),
[encrypt](dots-encrypt.md), **decrypt**, and [verify](dots-verify.md) — and is
the step that turns the encrypted artifacts in `secrets/` into working config
files in your home directory. It is reached for in two situations:

- **Bootstrap:** on a fresh machine it is called by
  [dots-setup(1)](dots-setup.md) (which itself comes from `curl …/setup.sh |
  bash`). With no `~/.age/keys.txt` present, each
  `X.phrase.age` artifact supplies the fallback path: the passphrase you type
  is the only credential needed to materialize your SSH keys and tokens.
- **Re-sync after a pull:** after `git pull` brought in a newly encrypted
  secret, run `just decrypt` to materialize it (`just restow` /
  `./scripts/setup.sh --restow` only re-stows and does **not** decrypt; only
  the full bootstrap and `setup.sh --force` call the decrypt step). The
  freshness check means the run is cheap when nothing changed;
  `FORCE=true ./scripts/decrypt.sh` re-decrypts everything when you know the
  artifacts moved but their timestamps did not help.

Decryption only places plaintext on disk; it does not create symlinks.
Each decrypted file is written straight to its final location (`~/.ssh/X`,
`~/.config/tokens/X`), so there is nothing for stow to put in place of it;
the stow step in [dots-setup(1)](dots-setup.md) only manages the checked-in
config files (the `ssh` package, for instance, manages `~/.ssh/config` but
not the private keys decrypt.sh writes). See the
[stow adopt workflow](stow-adopt-workflow.md) for how pre-existing files are
brought under management. To add a new secret, use
[dots-encrypt(1)](dots-encrypt.md), which produces the paired artifacts this
script expects and commits them.

Two things to keep in mind:

- **The fallback is a hard dependency on a fresh machine.** If the identity
  doesn't match (key rotated, wrong machine) you get
  `Identity did not match, falling back to passphrase...`; if the passphrase
  copy is then also wrong, the script prints
  `Error: passphrase decryption failed for <name>` and exits non-zero without
  processing the rest of the tree.
- **Unmapped subdirectories are skipped with a warning**, not an error. If you
  add a new directory under `secrets/`, add a `target_dir_for` entry in
  `scripts/decrypt.sh` (and a mapping in `scripts/encrypt.sh` if it produces
  artifacts there) or your secrets silently don't land anywhere.

## Examples

Established machine with `~/.age/keys.txt` present:

```
$ ./scripts/decrypt.sh
Using age identity: /Users/jlambert/.age/keys.txt
Decrypting: ssh/id_ed25519 -> /Users/jlambert/.ssh/id_ed25519
Decrypting: tokens/gh_token -> /Users/jlambert/.config/tokens/gh_token
Decrypted 4 file(s).
```

Fresh machine — no identity, so the passphrase is asked for interactively by
age (this is the path taken inside `curl … | bash`):

```
$ ./scripts/decrypt.sh
No age identity found at /home/alice/.age/keys.txt — will prompt for passphrase.
Decrypting: ssh/id_ed25519 -> /home/alice/.ssh/id_ed25519
```

Force re-decryption of everything, ignoring timestamps:

```
$ FORCE=true ./scripts/decrypt.sh
```

The same thing through `just`:

```
$ just decrypt
```

A run that hits an up-to-date target and an unmapped directory:

```
$ ./scripts/decrypt.sh
Using age identity: /Users/jlambert/.age/keys.txt
Skipping (up to date): ssh/id_ed25519 -> /Users/jlambert/.ssh/id_ed25519
Warning: No target mapping for subdir 'gpg', skipping gpg/pubkey.age
Decrypting: tokens/gh_token -> /Users/jlambert/.config/tokens/gh_token
Decrypted 6 file(s).
```