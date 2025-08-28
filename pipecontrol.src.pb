---
- hosts: all
  vars:
    TYPE: pipecontrol
    INSTANCE: git
    REPO: https://github.com/portaloffreedom/pipecontrol
    BINS:
      - name: build.sh
        exec: |
          echo hello world
  tasks:
    - import_tasks: tasks/compfuzor.includes
