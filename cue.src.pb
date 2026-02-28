---
- hosts: all
  vars:
    REPO: https://github.com/cue-lang/cue
    GO: True
    GO_TARGET: ./cmd/cue
    GO_BIN: cue-cli
    BINS:
      - name: build.sh
        basedir: repo
      - name: install.sh
        generatedAt: false
        content: |
          ln -sfv $(pwd)/repo/cue-cli ${GLOBAL_BINS_DIR}/cue
  tasks:
    - import_tasks: tasks/compfuzor.includes
