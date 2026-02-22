---
- hosts: all
  vars:
    TYPE: kq
    INSTANCE: main
    REPO: https://github.com/jihchi/kq
    ENV: True
    BINS:
      - name: build.sh
        content: |
          cargo build --release
      - name: install.sh
        content: |
          ln -sfv target/release/kq $GLOBAL_BINS_DIR/
  tasks:
    - import_tasks: tasks/compfuzor.includes
