---
- hosts: all
  vars:
    TYPE: astrovim
    INSTANCE: git
    REPO: https://github.com/AstroNvim/AstroNvim
    BINS:
      - name: install.user.sh
        exec: |
          echo 'export NVIM_APPNAME="$ASTROVIM_APPNAME"' | blockinfile -n "$ASTROVIM_APPNAME" ~/.zshrc
          ln -s $REPO_DIR ~/.config/$ASTROVIM_APPNAME
    ENV:
      ASTROVIM_APPNAME: "{{NAME}}"
  tasks:
    - include: tasks/compfuzor.includes type=opt
