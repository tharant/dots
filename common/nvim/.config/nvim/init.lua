-- Minimal neovim config — no plugin manager, sensible defaults only

-- Leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true
vim.opt.hlsearch = true

-- Indentation
vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.smartindent = true

-- Clipboard: only use the system clipboard when something can reach it
-- (pbcopy / wl-copy / xclip / win32yank, or a graphical session to find one in)
if vim.fn.exepath('pbcopy') ~= '' or vim.fn.exepath('wl-copy') ~= '' or vim.fn.exepath('xclip') ~= ''
  or vim.fn.exepath('win32yank.exe') ~= '' or vim.env.WAYLAND_DISPLAY or vim.env.DISPLAY then
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
    map("<leader>dd", vim.diagnostic.open_float, "Diagnostic details")
    -- Metals-specific; full list at :h metals-commands
    map("<leader>mi", function() vim.cmd("MetalsImportBuild") end, "Import build")
    map("<leader>mo", function() vim.cmd("MetalsOrganizeImports") end,
      "Organize imports")
    map("<leader>mp", function() vim.cmd("MetalsRunDoctor") end, "Run doctor")
  end
  metals_config.settings = {
    showImplicitArguments = true,   -- shows inferred types: good while learning
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

-- Scala convention is 2-space indent (scalafmt default); overrides the
-- 4-space defaults set above.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "scala", "sbt" },
  callback = function()
    vim.opt_local.shiftwidth = 2
    vim.opt_local.tabstop = 2
    vim.opt_local.softtabstop = 2
  end,
  desc = "Scala: 2-space indent (scalafmt convention)",
})
