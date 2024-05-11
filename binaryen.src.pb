---
- hosts: all
  vars:
    TYPE: binaryen
    INSTANCE: git
    REPO: https://github.com/WebAssembly/binaryen
    BINS:
      - name: "build.sh"
        basedir: True
        exec: |
          mkdir build
          cd build
          cmake -G Ninja ..
          ninja
      - name: "install.sh"
        basedir: build
        exec: |
          sudo ninja install
  tasks:
  - include: tasks/compfuzor.includes type=src
