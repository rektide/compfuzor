---
- hosts: all
  vars:
    REPO: https://github.com/dimtpap/coppwr
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
