---
- hosts: all
  vars:
    TYPE: gmrender-resurrect
    INSTANCE: git
    REPO: https://github.com/hzeller/gmrender-resurrect
    ENV:
      womp: womp
    BINS:
      - name: build.sh
        exec: |
          ./autogen.sh
          ./configure --with-gstreamer
          make
      - name: install.sh
        exec: |
          sudo make install
  tasks:
    - import_tasks: tasks/compfuzor.includes
