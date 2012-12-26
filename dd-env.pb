---
- hosts: all
  vars_files:
  - vars/common.vars
  - vars/dd.vars
  tasks:
  - include: "tasks/dd.pdebuild-cross.tasks"
  - include: "tasks/dd.pdebuild.helper.tasks"
