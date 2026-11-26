
-- >>> vimtutor >>> (managed block; removed by setup.sh --uninstall)
local vimtutor_ok = pcall(function()
  vim.cmd("let g:vimtutor_data = '/home/jlambert/.local/share/vimtutor'")
  vim.cmd("source /home/jlambert/.local/share/vimtutor/config/vimrc.common")
end)
if not vimtutor_ok then
  vim.notify("vimtutor: setup incomplete -- re-run setup.sh", vim.log.levels.WARN)
end
-- <<< vimtutor <<<
-- dots nvim config — kept in lockstep with ~/.vimrc: same options, the same
-- backslash leader, :DotTheme + theme maps (+ shared ~/.vim/.theme), and a
-- native statusline mirroring vim/airline. No plugin manager; vendored bits:
-- the two colorschemes under colors/ and the nvim-metals pack bootstrap.

-- Leader key: backslash, the same default vim uses ("Leader is the default
-- \", documented in MYDOTS). nvim-metals buffer maps then bind \rn \ac \fm
-- \dd \mi \mo \mp — identical keystrokes to vim's coc maps. maplocalleader
-- stays unset (vim has none either).
vim.g.mapleader = "\\"

-- Line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true
vim.opt.hlsearch = true

-- Indentation: 2-space world, like ~/.vimrc (the per-filetype scala/sbt
-- override this file used to carry is now redundant — global 2 == what it set)
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true

-- Clipboard: only use the system clipboard when something can reach it.
-- Canonical predicate (must match vim's s:ClipboardShell): one of
-- pbcopy | wl-copy | xclip | win32yank.exe | clip.exe, OR a graphical
-- session. (Vim honors only the helper half — its env fallback is
-- comment-only because -clipboard builds have no provider machinery.)
if vim.fn.exepath('pbcopy') ~= '' or vim.fn.exepath('wl-copy') ~= '' or vim.fn.exepath('xclip') ~= ''
  or vim.fn.exepath('win32yank.exe') ~= '' or vim.fn.exepath('clip.exe') ~= ''
  or vim.env.WAYLAND_DISPLAY or vim.env.DISPLAY then
  vim.opt.clipboard = "unnamedplus"
end

-- Visual
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.scrolloff = 8
vim.opt.cursorline = true
vim.opt.colorcolumn = "100"

-- File handling
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = true

-- Misc
vim.opt.updatetime = 250
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.mouse = "a"

-- Keymaps
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Move to below window" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Move to above window" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })
vim.keymap.set("n", "[b", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
vim.keymap.set("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })

-- Parity keymaps (mirror ~/.vimrc's QoL set; same keys both editors)
vim.keymap.set({ 'n', 'x', 'o' }, 'Q', 'gq', { desc = 'Reflow: Q is gq, Ex mode freed' })
vim.keymap.set('x', 'p', '<Esc>:let current_reg = @"<CR>gvs<C-R>=current_reg<CR><Esc>',
  { silent = true, desc = 'Paste over selection, keep the paste register' })
vim.cmd('cmap w!! %!sudo tee > /dev/null %')   -- forgot-sudo rescue, like vim
vim.keymap.set({ 'n', 'v' }, '<F2>', '<cmd>Lexplore<CR>',
  { desc = 'netrw sidebar (NERDTree parity)' })

-- ----------------------------------------------------------------------
-- Statusline — native, no plugins. Mirrors vim/airline's contract:
-- A mode | B git branch + hunks | C file + modified + readonly + LSP status
-- … = … X filetype | Y fenc[ff] | Z percent/position | E/W counts far right.
-- Glyphs are written as UTF-8 byte escapes (LuaJIT on nvim 0.10 cannot
-- parse \u{} literals). Powerline glyphs follow g:dot_powerline_fonts —
-- this config's neutral flag; vim's equivalent is g:airline_powerline_fonts.
-- ----------------------------------------------------------------------
vim.g.dot_powerline_fonts = 1

local stl_group = vim.api.nvim_create_augroup('dots-statusline', { clear = true })

local MODE_LABELS = {
  n = 'NORMAL', no = 'NORMAL·O', i = 'INSERT', ic = 'INSERT',
  v = 'VISUAL', V = 'V-LINE', [string.char(22)] = 'V-BLOCK',
  R = 'REPLACE', c = 'COMMAND', t = 'TERM', r = 'PROMPT',
}

local glyphs = { branch = '\xee\x82\xa0', lock = '\xee\x82\xa2' }

-- Git branch: cached per cwd (one small fork per directory change).
local branch_cache = { cwd = nil, name = '' }
local function git_branch()
  local cwd = vim.uv.cwd()
  if branch_cache.cwd == cwd then return branch_cache.name end
  local out = vim.fn.system({ 'git', 'rev-parse', '--abbrev-ref', 'HEAD' })
  branch_cache.cwd = cwd
  branch_cache.name = vim.v.shell_error == 0 and vim.trim(out) or ''
  return branch_cache.name
end

-- Hunks (unstaged, like vim-gitgutter's summary): count hunks of each type
-- from `git diff -U0` headers (@@ -o,n +p,m @@). Cached per buffer/path.
local hunk_cache = {}   -- [bufnr] = { path, add, mod, del }
local function hunk_count(field)             -- "12,3" → 3; "12" → 1; "0" → 0
  local n = field:match(',(%d+)')
  if n then return tonumber(n) end
  return field == '0' and 0 or 1
end
local function git_hunks()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' then return nil end
  local c = hunk_cache[bufnr]
  if c and c.path == path then return c end
  c = { path = path, add = 0, mod = 0, del = 0 }
  local out = vim.fn.system({ 'git', 'diff', '-U0', '--', path })
  if vim.v.shell_error == 0 and out ~= '' then
    for _, line in ipairs(vim.split(vim.trim(out), '\n')) do
      local old, new = line:match('^@@%s+%-([^%s]+)%s+%+([^%s]+)')
      if old and new then
        local o, n = hunk_count(old), hunk_count(new)
        if o == 0 then c.add = c.add + 1      -- added hunk
        elseif n == 0 then c.del = c.del + 1  -- removed hunk
        else c.mod = c.mod + 1 end            -- modified hunk
      end
    end
  end
  hunk_cache[bufnr] = c
  return c
end

-- Cache invalidation on the events that can change the answers.
vim.api.nvim_create_autocmd({ 'BufWritePost', 'FocusGained', 'DirChanged' }, {
  group = stl_group,
  callback = function(args)
    if args.event == 'DirChanged' then
      branch_cache.cwd = nil
    else
      hunk_cache[args.buf] = nil
      branch_cache.cwd = nil
    end
  end,
  desc = 'Refresh statusline git caches',
})

-- Derive User1-8 highlight groups from the ACTIVE colorscheme (fires on
-- every theme change — DotTheme, manual :colorscheme, anything). Single
-- owner rule, the nvim analog of vim's "airline theme only set by DotTheme".
local function hl_attr(name, want_bg)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if not ok or type(hl) ~= 'table' then return nil end
  if want_bg then return hl.bg or hl.background end
  return hl.fg or hl.foreground
end

vim.api.nvim_create_autocmd('ColorScheme', {
  group = stl_group,
  callback = function()
    local dark = hl_attr('Normal', true) or 0
    local accents = {                        -- mode chip accent per state
      { hl_attr('Statement', false),  1 },   -- NORMAL
      { hl_attr('String', false),     2 },   -- INSERT
      { hl_attr('Identifier', false), 3 },   -- VISUAL/V-LINE/V-BLOCK
      { hl_attr('Constant', false),   4 },   -- REPLACE/COMMAND/TERM/PROMPT
    }
    for _, a in ipairs(accents) do
      if a[1] then
        vim.api.nvim_set_hl(0, 'User' .. a[2], { bg = a[1], fg = dark, bold = true })
      end
    end
    vim.api.nvim_set_hl(0, 'User5',          -- neutral pill: branch/hunks/filetype
      { bg = hl_attr('Folded', true), fg = hl_attr('Folded', false) })
    local red = hl_attr('Error', false)
    if red then
      vim.api.nvim_set_hl(0, 'User6', { bg = red, fg = dark, bold = true })  -- readonly chip
      vim.api.nvim_set_hl(0, 'User7', { fg = red })                          -- E count
    end
    vim.api.nvim_set_hl(0, 'User8',          -- W count
      { fg = hl_attr('WarningMsg', false) or hl_attr('String', false) })
  end,
  desc = 'Derive statusline highlight groups from the active colorscheme',
})

function _G.dots_statusline()   -- set below: %!v:lua.dots_statusline()
  local ok, out = pcall(function()
    local parts = {}

    -- A: mode block
    local m = vim.fn.mode()
    local n = (m == 'n' or m == 'no') and 1
      or (m == 'i' or m == 'ic') and 2
      or (m == 'v' or m == 'V' or m == string.char(22)) and 3 or 4
    table.insert(parts, ('%%%d* %s %%*'):format(n, MODE_LABELS[m] or '---'))

    -- B: branch + hunks (shown even when zero, per the airline contract)
    local branch, hunks = git_branch(), git_hunks()
    if branch ~= '' or hunks then
      local seg = ''
      if branch ~= '' then seg = glyphs.branch .. ' ' .. branch end
      if hunks then
        seg = seg .. (seg == '' and '' or ' ')
          .. ('+%d ~%d -%d'):format(hunks.add, hunks.mod, hunks.del)
      end
      table.insert(parts, '%5* ' .. seg .. ' %*')
    end

    -- C: file, modified, readonly chip, LSP status (metals_status slot,
    -- 91-char cap like coc's; populated when a Metals session is live)
    local meta = vim.g.metals_status
    if meta == nil or meta == '' then meta = ''
    else meta = ' ' .. vim.fn.strcharpart(meta, 0, 91) end
    local ro = vim.bo.readonly and ('%6* ' .. glyphs.lock .. 'RO %* ') or ''
    table.insert(parts, ' %<%f%m ' .. ro .. meta)

    table.insert(parts, '%=')

    -- X: filetype pill
    local ft = vim.bo.filetype
    table.insert(parts, '%5* ' .. (ft ~= '' and ft or '-') .. ' %*')

    -- Y: encoding / fileformat
    table.insert(parts, ' %{&fenc}[%{&ff}] ')

    -- Z: percent + position (airline's glyph layout: line/col marks)
    if vim.g.dot_powerline_fonts == 1 then
      table.insert(parts, ' %p%% \xee\x82\xa1:%2l/%L\xe2\x89\xa1 \xe2\x85\x85:%v ')
    else
      table.insert(parts, ' %p%% L:%2l/%L C:%v ')
    end

    -- far right: E/W counts (airline's error/warning sections, always shown)
    local d = vim.diagnostic.count(0)
    -- NB: %% in Lua format = literal % (the statusline escapes around the counts)
    table.insert(parts, (' %%7*E:%d%%* %%8*W:%d%%* '):format(d.error or 0, d.warn or 0))

    return table.concat(parts)
  end)
  return ok and out or ''   -- statusline errors would otherwise flash forever
end
vim.o.statusline = '%!v:lua.dots_statusline()'

-- ----------------------------------------------------------------------
-- Theme switcher (:DotTheme) — mirrors ~/.vimrc's switcher exactly: same
-- two themes, same unknown-name error, same persistence, quiet startup
-- apply. Colorschemes are vendored copies in colors/ (stow puts
-- ~/.config/nvim/colors first on runtimepath). Refresh after a vim
-- :PlugUpdate:  cp ~/.vim/plugged/gruvbox/colors/gruvbox.vim colors/
--               cp ~/.vim/plugged/vim-code-dark/colors/codedark.vim colors/
-- Persistence: BOTH editors read/write ~/.vim/.theme (tmux-powerline and
-- the trueline prompt read it too — one file keeps terminal+vim+nvim in
-- sync). Only when the vim package is absent (nvim-only machine) does
-- nvim use its own state file instead (stow-safe, not in the repo tree).
-- ----------------------------------------------------------------------
local THEMES = { gruvbox = true, codedark = true }

local function theme_path()
  if vim.fn.isdirectory(vim.fn.expand('~/.vim')) == 1 then
    return vim.fn.expand('~/.vim/.theme')       -- shared with vim / tmux / trueline
  end
  return vim.fn.stdpath('state') .. '/.theme'   -- nvim-only fallback
end

local function load_theme()
  local f = io.open(theme_path(), 'r')
  if not f then return 'codedark' end
  local name = (f:read('*l') or ''):gsub('%s+', '')
  f:close()
  return THEMES[name] and name or 'codedark'    -- missing file AND unknown → codedark
end

local function set_theme(name, quiet)
  if not THEMES[name] then
    local keys = vim.tbl_keys(THEMES); table.sort(keys)
    vim.api.nvim_echo({ { 'Unknown theme: ' .. name .. ' (available: '
      .. table.concat(keys, ', ') .. ')', 'WarningMsg' } }, true, {})
    return
  end
  vim.g.gruvbox_italic = 1                      -- same force as ~/.vimrc
  local ok, err = pcall(vim.cmd.colorscheme, name)
  if not ok then
    vim.api.nvim_echo({ { 'Failed to load colorscheme ' .. name .. ': ' .. err, 'WarningMsg' } }, true, {})
    return                                      -- no persist when the colorscheme fails
  end
  vim.fn.writefile({ name }, theme_path())
  if not quiet then
    vim.api.nvim_echo({ { 'Theme set to ' .. name .. ' (persisted to ' .. theme_path() .. ')' } }, true, {})
  end
end

-- The vimtutor-managed block on this box defines its own :DotTheme before
-- this line; dots owns the name here — replace it and its Space-leader quick
-- maps (pcall'd, so they are plain no-ops on machines without that block).
pcall(vim.cmd, 'delcommand DotTheme')
pcall(vim.keymap.del, 'n', '<space>tg')
pcall(vim.keymap.del, 'n', '<space>tc')
pcall(vim.keymap.del, 'n', '<space>tt')

vim.api.nvim_create_user_command('DotTheme', function(o) set_theme(o.args) end, {
  nargs = 1,
  desc = 'Switch dotfiles theme (gruvbox | codedark); persists like vim',
  complete = function(arglead)                  -- = -complete=customlist in .vimrc
    local keys = vim.tbl_keys(THEMES); table.sort(keys)
    return vim.tbl_filter(function(k) return k:sub(1, #arglead) == arglead end, keys)
  end,
})

vim.keymap.set('n', '<leader>tg', '<cmd>DotTheme gruvbox<CR>', { silent = true, desc = 'Theme: gruvbox' })
vim.keymap.set('n', '<leader>tc', '<cmd>DotTheme codedark<CR>', { silent = true, desc = 'Theme: codedark' })

-- Quiet startup apply. Fires ColorScheme → the statusline groups above derive.
set_theme(load_theme(), true)

-- ----------------------------------------------------------------------
-- Scala via Metals (nvim-metals), the officially supported Metals client.
-- Needs Neovim >= 0.11 and coursier (`cs`)/Metals on PATH (this box:
-- ~/.local/share/coursier/bin via the .bashrc PATH block). The plugin is
-- a single shallow git clone — this config has no plugin manager — and
-- the bootstrap below fetches it on first run. Mappings only exist while
-- a Metals buffer is attached; :h metals-commands lists every command.
-- On machines stuck on nvim 0.10 (e.g. Debian apt) none of this runs.
-- ----------------------------------------------------------------------
if vim.fn.has('nvim-0.11') == 1 and vim.fn.executable('git') == 1
  and (vim.fn.exepath('metals') ~= '' or vim.fn.exepath('cs') ~= '') then
  local nvim_metals_group = vim.api.nvim_create_augroup("nvim-metals", { clear = true })

  local metals_dir = vim.fn.stdpath("data") .. "/site/pack/dots/start/nvim-metals"
  if not vim.uv.fs_stat(metals_dir) then
    vim.fn.system({ "git", "clone", "--depth", "1",
      "https://github.com/scalameta/nvim-metals", metals_dir })
  end
  if vim.uv.fs_stat(metals_dir) then
    vim.cmd("packadd nvim-metals")   -- pure-lua plugin; joins runtimepath
  end

  local metals_config = require("metals").bare_config()
  metals_config.on_attach = function(client, bufnr)
    if client.server_capabilities.completionProvider then
      vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
    end
    vim.bo[bufnr].omnifunc = "vim.lsp.omnifunc"
    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = "Metals: " .. desc })
    end
    -- Standard LSP surface (same keys coc uses in vim; buffer-local here)
    map("K",  vim.lsp.buf.hover, "Hover docs")
    map("gd", vim.lsp.buf.definition, "Go to definition")
    map("gD", vim.lsp.buf.declaration, "Go to declaration")
    map("gr", vim.lsp.buf.references, "Find references")
    map("gy", vim.lsp.buf.type_definition, "Go to type definition")
    map("gi", vim.lsp.buf.implementation, "Go to implementation")
    map("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
    map("<leader>ac", vim.lsp.buf.code_action, "Code actions")
    map("<leader>fm", function() vim.lsp.buf.format({ async = true }) end,
      "Format (scalafmt)")
    map("]d", vim.diagnostic.goto_next, "Next diagnostic")
    map("[d", vim.diagnostic.goto_prev, "Previous diagnostic")
    -- coc-parity aliases (vim's coc uses this spelling; same jumps)
    map("]g", vim.diagnostic.goto_next, "Next diagnostic (coc-parity alias)")
    map("[g", vim.diagnostic.goto_prev, "Previous diagnostic (coc-parity alias)")
    map("<leader>dd", vim.diagnostic.open_float, "Diagnostic details")
    -- Metals-specific; full list at :h metals-commands
    map("<leader>mi", function() vim.cmd("MetalsImportBuild") end, "Import build")
    map("<leader>mo", function() vim.cmd("MetalsOrganizeImports") end,
      "Organize imports")
    map("<leader>mp", function() vim.cmd("MetalsRunDoctor") end, "Run doctor")
  end
  metals_config.settings = {
    showImplicitArguments = true,   -- shows inferred types: good while learning
    -- Manage the Metals binary with coursier (`cs update metals`), not
    -- nvim-metals' own installer: one shared, version-consistent binary for
    -- nvim-metals and vim's coc fallback in ~/.vimrc.
    useGlobalExecutable = true,
  }

  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "scala", "sbt" },
    callback = function()
      require("metals").initialize_or_attach(metals_config)
    end,
    group = nvim_metals_group,
    desc = "Attach Metals to Scala/sbt buffers",
  })

  -- sbt/Metals worksheets (.worksheet.sc): show evaluated results inline
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = "*.worksheet.sc",
    callback = function() vim.lsp.inlay_hint.enable(true) end,
    group = nvim_metals_group,
    desc = "Enable inlay hints for Metals worksheets",
  })
end
