---
- hosts: all
  vars:
    TYPE: ollama
    INSTANCE: git
    REPO: https://github.com/ollama/ollama
    BINS:
      - name: build.sh
        content: |
          cmake -B build
          cmake --buid build
  tasks:
    - import_tasks: tasks/compfuzor.includes
