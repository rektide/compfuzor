---
- hosts: all
  vars:
    TYPE: bottom
    INSTANCE: git
    REPO: https://github.com/ClementTsang/bottom
    BINS:
      - name: build.sh
        basedir: True
        exec: |
          cargo build --release
      - name: install.sh
        basedir: True
        exec: |
          ln -s $(pwd)/target/release/bottom $GLOBAL_BINS_DIR/
    ENV:
      GLOBAL_BINS_DIR: "{{GLOBAL_BINS_DIR}}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: src
