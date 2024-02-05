---
- hosts: all
  vars:
    TYPE: h264bitstream
    INSTANCE: git
    REPO: https://github.com/aizvorski/h264bitstream
    BINS:
      - name: build.sh
        exec: |
          mkdir -p build
          cmake -S . -B build
          cmake --build build
      - name: install.sh
        exec: |
          cmake --install build
  tasks:
    - include: tasks/compfuzor.includes type=src

