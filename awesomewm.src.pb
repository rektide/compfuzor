---
- hosts: all
  vars:
    TYPE: awesomewm
    INSTANCE: git
    REPO: https://github.com/awesomeWM/awesome
    BINS:
    - name: build.sh
      run: True
      exec: "CMAKE_ARGS='-DLUA_INCLUDE_DIR=/usr/include/luajit-2.0 -DLUA_LIBRARY=/usr/lib/x86_64-linux-gnu/libluajit-5.1.so -DSYSCONFIG_DIR=/etc -DCMAKE_INSTALL_PREFIX=/usr' make package"
    PKGS:
    - libxcb-cursor-dev
    - libxcb-util0-dev
    - libxcb-keysyms1-dev
    - libxcb-icccm4-dev
    - libxcb-xtest0-dev
    - libxcb-xinerama0-dev
    - libxcb-xrm-dev
    - libxkbcommon-dev
    - libxkbcommon-x11-dev
    - libstartup-notification0-dev
    - libcairo2-dev
    - libpango1.0-dev
    - libglib2.0-dev
    - libgdk-pixbuf2.0-dev
    - libx11-dev
    - imagemagick
    - libxdg-basedir-dev
    - libdbus-1-dev
    - asciidoc
    - xmlto
    - gzip
    - lua-ldoc
    - lua-busted
    - lua-check
    - liblua5.2-dev
    - lua-lgi-dev # seems to only support liblua5.2-dev
  tasks:
  - include: tasks/compfuzor.includes type=src
