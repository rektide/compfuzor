---
- hosts: all
  sudo: True
  vars:
    TYPE: NAME
    INSTANCE: INSTANCE
    srv:
      host: 0.0.0.0
      port: 4444
      user: ${USER.stdout}
    repo: REPO
    npm_opts: --node-dir=/usr/src/node
    LOG_DIRS:
    - .
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  gather_facts: false
  handlers:
  - include: handlers.yml
  tasks:
  - include: tasks/cfvar_includes.tasks
  - include: tasks/npm.prepare.tasks
  - include: tasks/systemctl.thunk.service name=${NAME.stdout}
    only_if: ${has_service.changed}

