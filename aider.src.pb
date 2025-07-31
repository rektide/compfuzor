---
- hosts: all
  vars:
    TYPE: aider
    INSTANCE: git
    REPO: https://github.com/Aider-AI/aider
    ENV:
      hi: ho
    ETC_FILES:
      - name: tool-versions
        content: |
          python 3.12
    BINS:
      - name: build.sh
        exec: |
          [ -f .tool-versions ] || ln -sf etc/tool-versions .tool-versions
          uv sync
      - name: aider
        global: True
        basedir: False
        exec: |
          exec uv run --project ${DIR} aider $*
      - name: install.sh
        exec: |
          ln -s $(pwd)/bin/aider $GLOBAL_BINS_DIR/aider
  tasks:
    - import_tasks: tasks/compfuzor.includes
