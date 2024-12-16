---
- hosts: all
  vars:
    TYPE: streamlink-twitch-gui
    INSTANCE: git
    REPO: https://github.com/streamlink/streamlink-twitch-gui
    BINS:
      - name: build.sh
        basedir: True
        exec: |
          yarn install
          yarn run grunt release
  tasks:
    - import_tasks: tasks/compfuzor.includes
