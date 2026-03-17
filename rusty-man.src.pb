---
- hosts: all
  vars:
    REPO: git.sr.ht/~ireas/rusty-man
    RUST: True
    NVIM:
      lazy:
        - name: rusty-man
          content: |
            return {
              {
                "AstroNvim/astrocore",
                ---@type AstroCoreOpts
                opts = function(_, opts)
                  return require("astrocore").extend_tbl(opts, {
                    autocmds = {
                      rusty_man_keywordprg = {
                        {
                          event = "FileType",
                          pattern = "rust",
                          callback = function()
                            vim.opt_local.keywordprg = "rusty-man"
                          end,
                        },
                      },
                    },
                  })
                end,
              },
            }
          ftplugin:
            rust:
              keywordprg: rusty-man
  tasks:
    - import_tasks: tasks/compfuzor.includes
