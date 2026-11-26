" >>> vimtutor >>> (managed block; removed by setup.sh --uninstall)
" Optional: VIMTUTOR ADVANCED (github.com/tharant/vimtutor). Kept in dots
" with this marker so its setup.sh sees the file as wired and leaves the stow
" symlink alone; the path is $HOME-relative so it works on every machine.
" vimrc.common defaults g:vimtutor_data to ~/.local/share/vimtutor itself.
" dots owns the colorscheme and status line (DotTheme, airline below), so
" vimtutor must not apply its own (its g:vimtutor_ui setting).
let g:vimtutor_ui = 'off'
if filereadable(expand('~/.local/share/vimtutor/config/vimrc.common'))
  source ~/.local/share/vimtutor/config/vimrc.common
endif
" <<< vimtutor <<<
set nocompatible              " be iMproved, required
filetype off                  " re-enabled by plug#end() below

" ----------------------------------------------------------------------
" Plugins — managed by vim-plug (vendored at ~/.vim/autoload/plug.vim).
" Installed into ~/.vim/plugged/ (not tracked in this repo). Missing
" plugins are installed automatically on the first startup; manage them
" manually with :PlugInstall / :PlugUpdate / :PlugClean.
" ----------------------------------------------------------------------
" coc.nvim needs node (>= 22) at runtime; without it the plugin aborts with
" an error prompt on every startup. Load it — and bind its mappings — only
" when node exists (see ~/.vim/MYDOTS.md "Requirements"). node comes from
" fnm via the runtimes CLI (docs/direnv-runtimes.md); vim finds it on PATH.
" Under sudo/doas (e.g. `sudo vim /etc/hosts`) $HOME is still yours on
" macOS, so coc would install its extensions into ~/.config/coc and npm
" would cache into ~/.npm AS ROOT, leaving both unwritable for you later.
" Root sessions get no coc and no plugin auto-install; use `sudoedit` to
" edit system files with your full setup.
let s:sudo = !empty($SUDO_USER) || !empty($DOAS_USER)
let s:coc_ok = executable('node') && !s:sudo

call plug#begin('~/.vim/plugged')
Plug 'morhetz/gruvbox'                          " dark colorscheme (DotTheme gruvbox)
Plug 'tomasiser/vim-code-dark'                    " VS Code Dark+ colorscheme (DotTheme codedark)
if s:coc_ok
  Plug 'neoclide/coc.nvim', {'branch': 'release'} " LSP completion (needs node >= 22)
endif
Plug 'preservim/nerdtree'                       " file sidebar (F2)
Plug 'vim-airline/vim-airline'                  " statusline
Plug 'vim-airline/vim-airline-themes'           " airline themes (DotTheme picks one)
Plug 'tpope/vim-fugitive'                       " :Git, :Gdiffsplit, ...
Plug 'airblade/vim-gitgutter'                   " gutter diff markers
Plug 'derekwyatt/vim-scala'                     " scala syntax/indent
call plug#end()
" (tpope/vim-sensible was removed 2026-11-23: its "don't touch options the
" user set" heuristic looks for a ~/ prefix in the last-set location, which
" stow's symlinked configs never have — so it silently overrode vimrc
" defaults. All of its useful defaults are now explicit in the block below.)

" First-run bootstrap: if any declared plugin isn't on disk yet, install
" before anything else runs, then re-source this file.
if !s:sudo && len(filter(values(g:plugs), '!isdirectory(v:val.dir)'))
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" allow backspacing over everything in insert mode
set backspace=indent,eol,start

" Unified with nvim's init.lua (dots parity): everything below runs AFTER
" plug#end(), so it overrides vim-sensible where both set an option.
set history=10000
set ignorecase smartcase
set scrolloff=8
set expandtab
set tabstop=2
set shiftwidth=2
set autoindent                " nvim auto-indents new lines; match it
set smarttab                  " <Tab> at line start moves by shiftwidth
set nrformats-=octal          " 010 is not eight
set incsearch
set number
set relativenumber    " hybrid: absolute number on cursor line, relative elsewhere
set hidden
set complete-=i               " don't scan includes while ins-completing
set laststatus=2              " airline always gets its line
set wildmenu wildmode=longest:full,full
set sidescroll=1              " nvim's horizontal scroll feel
set display+=lastline,truncate " show the partial last line like nvim
set formatoptions+=j          " comment joins keep the leader
set tags^=./tags;             " project tags search up the tree
set autoread                  " reload files changed outside vim (nvim default)
set tabpagemax=50
set viminfo^=!                " persist uppercase registers across sessions
set sessionoptions-=options viewoptions-=options
set nolangremap

" Clean-tree file handling (nvim parity).
" BEHAVIOR CHANGE: the old `set backup` line is gone — no more file~ litter;
" ~/.vim/undo/ holds the recoverable history instead.
set noswapfile
set nobackup
set undofile
set undodir=~/.vim/undo//
if !isdirectory(expand('~/.vim/undo'))
  call mkdir(expand('~/.vim/undo'), 'p')    " vim does not create undodir itself
endif

" Responsive UI (nvim parity): CursorHold things (the coc reference
" highlight below) fire after 250 ms instead of 4 s.
set updatetime=250
set splitbelow
set splitright
set mouse=a
set signcolumn=yes            " gutter stays reserved; gitgutter/coc never shift layout
set cursorline
set colorcolumn=100

" True color where the terminal supports it (airline follows automatically),
" 256 colors everywhere else.
if exists('+termguicolors') && ($COLORTERM =~# 'truecolor\|24bit' || $TERM =~# 'kitty\|alacritty')
    set termguicolors
else
    set t_Co=256
endif

" ----------------------------------------------------------------------
" System clipboard: use it when a tool to talk to it exists. Without this
" a console vim on a headless box errors on `set clipboard=...`.
" Canonical predicate (MUST match nvim's init.lua guard): one of
"   pbcopy | wl-copy | xclip | win32yank.exe | clip.exe
"   OR a graphical session ($WAYLAND_DISPLAY/$DISPLAY).
" THIS BOX: the binary is compiled -clipboard, so `set clipboard=...`
" errors (E519) and the set-guard below is dead code here — vim keeps its
" internal registers and \y (below) is the working path to the clipboard.
" vim can honor only the helper half of the predicate: no provider
" machinery exists for the env fallback, so an env-only session leaves \y
" unbound by design — no helper means no error, no map (MYDOTS).
" ----------------------------------------------------------------------
function! s:ClipboardShell() abort
  for [cmd, args] in [
        \ ['pbcopy',        ''],
        \ ['wl-copy',       ''],
        \ ['xclip',         ' -selection clipboard'],
        \ ['win32yank.exe', ' -i --crlf'],
        \ ['clip.exe',      ''],
        \ ]
    if executable(cmd)
      return 'call system(''' . cmd . args . ''', @0)'
    endif
  endfor
  return ''
endfunction

if has('clipboard') && exists('+clipboard')
    if executable('pbcopy') || executable('wl-copy') || executable('xclip') || executable('win32yank.exe') || (executable('clip.exe') || has('win32'))
        set clipboard=unnamedplus
    endif
endif

" ----------------------------------------------------------------------
" Theme switcher: `:DotTheme default`, `:DotTheme gruvbox` or
" `:DotTheme codedark`. An explicit choice is written to ~/.vim/.theme and
" survives restarts; with no choice (file missing or unknown) 'default'
" applies: xoria256 here, tokyonight-storm in nvim (one name, an editor-
" native scheme each). Startup never writes the file, so "no choice"
" stays that way and tracks the dots default.
" ----------------------------------------------------------------------
let s:theme_file = expand('~/.vim/.theme')
let s:themes = {
      \ 'default':  {'colorscheme': 'xoria256', 'airline': 'minimalist'},
      \ 'gruvbox':  {'colorscheme': 'gruvbox',  'airline': 'gruvbox'},
      \ 'codedark': {'colorscheme': 'codedark', 'airline': 'codedark'},
      \ }

function! s:LoadTheme() abort
  let name = filereadable(s:theme_file) ? trim(get(readfile(s:theme_file), 0, '')) : 'default'
  return has_key(s:themes, name) ? name : 'default'
endfunction

" Second (optional) argument: quiet — apply without a message or persisting.
" Startup uses it so opening vim neither echoes nor writes ~/.vim/.theme;
" interactive :DotTheme confirms and persists.
function! s:SetTheme(name, ...) abort
  if !has_key(s:themes, a:name)
    echohl WarningMsg
    echomsg 'Unknown theme: ' . a:name . ' (available: ' . join(sort(keys(s:themes)), ', ') . ')'
    echohl None
    return
  endif
  let t = s:themes[a:name]
  if !empty(t.airline)
    let g:airline_theme = t.airline
  endif
  let g:gruvbox_italic = 1
  execute 'colorscheme' t.colorscheme
  if !(a:0 && a:1)
    call writefile([a:name], s:theme_file)
    echomsg 'Theme set to ' . a:name . ' (persisted to ' . s:theme_file . ')'
  endif
endfunction

command! -nargs=1 -complete=customlist,s:ThemeComplete DotTheme call s:SetTheme(<q-args>)
function! s:ThemeComplete(arglead, cmdline, cursorpos) abort
  return filter(sort(keys(s:themes)), 'v:val =~# "^" . a:arglead')
endfunction

" Leader mappings for quick switching: <leader>td / <leader>tg / <leader>tc
nnoremap <silent> <leader>td :DotTheme default<CR>
nnoremap <silent> <leader>tg :DotTheme gruvbox<CR>
nnoremap <silent> <leader>tc :DotTheme codedark<CR>

call s:SetTheme(s:LoadTheme(), 1)

" Search-highlight / window / buffer parity with nvim (nvim binds these in
" init.lua with identical keys; sensible's <C-L> nohl stays alongside).
nnoremap <silent> <Esc> :nohlsearch<CR>
nnoremap <silent> <C-h> <C-w>h
nnoremap <silent> <C-j> <C-w>j
nnoremap <silent> <C-k> <C-w>k
nnoremap <silent> <C-l> <C-w>l
nnoremap <silent> [b :bprevious<CR>
nnoremap <silent> ]b :bnext<CR>

" Allow saving of files as sudo when I forgot to start vim using sudo.
cmap w!! %!sudo tee > /dev/null %

" Don't use Ex mode, use Q for formatting
map Q gq

" Make p in Visual mode replace the selected text with the "" register.
vnoremap p <Esc>:let current_reg = @"<CR>gvs<C-R>=current_reg<CR><Esc>

" Switch syntax highlighting on, when the terminal has colors
" Also switch on highlighting the last used search pattern.
if &t_Co > 2 || has("gui_running")
  syntax on
  set hlsearch
endif

if has("gui_macvim")
	let macvim_hig_shift_movement = 1
endif

"autocmd vimenter * NERDTree
autocmd StdinReadPre * let s:std_in=1
"autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif
map <F2> :NERDTreeToggle<CR>

" coc.nvim configuration (replaces neocomplete)
" Everything coc-related — the plugin above, these mappings, K, the
" CursorHold highlight — is gated on s:coc_ok: the coc#...() functions and
" <Plug>(coc-...) maps only exist once the plugin loads, and referencing
" them from a mapping without coc produces errors on every keypress.
if s:coc_ok

" Extensions are installed automatically on first startup.
let g:coc_global_extensions = ['coc-json', 'coc-tsserver', 'coc-pyright']

" Use tab for trigger completion with characters ahead and navigate.
inoremap <silent><expr> <TAB>
      \ coc#pum#visible() ? coc#pum#next(1) :
      \ CheckBackspace() ? "\<Tab>" :
      \ coc#refresh()
inoremap <expr><S-TAB> coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"

" Make <CR> accept the selected completion item or notify coc.nvim to format.
inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm()
                              \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

function! CheckBackspace() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1] =~ '\s'
endfunction

" Highlight the symbol and its references when holding the cursor.
autocmd CursorHold * silent call CocActionAsync('highlight')

" Symbol renaming.
nmap <leader>rn <Plug>(coc-rename)

" Code action / quickfix / format-selection + diagnostic traversal —
" same keys vimtutor lesson 12 teaches, for every coc-served language.
nmap <silent> <leader>ac <Plug>(coc-codeaction-cursor)
nmap <silent> <leader>qf <Plug>(coc-fix-current)
xmap <silent> <leader>f  <Plug>(coc-format-selected)
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)

" Go to definition / references / implementation.
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" Show documentation in preview window.
nnoremap <silent> K :call ShowDocumentation()<CR>
function! ShowDocumentation()
  if CocAction('hasProvider', 'hover')
    call CocActionAsync('doHover')
  else
    call feedkeys('K', 'in')
  endif
endfunction

" Enable omni completion (coc handles most languages via LSP; these are
" fallbacks for filetypes without a language server).
autocmd FileType css setlocal omnifunc=csscomplete#CompleteCSS
autocmd FileType html,markdown setlocal omnifunc=htmlcomplete#CompleteTags
autocmd FileType xml setlocal omnifunc=xmlcomplete#CompleteTags

" ----------------------------------------------------------------------
" Scala via Metals: coc's generic language-server client drives the
" Coursier-installed Metals binary directly (the old coc-metals extension
" is deprecated and unmaintained — no coc extension covers Metals today).
" Guarded on the binary so machines without coursier are untouched, and
" injected via g:coc_user_config so no coc-settings.json has to ship.
" The full Metals experience (import dialogs, doctor, worksheets) lives
" in Neovim via nvim-metals — see ~/.vim/MYDOTS.md "Scala (Metals)".
if !empty(exepath('metals'))
  let g:coc_user_config = get(g:, 'coc_user_config', {})
  let g:coc_user_config.languageserver = get(g:coc_user_config, 'languageserver', {})
  let g:coc_user_config.languageserver.scala = {
        \ 'command': exepath('metals'),
        \ 'args': [],
        \ 'filetypes': ['scala', 'sbt'],
        \ 'rootPatterns': ['build.sbt', 'build.sc', '.git'],
        \ }
endif

endif " s:coc_ok

" <leader>y sends the last-yanked text to the system clipboard. Only bound
" when a clipboard helper exists (was: forwarding to Clipper on port 8377,
" which is gone).
if !empty(s:ClipboardShell())
  execute 'nnoremap <silent> <leader>y :' . s:ClipboardShell() . '<CR>'
endif

let g:airline_powerline_fonts = 1
" (airline theme is set by the DotTheme switcher at the top of this file —
" it must NOT be overridden here or the statusline won't match the colorscheme)

"function! AirlineInit()
"   let g:airline_section_a = airline#section#create(['mode',' ','branch'])
"   let g:airline_section_b = airline#section#create_left(['ffenc','hunks','%f'])
"   let g:airline_section_c = airline#section#create(['filetype'])
"   let g:airline_section_x = airline#section#create(['%P'])
"   let g:airline_section_y = airline#section#create(['%B'])
"   let g:airline_section_z = airline#section#create_right(['%l','%c'])
"endfunction
"autocmd VimEnter * call AirlineInit()
