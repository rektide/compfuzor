---
- hosts: all
  vars_files:
  - vars/apt.vars
  tasks:
    - include: "tasks/dd.pdebuild-cross.tasks"
