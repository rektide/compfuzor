---
- hosts: all
  vars:
    NAME: termit
    ETC_DIR: "{{ '/etc/xdg/termit' if not USERMODE|default(False) else '~/.config/termit' }}"
    ETC_FILES:
    - name: rc.lua
      raw: True
    LINKS:
      "{{ETC}}/rc.lua.example.gz": "/usr/share/doc/termit/rc.lua.example.gz"
      "/etc/alternatives/x-terminal-emulator": "/usr/bin/termit"
  tasks:
  - include: tasks/compfuzor.includes type=etc
