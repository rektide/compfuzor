---
- hosts: all
  vars:
    version: 0.8.2
    GET_URLS:  https://github.com/quickwit-oss/quickwit/releases/download/v{{version}}/quickwit-v{{version}}-{{ARCH}}-unknown-linux-gnu.tar.gz
    ENV:
      - version
    BINS:
      - name: build.sh
        content: |
          tar -xvzf src/quickwit-v${VERSION}-x86_64-unknown-linux-gnu.tar.gz
          ln -sf quickwit-v${VERSION} quickwit
      - name: install.sh
        content: |
          ln -sfv $(pwd)/quickwit/quickwit $GLOBAL_BINS_DIR/
  tasks:
    - import_tasks: tasks/compfuzor.includes

