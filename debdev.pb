---
- hosts: all
  sudo: true
  tasks:
    - include: "tasks/debdev.tasks"
