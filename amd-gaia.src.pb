---
- hosts: all
  vars:
    TYPE: gaia
    INSTANCE: git
    REPO: https://github.com/amd/gaia
    BINS:
      - name: build.sh
        content: |
          uv sync
          uv venv .venv --python 3.12
          source .venv/bin/activate
          uv pip install -e .
  tasks:
    - import_tasks: tasks/compfuzor.includes
