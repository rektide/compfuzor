---
- hosts: all
  vars:
    NAME: xdg-dirs
    DIR: "~/.config"
    MEDIAS_DIR: "$HOME/media"
    PREFIX_DIR: "$HOME/"
    ENV: "{{XDG_DIRS}}"
    USERMODE: True
  tasks:
  - action: include_defaults source=vars/xdg.vars
  - action: include_defaults source=vars/common.user.vars
  - action: include_defaults source=vars/common.vars
  #- set_fact: MEDIAS_DIR='${HOME}/media'
  - template: src=files/_env dest=~/.config/user-dirs.dirs
