---
- hosts: all
  sudo: true
  tasks:
    - include: "tasks/dd.vars.tasks"
    - include: "tasks/dd.tasks"
    - include: "tasks/dd.multistrap.tasks"
    - include: "tasks/dd.pdebuild-cross.tasks"
