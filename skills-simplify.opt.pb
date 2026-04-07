---
- hosts: all
  vars:
    BINS:
      - name: skills-simplify.sh
        basedir: False
        global: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
