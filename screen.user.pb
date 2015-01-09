---
- hosts: all
  gather_facts: False
  vars:
    NAME: screen
    DIR: "~"
    ETC: "~/.screenrc.d"
    ETC_FILES:
    - "utf8"
    FILES_D:
    - "~/.screenrc"
  tasks:
  - include: tasks/compfuzor.includes
