---
- hosts: all
  vars:
    TYPE: shoutcast-search
    INSTANCE: git
    REPO: https://github.com/halhen/shoutcast-search
  tasks:
  - include: tasks/compfuzor.includes type=src
