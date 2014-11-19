---
- hosts: all
  gather_facts: False
  vars_files:
  - vars/common.user.vars
  vars:
    NAME: xdg-dirs
    DIR: "~/.config"
    MEDIAS_DIR: "${HOME}/media"
    PREFIX_DIR: "${HOME}/"
    ENV: "{{XDG}}"
  tasks:
  - include_vars: vars/xdg.vars
  - set_fact: MEDIAS_DIR='${HOME}' PREFIX_DIR='${HOME}'
  - debug: msg={{MEDIAS_DIR}} {{XDG}}
  - template: src=files/_env dest=~/.config/user-dirs.dirs
