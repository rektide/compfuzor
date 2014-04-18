---
- hosts: all
  user: rektide
  vars:
    TYPE: rygel
    INSTANCE: main
    DIR_BYPASS: True
    ETC_FILES:
    - rygel.conf
  vars_files:
  - vars/common.vars
  - vars/common.user.vars
  tasks:
  - include: tasks/xdg.vars.tasks
  - include: tasks/compfuzor.includes type="opt"
