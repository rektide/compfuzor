---
- hosts: all
  vars:
    REPO: https://github.com/ClassicOldSongs/Apollo
    CMAKE: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
