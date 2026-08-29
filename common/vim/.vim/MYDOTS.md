# MYDOTS — Vim setup guide

Everything about this setup lives in `~/.vimrc` (the only main config — vim
reads that file, not `~/.vim/init.vim`) and `~/.vim/` (plugins). This document
explains what's active, how it works, and how to use it.

## Keybindings — what's been changed from shipped defaults

Leader is the default `\`.

### Editing / text

| Keys | Action | Notes |
|------|--------|-------|
| `F2` | Toggle NERDTree file sidebar | |
| `Q` | Reflow text (`gq`) | Freed from Ex mode, which is basically useless |
| `p` (visual mode) | Replace selection with last-pasted text without clobbering the paste register | Lets you paste over multiple things in a row |
| `w!!` (command mode) | Save file with sudo | "forgot to open vim with sudo" rescue |
| `\y` | Send last-yanked text to Clipper (`nc localhost 8377`) | Cross-machine clipboard sharing; requires Clipper running |

### coc.nvim (code intelligence)

These follow recommendations from the coc example config, defining behavior
you don't get with the plugin alone:

| Keys | Action |
|------|--------|
| `Tab` / `S-Tab` | Next / previous completion item (or a real `<Tab>` insert if the cursor is before whitespace; `<C-Space>`-style refresh otherwise) |
| `Enter` | Accept the selected completion item, or insert a plain newline |
| `gd` | Go to definition |
| `gy` | Go to type definition |
| `gi` | Go to implementation |
| `gr` | Find references |
| `K` | Show docs in preview window (falls back to built-in keyword lookup when no LSP covers the buffer) |
| `\rn` | Rename symbol under cursor |
| (hover) | Holding the cursor on a symbol highlights where it's used (`CursorHold` autocmd) |

### Theme switching

| Keys / command | Action |
|----------------|--------|
| `:DotTheme gruvbox` | Switch to gruvbox (colorscheme + airline) |
| `:DotTheme codedark` | Switch to vim-code-dark |
| `:DotTheme <Tab>` | Tab-complete the theme name |
| `\tg` | gruvbox |
| `\tc` | vim-code-dark |

Every switch applies the colorscheme **and** the matching
[vim-airline](#active-plugins-bundle) statusline theme, and echoes a
confirmation. An unknown name (e.g. `:DotTheme bogus`) prints the available
options and leaves the theme untouched.

## Theme switching — how it works

Two colorschemes are installed:

| Theme           | Colorscheme name | Airline theme |
|-----------------|------------------|---------------|
| morhetz/gruvbox | `gruvbox`        | `gruvbox`     |
| vim-code-dark   | `codedark`       | `codedark`    |

- The chosen theme is written to `~/.vim/.theme` (plain text, one line) and
  re-applied at startup. If that file is missing or has an unrecognized value,
  it defaults to `gruvbox`.
- The block in `~/.vimrc` right after `set t_Co=256` defines `s:themes` (theme
  → colorscheme/airline names), `s:LoadTheme()` (reads the restored name),
  `s:SetTheme()` (validates, sets `g:airline_theme`, enables
  `g:gruvbox_italic`, runs `:colorscheme`, persists), the `:DotTheme` command
  with completion, the `\tg` / `\tc` maps, and the startup `call
  s:SetTheme(s:LoadTheme())`.
- `g:airline_theme` is deliberately never set anywhere else in `~/.vimrc` —
  setting it after the switcher (as an old `molokai` line did) desyncs the
  statusline from the colorscheme.
- To revert without the switcher, delete `~/.vim/.theme` and replace
  `call s:SetTheme(s:LoadTheme())` with e.g. `colorscheme xoria256`
  (still present in `~/.vim/colors/`).

## Plugin manager: Pathogen

- `~/.vim/autoload/pathogen.vim` — the manager (activated by
  `call pathogen#infect()` at the top of `~/.vimrc`).
- `~/.vim/bundle/` — every directory here is automatically loaded as a plugin.
  Add a plugin by cloning it there; remove it by deleting the directory.

## Active plugins (`~/.vim/bundle/`)

| Plugin | What it does | How to use |
|--------|--------------|------------|
| `gruvbox` | Retro-groove dark colorscheme | `:DotTheme gruvbox` or `\tg` |
| `vim-code-dark` | VS Code Dark+ colorscheme | `:DotTheme codedark` or `\tc` |
| `coc.nvim` | Completion + LSP code intelligence | see [keybinding table](#cocnvim-code-intelligence) above |
| `nerdtree` | File-tree sidebar | `F2` toggles it |
| `vim-airline` + `vim-airline-themes` | Statusline with powerline glyphs; theme follows your colorscheme | automatic (`g:airline_powerline_fonts = 1`) |
| `vim-fugitive` | Git integration inside vim | `:Git status`, `:Git blame`, `:Gdiffsplit`, … |
| `vim-gitgutter` | Added/changed/removed markers in the gutter | automatic; `:GitGutterToggle` to disable |
| `vim-scala` | Scala syntax highlighting / indent | automatic for `.scala` files |
| `vim-sensible` | Sane defaults | automatic |

## coc.nvim notes

- Configured in `~/.vimrc` to install `coc-json`, `coc-tsserver`, `coc-pyright`
  automatically (already done on 2026-08-28; they live in
  `~/.config/coc/extensions/`). Add more by appending to
  `g:coc_global_extensions` in `~/.vimrc` or with `:CocInstall <ext>`.
- Requires `node` on your PATH (managed by nvm here).
- Management: `:CocInfo`, `:CocList extensions`, `:CocCommand <name>`.

## Other `~/.vimrc` settings worth knowing

- **Tabs**: `expandtab`, 2-space tabs (filetypes may override).
- **Numbers**: hybrid — absolute current line, relative everywhere else.
- **Search**: incremental + highlighted (`hlsearch`).
- **Backspace**: works over indent, EOL, insert-start like everywhere else.
- **clipper**: `\y` sends yanks to `localhost:8377` (see keybinding table).

## Files in `~/.vim` and `~`

```
~/.vimrc            main config (the ONLY vim config; edit this one)
~/.vim/.theme       persisted theme choice, one line: gruvbox | codedark
~/.vim/autoload/pathogen.vim    plugin manager
~/.vim/bundle/      all installed plugins (add/remove to change your setup)
~/.vim/colors/xoria256.vim   old default colorscheme, kept as a fallback
~/.vim/.netrwhist   vim's netrw history (auto-generated, regenerates itself)
~/.vim/MYDOTS.md    this file
```

## Cleaned up on 2026-08-28

These were found and removed; delete this section whenever it stops being
useful:

- `~/.vim/init.vim` — stale duplicate of the config that nothing sourced.
- `~/.vim/autoload/plug.vim` + `~/.vim/plugged/` (vim-plug dup of vim-scala) —
  inert leftovers; nothing called `plug#begin()` and pathogen never scans
  `plugged/`.
- `~/.vim/bundle/neocomplete.vim` — obsolete completion engine, superseded by
  coc.nvim (and wasn't even enabled; its startup flag was never set).
- `~/.vim/plugin/` — empty directory.
- `let g:airline_theme='molokai'` in `~/.vimrc` — overrode the DotTheme
  switcher on every startup, pinning the statusline to molokai regardless of
  colorscheme. Removed.
- **coc.nvim was never installed** even though `~/.vimrc` configures it, which
  meant `<Tab>`, `<CR>`, and the `CursorHold` reference-highlighting autocmd
  all threw errors on every use. Installed (release branch), and the three LSP
  extensions initialized.