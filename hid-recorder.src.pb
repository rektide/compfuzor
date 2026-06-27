---
- hosts: all
  vars:
    REPO: https://github.com/hidutils/hid-recorder
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
