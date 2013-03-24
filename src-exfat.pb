---
- hosts: all
  tags:
  - source
  gather_facts: False
  vars:
    TYPE: exfat
    INSTANCE: svn
    REPO: http://exfat.googlecode.com/svn/trunk/
    NO_GIT: True
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - file: path=${DIR.stdout} state=directory
  - shell: chdir=${SRCS_DIR} svn co ${REPO} ${NAME.stdout}
