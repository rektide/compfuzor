---
- hosts: all
  vars:
    TYPE: emscripten
    INSTANCE: git
    REPO: https://github.com/emscripten-core/emscripten.git
    ENV:
      INSTALL_DIR: /usr/local/bin
    BINS:
      - name: "build.sh"
        basedir: True
        exec: |
          # not really a build, just a prep. but build.sh is typical in compfuzor.
          ./bootstrap
      # have not found a way to install yet, just add to PATH i guess?
      #- name: "install.sh"
      #  basedir: True
      #  exec: |
      #     ln -s $(printf "$(pwd)/%s\n" $(fd -tx --maxdepth=1 -E '*.py' em)) ${INSTALL_DIR}
  tasks:
  - include: tasks/compfuzor.includes type=src
