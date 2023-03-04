---
- hosts: all
  vars:
    TYPE: packer
    INSTANCE: git
    REPO: https://github.com/wbthomason/packer.nvim
    ETC_FILES:
      - name: init.lua
        src: ./files/neovim/init.lua
    BINS:
      - name: install.sh
        exec: |
          mkdir -p {{path.packer|dirname}}
          ln -sf {{DIR}}/repo {{path.packer}}
          [ -f "{{path.config}}" ] || cp {{DIR}}/etc/init.lua {{path.config}}
        run: True
    path:
      packer: ~/.local/share/nvim/site/pack/packer/start/packer.nvim
      config: ~/.config/nvim/init.lua
  tasks:
    - include: tasks/compfuzor.includes type=src
