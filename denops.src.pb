---
- hosts: all
  vars:
    TYPE: denops
    INSTANCE: git
    REPO: https://github.com/vim-denops/denops.vim
  tasks:
    - include: tasks/compfuzor.includes type=src
