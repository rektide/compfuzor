---
- hosts: all
  gather_facts: False
  vars:
    TYPE: rabbitmq
    INSTANCE: main
    PACKAGES:
    - rabbitmq-server
    - erlang-nox
    SD_ENV:
      mnesia: "{{VAR_DIR}}"
      nodename: "{{NAME}}"
    ETC_FILES:
    - rabbitmq.conf
    LOG_DIRS:
    - "."
    VAR_DIRS:
    - "."
    localhost: false
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
