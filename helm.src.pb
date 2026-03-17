---
- hosts: all
  vars:
    REPO: https://github.com/helm/helm
    TOOL_VERSIONS:
      go: True
    ENV: True
    BINS:
      - name: build.sh
        basedir: repo
        content: |
          make build
      - name: install.sh
        content: |
          ln -sfv $(pwd)/repo/bin/helm $GLOBAL_BINS_DIR/
  tasks:
    - import_tasks: tasks/compfuzor.includes
