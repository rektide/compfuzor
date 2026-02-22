---
- hosts: all
  vars:
    REPO: https://github.com/unclecode/crawl4ai
  tasks:
    - import_tasks: tasks/compfuzor.includes
