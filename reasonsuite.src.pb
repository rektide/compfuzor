---
- hosts: all
  vars:
    REPO: https://github.com/henryhawke/ReasonSuite
    NODE: True
  tasks:
    import_tasks: tasks/compfuzor.includes
