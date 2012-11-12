---
- hosts: all
  sudo: true
  tasks:
    - include: "tasks/debdev.vars.tasks"
    - include: "tasks/debdev.tasks"
    - include: "tasks/debdev.pdebuild-cross.tasks"
