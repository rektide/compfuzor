---
- hosts: all
  vars:
    TYPE: astrovim
    INSTANCE: git
    REPO: https://github.com/AstroNvim/AstroNvim
    BINS:
      - name: install.user.sh
        exec: |
          cat $DIR/etc/zshrc | envsubst | block-in-file -n "$ASTROVIM_APPNAME" ${ZSHRC/#\~/$HOME}
          ln -sf $DIR/repo ~/.config/$ASTROVIM_APPNAME
    ETC_FILES:
      - name: init.lua
      - name: zshrc
        content: export NVIM_APPNAME="$ASTROVIM_APPNAME"
    LINKS:
      - src: "{{ETC}}/init.lua"
        dest: "{{REPO_DIR}}/lua/user/init.lua"
    ENV:
      ASTROVIM_APPNAME: "{{NAME}}"
      ZSHRC: "~/.zshrc"
  tasks:
    - include: tasks/compfuzor.includes type=opt
