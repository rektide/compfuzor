---
- hosts: all
  vars:
    TYPE: astrovim
    INSTANCE: git
    REPO: https://github.com/AstroNvim/template
    BINS:
      - name: install.user.sh
        exec: |
          cat $DIR/etc/zshrc | envsubst | block-in-file -n "$ASTROVIM_APPNAME" ${ZSHRC/#\~/$HOME}
          ln -sf $DIR/repo ~/.config/$ASTROVIM_APPNAME
      - name: install-unception-git.sh
        exec: git config --global --add core.editor "nvim --cmd 'let g:unception_block_while_host_edits=1'"
    ETC_DIRS:
      - plugins
    ETC_FILES:
      - name: init.lua
      - name: zshrc
        content: export NVIM_APPNAME="$ASTROVIM_APPNAME"
      - name: community.lua
      - name: plugins/dap.lua
      - name: plugins/user.lua
    LINKS:
      - src: "{{ETC}}/init.lua"
        dest: "{{REPO_DIR}}/lua/user/init.lua"
    ENV:
      ASTROVIM_APPNAME: "{{NAME}}"
      ZSHRC: "~/.zshrc"
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: opt
