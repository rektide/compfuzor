return {
  plugins = {
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
}
