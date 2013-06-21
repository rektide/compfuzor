---
- hosts: all
  vars:
    TYPE: reprepro
    INSTANCE: main
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  - private/reprepro.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - shell: chdir={{DIR}} reprepro -Vb . export
  - shell: chdir={{DIR}} reprepro -Vb . createsymlinks
  
