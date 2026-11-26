# MYDOTS — Vim setup guide

Everything about this setup lives in `~/.vimrc` (the only main config — vim
reads that file, not `~/.vim/init.vim`) and `~/.vim/` (plugins). Neovim runs
a config kept in lockstep with this one: `~/.config/nvim/init.lua` — same
options, same keys, the same `:DotTheme` writing the same `~/.vim/.theme`,
plus a native statusline mirroring airline. This document explains what's
active, how it works, and how to use it.

## Requirements

- **coc.nvim** needs `node` >= 22.15 on your PATH, plus Neovim >= 0.8 or Vim
  >= 9.0.0438. On old distros (e.g. Debian bookworm ships Vim 9.0 and Node 18)
  use Neovim from upstream so coc still works — or skip coc entirely. When
  `node` is missing, `.vimrc` detects it and skips coc (plugin, mappings and
  all) so startup stays clean; installing node and restarting vim re-enables
  it. node comes from fnm via the `runtimes` CLI (see
  [docs/direnv-runtimes.md](../../docs/direnv-runtimes.md) in the repo).
- **Scala tooling** (`metals`) is optional: `.bashrc` gives coursier's bin dir
  a PATH entry when `~/.local/share/coursier/bin` exists, and the Scala
  client in `.vimrc` only wires up when the `metals` binary is found (see
  [Scala (Metals) via coc](#scala-metals-via-coc)). On Neovim the full
  nvim-metals setup needs nvim >= 0.11 (this box runs an upstream tarball; the
  stock Debian `nvim` is 0.10 and quietly skips it).
- A clipboard helper (`pbcopy`, `wl-copy`, `xclip`, `win32yank.exe` or
  `clip.exe`) for `\y` and for the `clipboard=unnamedplus` shortcut. Without
  one vim just keeps its internal clipboard — no errors, no maps bound.

## Keybindings — what's been changed from shipped defaults

Leader is the default `\` — in BOTH editors (nvim's leader was unified onto
the same backslash so every map below binds identically in `~/.vimrc` and
`~/.config/nvim/init.lua`).

### Editing / text

| Keys | Action | Notes |
|------|--------|-------|
| `F2` | Toggle NERDTree file sidebar | |
| `Q` | Reflow text (`gq`) | Freed from Ex mode, which is basically useless |
| `p` (visual mode) | Replace selection with last-pasted text without clobbering the paste register | Lets you paste over multiple things in a row |
| `w!!` (command mode) | Save file with sudo | "forgot to open vim with sudo" rescue |
| `<Esc>` | Clear search highlight | also in nvim; sensible's `<C-L>` keeps working |
| `<C-h>`/`<C-j>`/`<C-k>`/`<C-l>` | Move between splits | same keys in both editors (`<C-l>` still plain-left in insert) |
| `[b` / `]b` | Previous / next buffer | same keys in both editors |
| `\y` | Copy last-yanked text to the system clipboard | Uses whichever helper is found (`pbcopy`, `wl-copy`, `xclip`, `win32yank.exe`, `clip.exe`); only bound if one exists. nvim doesn't ship this map — its `clipboard=unnamedplus` already sends every yank to the system clipboard |

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
| `\ac` | Show code actions at the cursor (fixes, refactors) | |
| `\qf` | Apply the quickfix offered by the diagnostic at the cursor | |
| `\f` (visual) | Format the selection via the language server | |
| `[g` / `]g` | Jump to previous / next diagnostic | |
| (hover) | Holding the cursor on a symbol highlights where it's used (`CursorHold` autocmd) |

### Theme switching

| Keys / command | Action |
|----------------|--------|
| `:DotTheme default` | The dots default: xoria256 (airline `minimalist`) in vim, tokyonight-storm in nvim |
| `:DotTheme gruvbox` | Switch to gruvbox (colorscheme + airline) |
| `:DotTheme codedark` | Switch to vim-code-dark |
| `:DotTheme <Tab>` | Tab-complete the theme name |
| `\td` | default |
| `\tg` | gruvbox |
| `\tc` | vim-code-dark |

Every switch applies the colorscheme **and** the matching
[vim-airline](#active-plugins-vimplugged) statusline theme, and echoes a
confirmation. An unknown name (e.g. `:DotTheme bogus`) prints the available
options and leaves the theme untouched. Startup re-applies the saved theme
silently — no message, no keypress needed — and never writes the file, so
until you pick one you track the dots default (`default`).

**Neovim ships the same system**: `:DotTheme` with the same names,
`\td`/`\tg`/`\tc`, and the same default — with colorscheme files vendored
at `~/.config/nvim/colors/` (`gruvbox.vim`/`codedark.vim` are copies of the
vim plugins' `colors/`, refresh them after a `:PlugUpdate`;
`tokyonight-storm.vim` is folke/tokyonight.nvim's `extras/vim` build, pinned
in its header, Apache-2.0 in `LICENSE.tokyonight`). `default` is the one
name that maps to a different scheme per editor. Both editors write
the same `~/.vim/.theme`, so the tmux bar and the trueline prompt follow
theme switches from **either** editor; if `~/.vim` doesn't exist (an
nvim-only machine), nvim persists to `~/.local/state/nvim/.theme` instead.

## Theme switching — how it works

Three themes:

| Theme (`:DotTheme`) | vim colorscheme | nvim colorscheme | Airline theme |
|---------------------|-----------------|------------------|---------------|
| `default`           | `xoria256` (`~/.vim/colors`) | `tokyonight-storm` (vendored) | `minimalist` |
| `gruvbox`           | `gruvbox`       | `gruvbox`        | `gruvbox`     |
| `codedark`          | `codedark`      | `codedark`       | `codedark`    |

- An explicit `:DotTheme` choice is written to `~/.vim/.theme` (plain text,
  one line) and re-applied at startup. If that file is missing or has an
  unrecognized value, `default` applies. Startup never writes the file (the
  repo doesn't ship one), so a machine with no choice follows the dots
  default. Machines that predate this kept a `.theme` the old startup wrote
  automatically: run `:DotTheme default` (or `\td`) once to switch.
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

## coc.nvim notes

- Configured in `~/.vimrc` to install `coc-json`, `coc-tsserver`, `coc-pyright`
  automatically. Add more by appending to
  `g:coc_global_extensions` in `~/.vimrc` or with `:CocInstall <ext>`.
- Requires `node` >= 22.15 on your PATH (see Requirements above); the plugin
  itself needs Neovim >= 0.8 or Vim >= 9.0.0438. On distros too old for either
  (e.g. Debian bookworm, which ships Vim 9.0 / Node 18), install Neovim from
  upstream and use this same setup there.
- Management: `:CocInfo`, `:CocList extensions`, `:CocCommand <name>`.

### Scala (Metals) via coc

`.scala` / `.sbt` buffers are served by a **generic coc language-server
client** that drives the Metals binary installed by Coursier. Why not the
usual `coc-metals` extension? It is deprecated and unmaintained — no coc
extension covers Metals anymore, and upstream only recommends nvim-metals
(Neovim) or plain LSP clients for Vim. So the split is:

- **Neovim — primary, full experience.** `~/.config/nvim` bootstraps
  `nvim-metals` (shallow clone into a `site/pack/dots/start` pack on first
  run — no plugin manager). Buffer-local mappings (`gd`, `gr`, `K`,
  `\rn`, `\ac`, `\fm`, `]d`/`[d`, …) plus Metals commands
  (`\mi` import build, `\mo` organize imports, `\mp` doctor; every command
  in `:h metals-commands`). Worksheets get inlay hints.
- **Vim — fallback, core LSP.** `.vimrc` injects `languageserver.scala`
  into `g:coc_user_config`, pointed at `exepath('metals')` and guarded on
  the binary's existence. Completion, `K`, `gd`/`gr`/`gy`/`gi`, `\rn`,
  `\ac`, `[g`/`]g` and `:CocList diagnostics` all work there; the build
  import prompt arrives as a normal coc dialog. Metals-specific commands
  are not registered as `:CocCommand` names, but they can still be run —
  e.g. `:CocCommand workspace.executeCommand metals.import-build`.
- **Install (both editors share one Metals binary):** coursier lives in
  `~/.local/share/coursier/bin` (PATH block in `.bashrc`), then
  `cs install metals scala-cli`.

Caveat: `g:coc_user_config` takes precedence over `coc-settings.json`; if
you ever move settings to a file, mirror or relocate this block.

## Other `~/.vimrc` settings worth knowing

- **Tabs**: `expandtab`, 2-space tabs (filetypes may override) — nvim uses
  the same 2-space base (its scala/sbt override became redundant and was
  removed).
- **Numbers**: hybrid — absolute current line (highlighted, `cursorline`),
  relative everywhere else, scrolling with the cursor. nvim also signs the
  distance through `statuscolumn`: `-3 -2 -1` above the cursor, `+1 +2 +3`
  below (vim has no `statuscolumn`, so its relative numbers are unsigned).
- **Under sudo/doas** (`$SUDO_USER`/`$DOAS_USER` set): no coc and no plugin
  auto-install. macOS sudo keeps your `$HOME`, so `sudo vim` would otherwise
  write `~/.config/coc` and `~/.npm` as root; prefer `sudoedit`.
- **Search**: incremental + highlighted (`hlsearch`), case-insensitive until
  CamelCase (`ignorecase smartcase`), `<Esc>` clears the highlight.
- **Scroll/UI**: `scrolloff=8`, `cursorline`, `colorcolumn=100`,
  `signcolumn=yes` (a reserved gutter column that never shifts layout),
  splits always open below/right, mouse enabled everywhere.
- **Updatetime**: 250 ms — CursorHold features (the coc reference highlight)
  react quickly in vim, matching nvim's long-standing setting.
- **File handling**: no swap files, no `file~` backups; undo persists across
  restarts (`undofile`) in `~/.vim/undo/` (vim) / the nvim data dir.
- **Backspace**: works over indent, EOL, insert-start like everywhere else.
- **Colors**: true color (`termguicolors`) when `$COLORTERM` says so (or you're
  on kitty/alacritty), 256 colors otherwise; airline follows either way.
- **Clipboard**: `clipboard=unnamedplus` when a clipboard helper is found (so
  yanks go straight to the system clipboard); `\y` re-sends the last yank (see
  keybinding table). Note: the vim binary on this box is compiled
  **-clipboard** — `set clipboard=…` errors there (E519), which is why the
  set-guard exists: it applies only on +clipboard builds, and `\y` is the
  working path on this box. nvim's guard is functional (it has a clipboard
  provider), including the graphical-session fallback vim can't use.
- **Statusline**: vim uses vim-airline with powerline glyphs; nvim uses a
  native, plugin-free statusline that mirrors airline's contract (mode chip,
  branch + hunks, LSP status, filetype, E/W counts, powerline position glyphs)
  driven by `g:dot_powerline_fonts`.

## Files in `~/.vim` and `~`

```
~/.vimrc            main config (the ONLY vim config; edit this one)
~/.vim/.theme       persisted theme choice, one line: default | gruvbox | codedark
                    (generated by the theme switcher, not tracked; read AND
                    written by the nvim twin too, plus tmux/trueline)
~/.vim/undo/        persistent undo directory (generated by the undofile
                    switch, not tracked)
~/.vim/autoload/plug.vim      plugin manager (vendored vim-plug)
~/.vim/plugged/     installed plugins (generated on first launch)
~/.vim/colors/xoria256.vim   the `default` theme's vim colorscheme
~/.vim/.netrwhist   vim's netrw history (auto-generated, regenerates itself)
~/.vim/MYDOTS.md    this file
~/.config/nvim/init.lua       nvim main config (kept in lockstep with ~/.vimrc)
~/.config/nvim/colors/*.vim   vendored gruvbox/codedark/tokyonight-storm for
                              nvim (sync recipe in the init.lua theme block)
~/.local/state/nvim/.theme    nvim-only theme fallback (only when ~/.vim is absent)
```

## Cleaned up on 2026-11-23

- **vim-sensible removed** — its defaults are now explicit in the "Unified
  with nvim" block at the top of `~/.vimrc`. Reason: sensible only defers to
  options it believes were "set from a file in $HOME" (it greps the last-set
  location for a literal `~/`), and stow's symlinked configs record absolute
  repo paths — so sensible silently overrode vimrc's own settings (it reset
  `scrolloff` to 1 and `history` to 1000 after vimrc set 8/10000). All of its
  useful defaults (wildmenu, autoread, laststatus, smarttab, `nrformats-=o`,
  `formatoptions+=j`, session/viminfo tweaks) are now written explicitly.

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
  theme switcher writes it whenever you run `\td` / `\tg` / `\tc`, and you get
  the `default` theme until then. coc.nvim's node requirement (>= 22.15) is why the requirement
  note above exists.