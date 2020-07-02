---
- hosts: all
  vars:
    TYPE: rusty_v8
    INSTANCE: git
    REPO: https://github.com/denoland/rusty_v8
  tasks:
  - include: tasks/compfuzor.includes type=src
