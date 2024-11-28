---
- hosts: all
  vars:
    TYPE: rofication
    INSTANCE: git
    REPO: https://github.com/regolith-linux/regolith-rofication
    BINS:
      - name: build.sh
        exec: |
          echo TODO
  tasks:
    - include: tasks/compfuzor.includes
