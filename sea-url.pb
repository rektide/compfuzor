---
- hosts: all
  gather_facts: false
  vars:
    TYPE: sea-url
    INSTANCE: git
    REPO: https://github.com/rektide/sea-url.git
    BINARIES:
    - seacurli
    - urlize
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - file: src=${DIR.stdout}/${item} dest=/usr/local/bin/${item} state=link
    with_items: $BINARIES
