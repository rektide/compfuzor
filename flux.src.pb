---
- hosts: all
  vars:
    REPO: https://github.com/fluxcd/flux2
    ENV: True
    BINS:
      - name: build.sh
        basedir: repo
        content: |
          make build
      - name: install.sh
        content: |
          ln -sfv $(pwd)/repo/bin/flux $GLOBAL_BINS_DIR/
  tasks:
    - import_tasks: tasks/compfuzor.includes
