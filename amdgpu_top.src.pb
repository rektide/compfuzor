---
- hosts: all
  vars:
    TYPE: amdgpu-top
    INSTANCE: git
    REPO: https://github.com/Umio-Yasuno/amdgpu_top
    BINS:
      - name: build.sh
        content: |
          echo hi
  tasks:
    - import_tasks: tasks/compfuzor.includes
