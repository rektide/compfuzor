---
- hosts: all
  vars:
    REPO: https://github.com/Cretezy/lazyjj
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes

