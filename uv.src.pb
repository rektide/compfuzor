---
- hosts: all
  vars:
    TYPE: uv
    INSTANCE: git
    REPO: https://github.com/astral-sh/uv
    ENV:
      hello: world
    BINS:
      - name: build.sh
        exec: |
          cargo build --release
      - name: install.sh
        exec: |
          ln -s $(pwd)/target/release/uv $GLOBAL_BINS_DIR/
  tasks:
    - import_tasks: tasks/compfuzor.includes
