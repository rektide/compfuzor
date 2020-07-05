---
- hosts: all
  vars:
    TYPE: gnome-keyring-unlock
    INSTANCE: git
    REPO: https://codeberg.org/umglurf/gnome-keyring-unlock
    BINS:
      - name: gnome-keyring-unlock
        basedir: repo
        exec: ./unlock.py
  tasks:
    - include: tasks/compfuzor.includes type=opt
