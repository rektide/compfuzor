---
- hosts: all
  vars:
    TYPE: beads
    INSTANCE: git
    REPO: https://github.com/steveyegge/beads.git
    TOOL_VERSIONS:
      go: True
    BINS:
      - name: build.sh
        content: |
          go build -o bd ./cmd/bd
      - name: install.sh
        content: |
          ln -sv "$(pwd)/bd" $GLOBAL_BINS_DIR/bd
    ENV: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
