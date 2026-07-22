---
- hosts: all
  vars:
    TYPE: solstone
    INSTANCE: git
    REPO: https://github.com/solpbc/solstone-journal.git
    PYTHON: True
    PKGS:
      - ripgrep
      - ffmpeg
      - pipewire
      - gstreamer1.0-tools
      - gstreamer1.0-pipewire
      - pulseaudio-utils
    BINS:
      - name: build.sh
        content: |
          make install
      - name: setup.sh
        exec: |
          .venv/bin/journal setup
      - name: sol
        global: True
        exec: |
          .venv/bin/sol $*
      - name: journal
        global: True
        exec: |
          .venv/bin/journal $*
  tasks:
    - import_tasks: tasks/compfuzor.includes
