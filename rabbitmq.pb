---
- hosts: all
- gather_facts: False
- vars:
    TYPE: rabbitmq
    INSTANCE: main
    PACKAGES:
    - rabbitmq-server
    - erlang-nox
    ETC_FILES:
    - rabbitmq.conf
    LOG_DIRS:
    - .
    localhost: false
- vars_files:
  - vars/common.vars
  - vars/srv.vars
- tasks:
  - include: tasks/cfvars_install.tasks
