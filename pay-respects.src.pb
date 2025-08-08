---
- hosts: all
  vars:
    TYPE: pay-respects
    INSTANCE: git
    REPO: https://codeberg.org/iff/pay-respects
    ENV:
      hi: ho
    ETC_FILES:
      - name: tool-versions
        content: |
          rust 1
    BINS:
      - name: build.sh
        content: |
          [ -f .tool-versions ] || ln -sf etc/tool-versions .tool-versions
          cargo build --release
      - name: install-global.sh
        content: |
          ln -s $(pwd)/target/release/pay-respects $GLOBAL_BINS_DIR
  tasks:
    - import_tasks: tasks/compfuzor.includes

