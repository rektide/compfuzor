---
- hosts: all
  gather_facts: False
  vars:
    TYPE: dbusfs
    INSTANCE: git
    REPO: https://github.com/sidorares/dbusfs
  tasks:
  - include: tasks/compfuzor.includes type=opt
  - include: tasks/npm.installg.tasks
