return {
	{
		"rektide/project-settings-nvim",
		dir = "/home/rektide/src/nvim-project-config",
		dev = true,
	},
	{
		"rektide/nvim-auto-listen",
		dependencies = { "rektide/project-settings-nvim" },
	},
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
	"ojroques/nvim-osc52",
	--{
	--	"samjwill/nvim-unception",
	--	lazy = false,
	--	init = function()
	--		--vim.g.unception_open_buffer_in_new_tab = true
	--		vim.g.unception_enable_flavor_text = false
	--	end,
	--},
	{
		"AstroNvim/astrocore",
		---@type AstroCoreOpts
		opts = function(_, opts)
			local utils = require("astrocommunity")
			return require("astrocore").extend_tbl(opts, {
				filetypes = {
					extension = {
						pb = "yaml",
						includes = "yaml",
						tasks = "yaml",
					},
				},
			})
		end,
	},
	{},
}
