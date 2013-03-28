---
# gitolite
- hosts: all
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    TYPE: gitolite
    INSTANCE: main
    ETC_DIRS:
    - .
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  handlers:
  - include: handlers.yml
  tasks:
  - include: tasks/cfvar_includes.tasks
  - apt: state=${APT_INSTALL} pkg=gitolite
  - user: name=${USER} system=true home=${DIR.stdout}
