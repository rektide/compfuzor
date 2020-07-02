---
- hosts: all
  vars:
    TYPE: deno
    INSTANCE: git
    REPO: https://github.com/denoland/deno
  tasks:
  - include: tasks/compfuzor.includes type=src
