---
- hosts: all
  vars:
    TYPE: clipse
    INSTANCE: git
    REPO: https://github.com/savedra1/clipse
    BINS:
      - name: build.sh
        exec: |
          go mod tidy
          go build -o clipse
  tasks:
    - import_tasks: tasks/compfuzor.includes
