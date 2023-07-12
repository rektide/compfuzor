---
- hosts: all
  vars:
    TYPE: community-solid-server
    INSTANCE: git
    REPO: https://github.com/CommunitySolidServer/CommunitySolidServer
    OPT_DIR: True
  tasks:
    - include: tasks/compfuzor.includes type=src
