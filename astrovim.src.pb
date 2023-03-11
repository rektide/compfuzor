---
- hosts: all
  vars:
    TYPE: astrovim
    INSTANCE: git
    REPO: https://github.com/AstroNvim/AstroNvim
    BINS:
      - name: install.user.sh
        exec:
          echo 'export NVIM_APP="$ASTROVIM_APP"' | blockinfile -n "$ASTROVIM_APP" ~/.zshrc
          ln -s $DIR ~/.config/$ASTROVIM_APP
    ENV:
      ASTROVIM_APP: "{{NAME}}"
  tasks:
    - include: tasks/compfuzor.includes type=opt
