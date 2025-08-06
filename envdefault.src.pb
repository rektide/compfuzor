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
    - import_tasks: tasks/compfuzor.includes
