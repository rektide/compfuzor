---
- hosts: all
  vars:
    TYPE: avfs
    INSTANCE: main
    DIR: True
    BINS:
    - name: mountavfs
      exec: "mountavfs ~/.local/mnt/avfs"
  tasks:
  - include: tasks/compfuzor.includes type=srv
