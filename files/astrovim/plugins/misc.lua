return {
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
	{
		"samjwill/nvim-unception",
		lazy = false,
		init = function()
			--vim.g.unception_open_buffer_in_new_tab = true
			vim.g.unception_enable_flavor_text = false
		end,
	},
}
