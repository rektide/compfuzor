---
- hosts: all
  vars:
    TYPE: xdg-dirs
    NAME: xdg-dirs
    DIR: "~/.config"
    MEDIAS_DIR: "$HOME/media"
    PREFIX_DIR: "$HOME/"
    ENV: "{{XDG_DIRS}}"
    USERMODE: True
  tasks:
  - include: tasks/compfuzor/vars_base.tasks
  - include: tasks/compfuzor/vars_xdg.tasks
  #- set_fact: MEDIAS_DIR='${HOME}/media'
  - template: src=files/_env dest=~/.config/user-dirs.dirs
