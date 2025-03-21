---
- hosts: all
  gather_facts: False
  vars:
    NAME: vim
    DIR: ~/.vim
    DIRS:
    - colors
    - plugins
    FILES:
    - plugins/syntax
    - plugins/filetype-compfuzor
    - plugins/font-gvim
    - plugins/debian-recommended
    REPOS:
     #"{{DIR}}/colorpack": "https://github.com/endel/vim-github-colorscheme" #!
     colorpack: "https://github.com/vim-scripts/Colour-Sampler-Pack"
    LINKS:
      "{{ETC}}": "{{DIR}}"
    USERMODE: True
    DIR_BYPASS: True
    PKGS:
    - fonts-ricty-diminished

  tasks:
  - include: tasks/compfuzor.includes
  - shell: ln -sf {{DIR}}/colorpack/colors/*vim {{DIR}}/colors/
  - get_url: url=http://www.vim.org/scripts/download_script.php?src_id=2335 dest={{DIR}}/colors/
