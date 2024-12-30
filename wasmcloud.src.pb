---
- hosts: all
  vars:
    TYPE: wasmcloud
    INSTANCE: git
    REPO: https://github.com/wasmCloud/wasmCloud
    ENV:
      hi: ho
    BINS:
      - name: build.sh
        exec: |
          cargo build --release
          cd crates/wash-cli
          cargo build --release
      - name: install.sh
        exec: |
          ln -s $(pwd)/target/release/wash $GLOBAL_BINS_DIR/wash
  tasks:
    - import_tasks: tasks/compfuzor.includes
