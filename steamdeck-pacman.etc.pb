---
- hosts: all
  vars:
    TYPE: steamdeck-packman
    INSTANCE: main
    ETC_FILES:
      - name: packages.txt
        content: |
          {%for package in packages%}{{package}} {%endfor%}
    packages:
      - ghostty
      - zsh
      - tmux
      - htop
      - neovim
      - vim-ansible
      - interception-tools
      - interception-caps2esc
      - uv
      - ripgrep
      - fd
      - sshpass
      - mise
      - pkgconfig
      - irssi
      - plymouth
      - systemd
    BINS:
      - name: install.sh
        content: |
          sudo steamos-readonly disable
          sudo pacman-key --init
          sudo pacman-key --populate archlinux
          sudo pacman-key --populate holo
      - name: install-pkgs.sh
        content: |
          sudo pacman -S $(cat etc/packages.txt)
  tasks:
    - import_tasks: tasks/compfuzor.includes
