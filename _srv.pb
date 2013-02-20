---
- hosts: all
  sudo: True
  vars:
    TYPE: NAME
    INSTANCE: INSTANCE
    user: USER
    srv:
      host: 0.0.0.0
      port: 4444
      user: ${user}
    repo: REPO
    npm_opts: --node-dir=/usr/src/node
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  gather_facts: false
  handlers:
  - include: handlers.yml
  tasks:
  - include: tasks/cfvar_includes.tasks
  - shell: echo ${DIR.stdout}
  - user: name=${user} system=true home=${DIR.stdout}
  - template: owner=root group=root src=files/${NAME.stdout}/${NAME.stdout}.service dest=/etc/systemd/system/${NAME.stdout}.service
    register: has_service
  - include: tasks/systemctl.thunk.service name=${NAME.stdout}
