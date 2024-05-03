---
- hosts: all
  vars:
    TYPE: nvim-term-esc
    INSTANCE: main
    ETC_FILES:
      - name: term-esc.lua
        content: |
          vim.api.nvim_set_keymap('t', '<Leader><ESC>', '<C-\\><C-n>',  {noremap = true})"
      - name: 
    BINS:
      - name: install.sh
        content:
          dest=~/.config/$VIM/$PLUGINS
          mkdir -p $dest
          ln -s etc/$NAME.lua ${dest}/$NAME.lua
    VIM: "nvim" # or astrovim-git!
    PLUGINS: lua/plugins
    ENV:
      - NVIM
      - PLUGINS
      - ETC
  tasks:
    include: tasks/compfuzor.includes type=etc
