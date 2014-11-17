---
- hosts: all
  gather_facts: False
  vars:
    TYPE: rtorrent
    INSTANCE: main
    ETC_FILES:
    - rtorrent.rc
    VAR_DIR: True
    PKGS:
    - rtorrent
    LINKS:
      "~/.rtorrent.rc": "{{ETC}}/rtorrent.rc"
    USERMODE: True
  tasks:
  - include: tasks/compfuzor.includes
