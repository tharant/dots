# MYDOTS — Vim setup guide

Everything about this setup lives in `~/.vimrc` (the only main config — vim
reads that file, not `~/.vim/init.vim`) and `~/.vim/` (plugins). This document
explains what's active, how it works, and how to use it.

## Requirements

- **coc.nvim** needs `node` >= 22.15 on your PATH, plus Neovim >= 0.8 or Vim
  >= 9.0.0438. On old distros (e.g. Debian bookworm ships Vim 9.0 and Node 18)
  use Neovim from upstream so coc still works — or skip coc entirely. When
  `node` is missing, `.vimrc` detects it and skips coc (plugin, mappings and
  all) so startup stays clean; installing node and restarting vim re-enables
  it. node comes from fnm via the `runtimes` CLI (see
  [docs/direnv-runtimes.md](../../docs/direnv-runtimes.md) in the repo).
- A clipboard helper (`pbcopy`, `wl-copy`, `xclip`, `win32yank.exe` or
  `clip.exe`) for `\y` and for the `clipboard=unnamedplus` shortcut. Without
  one vim just keeps its internal clipboard — no errors, no maps bound.

## Keybindings — what's been changed from shipped defaults

Leader is the default `\`.

### Editing / text

| Keys | Action | Notes |
|------|--------|-------|
| `F2` | Toggle NERDTree file sidebar | |
| `Q` | Reflow text (`gq`) | Freed from Ex mode, which is basically useless |
| `p` (visual mode) | Replace selection with last-pasted text without clobbering the paste register | Lets you paste over multiple things in a row |
| `w!!` (command mode) | Save file with sudo | "forgot to open vim with sudo" rescue |
| `\y` | Copy last-yanked text to the system clipboard | Uses whichever helper is found (`pbcopy`, `wl-copy`, `xclip`, `win32yank.exe`, `clip.exe`); only bound if one exists |

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
[vim-airline](#active-plugins-vimplugged) statusline theme, and echoes a
confirmation. An unknown name (e.g. `:DotTheme bogus`) prints the available
options and leaves the theme untouched. Startup re-applies the saved theme
silently — no message, no keypress needed.

## Theme switching — how it works

Two colorschemes are installed:

| Theme           | Colorscheme name | Airline theme |
|-----------------|------------------|---------------|
| morhetz/gruvbox | `gruvbox`        | `gruvbox`     |
| vim-code-dark   | `codedark`       | `codedark`    |

- The chosen theme is written to `~/.vim/.theme` (plain text, one line) and
  re-applied at startup. If that file is missing or has an unrecognized value,
  it defaults to `gruvbox`. (The file is generated on first use — the repo
  doesn't ship one.)
- The block in `~/.vimrc` right after the true-color setup defines `s:themes`
  (theme → colorscheme/airline names), `s:LoadTheme()` (reads the restored name),
  `s:SetTheme()` (validates, sets `g:airline_theme`, enables
  `g:gruvbox_italic`, runs `:colorscheme`, persists; an optional second
  argument silences the confirmation), the `:DotTheme` command
  with completion, the `\tg` / `\tc` maps, and the startup `call
  s:SetTheme(s:LoadTheme(), 1)` — the `1` is the quiet flag, so opening vim
  doesn't echo anything.
- `g:airline_theme` is deliberately never set anywhere else in `~/.vimrc` —
  setting it after the switcher (as an old `molokai` line did) desyncs the
  statusline from the colorscheme.
- To revert without the switcher, delete `~/.vim/.theme` and replace
  `call s:SetTheme(s:LoadTheme(), 1)` with e.g. `colorscheme xoria256`
  (still present in `~/.vim/colors/`).

## Plugin manager: vim-plug

- `~/.vim/autoload/plug.vim` — the manager (vendored single file, activated by
  `call plug#begin('~/.vim/plugged')` in `~/.vimrc`).
- `~/.vim/plugged/` — where plugins land; not tracked in the repo, it fills
  in on first launch. Add a plugin by adding a `Plug 'author/name'` line
  between `plug#begin` and `plug#end`, then `:PlugInstall`. Remove a plugin by
  deleting its line and running `:PlugClean`.
- Versions float: each `Plug` line tracks the plugin's default branch (coc is
  pinned to its `release` branch). There are no checked-in plugin copies.
- Missing plugins are installed automatically on first launch
  (`PlugInstall --sync` runs once, then the config re-sources itself).

## Active plugins (`~/.vim/plugged/`)

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
  automatically. Add more by appending to
  `g:coc_global_extensions` in `~/.vimrc` or with `:CocInstall <ext>`.
- Requires `node` >= 22.15 on your PATH (see Requirements above); the plugin
  itself needs Neovim >= 0.8 or Vim >= 9.0.0438. On distros too old for either
  (e.g. Debian bookworm, which ships Vim 9.0 / Node 18), install Neovim from
  upstream and use this same setup there.
- Management: `:CocInfo`, `:CocList extensions`, `:CocCommand <name>`.

## Other `~/.vimrc` settings worth knowing

- **Tabs**: `expandtab`, 2-space tabs (filetypes may override).
- **Numbers**: hybrid — absolute current line, relative everywhere else.
- **Search**: incremental + highlighted (`hlsearch`).
- **Backspace**: works over indent, EOL, insert-start like everywhere else.
- **Colors**: true color (`termguicolors`) when `$COLORTERM` says so (or you're
  on kitty/alacritty), 256 colors otherwise; airline follows either way.
- **Clipboard**: `clipboard=unnamedplus` when a clipboard helper is found (so
  yanks go straight to the system clipboard); `\y` re-sends the last yank (see
  keybinding table).

## Files in `~/.vim` and `~`

```
~/.vimrc            main config (the ONLY vim config; edit this one)
~/.vim/.theme       persisted theme choice, one line: gruvbox | codedark
                    (generated by the theme switcher, not tracked)
~/.vim/autoload/plug.vim      plugin manager (vendored vim-plug)
~/.vim/plugged/     installed plugins (generated on first launch)
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
  `plugged/`. (Superseded later the same day — vim-plug is the real manager
  now, see below.)
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
- **Pathogen → vim-plug (2026-08-28)** — the whole `~/.vim/bundle/` tree of
  vendored clones went away in favor of the manager: `plug.vim` is now the
  single vendored file in `~/.vim/autoload/`, and plugins install into
  `~/.vim/plugged/` on first launch. `~/.vim/.theme` is untracked too — the
  theme switcher writes it whenever you run `\tg` / `\tc`, and you get gruvbox
  until then. coc.nvim's node requirement (>= 22.15) is why the requirement
  note above exists.