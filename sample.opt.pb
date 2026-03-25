---
- hosts: all
  vars:
    BINS:
      - name: sample.sh
  tasks:
    - import_tasks: tasks/compfuzor.includes

