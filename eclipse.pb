---
- hosts: all
  gather_facts: False
  vars:
    TYPE: eclipse
    INSTANCE: 4.3
    file: http://ftp.ussg.iu.edu/eclipse/technology/epp/downloads/release/kepler/R/eclipse-standard-kepler-R-linux-gtk-x86_64.tar.gz
    SRCS_NAME: "{{SRCS_DIR}}/{{NAME}}.tgz"
    OPT_DIR: "{{OPTS_DIR}}/{{NAME}}"
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - get_url: url={{file}} dest={{SRCS_NAME}}
  - shell: chdir={{OPTS_DIR}} tar -xvzf {{SRCS_NAME}}
  - file: path={{OPT_DIR}} state=absent
  - shell: chdir={{OPTS_DIR}} mv eclipse {{NAME}}
  - file: src={{OPT_DIR}}/eclipse dest={{BINS_DIR}}/eclipse state=link