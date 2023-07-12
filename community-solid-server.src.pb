---
- hosts: all
  vars:
    TYPE: community-solid-server
    INSTANCE: git
    REPO: https://github.com/CommunitySolidServer/CommunitySolidServer
    OPT_DIR: True
    BINS:
      - name: build.sh
        run: True
        exec: |
          npm ci
  tasks:
    - include: tasks/compfuzor.includes type=src
