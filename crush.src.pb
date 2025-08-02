---
- hosts: all
  vars:
    TYPE: crush
    INSTANCE: git
    REPO: https://github.com/charmbracelet/crush
    BINS:
      - name: build.sh
        content: |
          go install .
          go build .
      - name: install.sh
        content: |
          ln -s $(pwd)/crush $GLOBAL_BIN_DIR/
  tasks:
    - import_tasks: tasks/compfuzor.includes
