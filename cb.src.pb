---
- hosts: all
  vars:
    TYPE: cb
    INSTANCE: git
    REPO: https://github.com/Slackadays/Clipboard
    ENV:
      BUILD_DIR: "{{BUILD_DIR}}"
    BINS:
      - name: build.sh
        exec: |
          mkdir -p $BUILD_DIR
          cd $BUILD_DIR
          cmake -DCMAKE_BUILD_TYPE=Release ..
          cmake --build . -j 8
      - name: install.sh
        exec: |
          cd $BUILD_DIR
          cmake --install .
  tasks:
    - import_tasks: tasks/compfuzor.includes

