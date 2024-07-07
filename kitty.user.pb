---
- hosts: all
  vars:
    TYPE: kitty
    INSTANCE: user
    ETC_FILES:
      - name: nerdfonts.include
        content: |
          symbol_map U+e000-U+e00a,U+ea60-U+ebeb,U+e0a0-U+e0c8,U+e0ca,U+e0cc-U+e0d4,U+e200-U+e2a9,U+e300-U+e3e3,U+e5fa-U+e6b1,U+e700-U+e7c5,U+f000-U+f2e0,U+f300-U+f372,U+f400-U+f532,U+f0001-U+f1af0 Symbols Nerd Font Mono
    BINS:
      - name: install-user.sh
        exec: |
          mkdir -p ~/.config/kitty
          ln -sf $(pwd)/etc/nerdfonts.include ~/.config/kitty/
          echo 'globinclude *.conf' | block-in-file --create=true --names=kitty-user ~/.config/kitty/kitty.conf
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: opt
