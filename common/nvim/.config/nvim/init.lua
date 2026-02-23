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

-- Clipboard
vim.opt.clipboard = "unnamedplus"

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
