---
- hosts: all
  gather_facts: False
  vars:
    TYPE: nginx
    INSTANCE: main
    packages:
    - nginx-extras
    - nginx-common
    - nginx-doc
    ETC:
      stdout: ${NGINX.stdout}
    ETC_DIRS:
    - global.d
    - hosts.d
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - apt: pkg=$packages state=${APT_INSTALL}
    with_items: $packages
