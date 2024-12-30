---
- hosts: all
  vars:
    TYPE: wrpc
    INSTANCE: git
    REPO: https://github.com/bytecodealliance/wrpc
    ENVS:
      hi: ho
    BINS:
      - name: build.sh
        exec: |
          cargo build --release
      - name: install.sh
        exec: |
          ln -s $(pwd)/target/release/wrpc-wasmtime $GLOBAL_BINS_DIR/wrpc-wasmtime
          ln -s $(pwd)/target/release/wit-bindgen-wrpc $BINS_DIR/wit-bindgen-wrpc
  tasks:
    - import_tasks: tasks/compfuzor.includes
