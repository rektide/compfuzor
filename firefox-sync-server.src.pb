---
- hosts: all
  vars:
    TYPE: firefox-sync-server
    INSTANCE: git
    REPO: https://github.com/mozilla-services/syncserver
    SYSTEMD_EXEC: local/bin/gunicorn --threads 4 --paste {{ETC}}/firefox-sync-server.ini
    BINS:
    - exec: make build
    ETC_FILES:
    - firefox-sync-server.ini
    SECRET: True
  tasks:
  - include: tasks/compfuzor.includes type=src
