---
- hosts: all
  vars:
    REPO: https://github.com/duckdb/duckdb
  tasks:
    - import_tasks: tasks/compfuzor.includes
