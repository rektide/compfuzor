---
- hosts: all
  vars:
    TYPE: rofi-emoji
    INSTANCE: git
    REPO: https://github.com/Mange/rofi-emoji
    ENV:
      womp: womp
    BINS:
      - name: build.sh
        exec: |
          autoreconf -i
          mkdir $BUILD_DIR
          cd $BUILD_DIR
          ../configure
          make
      - name: install.sh
        exec: |
          cd $BUILD_DIR
          sudo make install
  tasks:
    - import_tasks: tasks/compfuzor.includes
