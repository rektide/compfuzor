---
- hosts: all
  vars:
    TYPE: envdefault
    INSTANCE: git
    REPO: https://github.com/rektide/envdefault
    BINS:
      - src: "{{DIR}}/envdefault"
        global: True
        exists: False
  tasks:
    - include: tasks/compfuzor.includes type=src
