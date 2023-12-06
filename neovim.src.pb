---
- hosts: all
  vars:
    TYPE: neovim
    INSTANCE: git
    REPO: https://github.com/neovim/neovim
    BINS:
      - name: build.sh
        run: True
        basedir: repo
        exec: |
          mkdir -p build
          cd build
          cmake $(env|grep -e '^CMAKE\|^LIB'|sed -e 's/^/-D /') -G Ninja ..
          ninja
          ninja install
      - name: clean.sh
        basedir: repo
        exec: |
          make distclean
          rm -rf build
      - name: nvim
        global: True
        src: False
        delay: postRun
    PKGS:
      - libuv1
      - libuv1-dev
      - lua-luv
      - lua-luv-dev
      - libtermkey1
      - libtermkey-dev
      - libvterm0
      - libvterm-dev
      - luajit2
      - libluajit2-5.1-2
      - libluajit2-5.1-common
      - libluajit2-5.1-dev
      - lua-lpeg
      - lua-lpeg-dev
      - lua-mpack
      - libmpack0
      - libmpack-dev
      - libmsgpackc2
      - libmsgpack-dev
      - tree-sitter-cli
      - libtree-sitter0
      - libtree-sitter-dev
      - libunibilium4
      - libunibilium-dev
    ENV:
      USE_BUNDLED: "OFF"
      CMAKE_INSTALL_PREFIX: "{{DIR}}"
      CMAKE_BUILD_TYPE: "Release"
      LIBLUV_INCLUDE_DIR: /usr/include/lua5.1
      LIBLUV_LIBRARY: /usr/lib/x86_64-linux-gnu/lua/5.1/luv.so
      #CMAKE_BUILD_TYPE: RelWithDebInfo
  tasks:
    - include: tasks/compfuzor.includes type=opt
