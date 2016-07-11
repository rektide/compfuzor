---
- hosts: all
  vars:
    NAME: termit
    ETC_FILES:
    - name: rc.lua
      raw: True
    LINKS:
      "{{ETC}}/rc.lua.example.gz": "/usr/share/doc/termit/rc.lua.example.gz"
  tasks:
  - include: tasks/compfuzor.includes type=etc
