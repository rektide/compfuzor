return {
	plugins = {
		{
			"jauntywunderkind/nvim-random-color",
			-- our random is best
			priority = 100,
		},
		{
			"rainglow/vim",
			lazy = false,
		},
		{
			"rafi/awesome-vim-colorschemes",
			lazy = false,
		},
		{
			"flazz/vim-colorschemes",
			lazy = false,
		},
		"https://github.com/ojroques/nvim-osc52",
		"jose-elias-alvarez/typescript.nvim",
		"sigmasd/deno-nvim",
		{
			"williamboman/mason-lspconfig.nvim",
			opts = {
				esnure_installed = { "tsserver", "denols" },
			},
		},
	},
	lsp = {
		setup_handlers = {
			denols = function(opts)
				opts.root_dir = require("lspconfig.util").root_pattern("deno.json", "deno.jsonc")
				return opts
			end,
			tsserver = function(opts)
				opts.root_dir = require("lspconfig.util").root_pattern("package.json")
				return opts
			end,
			eslint = function(opts)
				opts.root_dir = require("lspconfig.util").root_pattern(".eslintrc.json", ".eslintrc.js")
				return opts
			end,
		},
	},
	polish = function()
		vim.filetype.add {
			extension = {
				pb = "yaml",
				includes = "yaml",
				tasks = "yaml",
			}
		}
	end,
}
