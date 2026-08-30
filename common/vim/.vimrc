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
let s:coc_ok = executable('node')

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
Plug 'tpope/vim-sensible'                       " sane defaults
call plug#end()

" First-run bootstrap: if any declared plugin isn't on disk yet, install
" before anything else runs, then re-source this file.
if len(filter(values(g:plugs), '!isdirectory(v:val.dir)'))
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" allow backspacing over everything in insert mode
set backspace=indent,eol,start

set backup		   " keep a backup file
set history=1000  " keep 1000 lines of command line history
set ruler		   " show the cursor position all the time
set showcmd		   " display incomplete commands
set expandtab
set tabstop=2
set shiftwidth=2
set incsearch		" do incremental searching
set number
set relativenumber    " hybrid: absolute number on cursor line, relative elsewhere

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
" Theme switcher: `:DotTheme gruvbox` or `:DotTheme codedark`
" The choice is written to ~/.vim/.theme and survives restarts.
" ----------------------------------------------------------------------
let s:theme_file = expand('~/.vim/.theme')
let s:themes = {
      \ 'gruvbox':  {'colorscheme': 'gruvbox',  'airline': 'gruvbox'},
      \ 'codedark': {'colorscheme': 'codedark', 'airline': 'codedark'},
      \ }

function! s:LoadTheme() abort
  let name = filereadable(s:theme_file) ? trim(readfile(s:theme_file)[0]) : 'codedark'
  return has_key(s:themes, name) ? name : 'codedark'
endfunction

" Second (optional) argument: quiet — apply without a message. Startup uses
" it so opening vim doesn't echo anything; interactive :DotTheme confirms.
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
  call writefile([a:name], s:theme_file)
  if !(a:0 && a:1)
    echomsg 'Theme set to ' . a:name . ' (persisted to ' . s:theme_file . ')'
  endif
endfunction

command! -nargs=1 -complete=customlist,s:ThemeComplete DotTheme call s:SetTheme(<q-args>)
function! s:ThemeComplete(arglead, cmdline, cursorpos) abort
  return filter(sort(keys(s:themes)), 'v:val =~# "^" . a:arglead')
endfunction

" Leader mappings for quick switching: <leader>tg / <leader>tc
nnoremap <silent> <leader>tg :DotTheme gruvbox<CR>
nnoremap <silent> <leader>tc :DotTheme codedark<CR>

call s:SetTheme(s:LoadTheme(), 1)

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
