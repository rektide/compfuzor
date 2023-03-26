---
- hosts: all
  vars:
    TYPE: gnome-keyring-unlock
    INSTANCE: git
    REPO: https://codeberg.org/umglurf/gnome-keyring-unlock
    BINS:
      - name: gnome-keyring-unlock
        basedir: repo
        global: True
        exec: |
          exec ./unlock.py
      - name: gnome-keyring-unlock-ugly
        exec: |
          # https://github.com/jaraco/keyring#using-keyring-on-headless-linux-systems
          echo enter password then control-d then load the SSH_AUTH_SOCK
          exec gnome-keyring-daemon --unlock
  tasks:
    - include: tasks/compfuzor.includes type=opt
