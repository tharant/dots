# Stow Adopt Workflow

Use `stow --adopt` to bring existing `$HOME` config files into the repo.

## Steps

1. **Create the target package path in the repo** with an empty file:

   ```bash
   mkdir -p linux/tmux
   touch linux/tmux/.tmux.conf
   ```

2. **Run stow with `--adopt`:**

   ```bash
   stow --adopt -d ~/.dots/linux -t ~ tmux
   ```

   Stow moves the real file from `$HOME` into the repo and replaces it with a symlink.

3. **Review the adopted content:**

   ```bash
   git diff
   ```

4. **Commit** once satisfied:

   ```bash
   git add linux/tmux/.tmux.conf
   git commit -m "Adopt tmux config into linux stow package"
   ```

## Notes

- The empty file you create in step 1 is overwritten by `--adopt` with the real file from `$HOME`.
- Always review `git diff` before committing — `--adopt` pulls in whatever is on disk.
- Use `--no-folding` if you want symlinks per-file rather than per-directory.
