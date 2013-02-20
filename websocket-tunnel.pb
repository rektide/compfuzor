---
- hosts: all
  sudo: True
  vars:
    TYPE: websocket-tunnel
    INSTANCE: main
    srv:
      host: localhost
      port: 447
      user: ${USER.stdout}
    repo: https://github.com/rektide/websocket-tunnel.git
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
