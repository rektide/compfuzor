---
- hosts: all
  vars:
    TYPE: jellyfin
    INSTANCE: main
    APT_REPO: https://repo.jellyfin.org/debian
  tasks:
    - include: tasks/compfuzor.includes type=etc
