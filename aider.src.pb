---
- hosts: all
  vars:
    TYPE: aider
    INSTANCE: git
    REPO: https://github.com/Aider-AI/aider
    ENV:
      hi: ho
    BINS:
      - name: build.sh
        exec: |
          uv sync
      - name: aider
        global: True
        exec:
          uv run --project ${DIR} aider $*
  tasks:
    - import_tasks: tasks/compfuzor.includes
