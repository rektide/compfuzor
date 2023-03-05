-- vim.cmd [[packadd packer.nvim]]

return require('packer').startup(function(use)
  -- Packer can manage itself
  use 'wbthomason/packer.nvim'

  if vim.fn.executable "deno" then
    use { "vim-denops/denops.vim" }
    use { "vim-denops/denops-helloworld.vim" }
  end
end)
