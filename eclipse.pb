---
- hosts: all
  gather_facts: False
  vars:
    TYPE: eclipse
    INSTANCE: 4.3
    file: http://ftp.ussg.iu.edu/eclipse/technology/epp/downloads/release/kepler/R/eclipse-standard-kepler-R-linux-gtk-x86_64.tar.gz
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - get_url: url={{file}} dest={{SRCS_DIR}}/{{NAME}}.tgz
  - shell: chdir={{OPTS_DIR}} tar -xvzf {{SRCS_DIR}}/{{NAME}}.tgz
  - shell: chdir={{OPTS_DIR}} mv eclipse {{NAME}}
