---
- hosts: all
  vars:
    TYPE: cliphist
    INSTANCE: git
    REPO: https://github.com/sentriz/cliphist
    BINS:
      - name: build.sh
        exec: |
          go build .
  tasks:
    - import_tasks: tasks/compfuzor.includes
