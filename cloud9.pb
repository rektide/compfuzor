---
- hosts: all
  sudo: True
  vars:
    TYPE: c9
    INSTANCE: main
    user: cloud9
    srv:
      host: 0.0.0.0
      port: 3232
      user: ${user}
    repo: https://github.com/ajaxorg/cloud9.git
    npm_opts: --node-dir=/usr/src/node
    DIR_DIRS:
    - workspace
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
  - shell: which sm; echo $?
    register: missing_sm
  - shell: npm ${npm_opts} install sm
    only_if: ${missing_sm.rc} > 0
  - git: repo=${repo} dest=${DIR.stdout}/webapp
    register: has_webapp
  - shell: chown ${user} ${DIR.stdout}/webapp
    only_if: ${has_webapp.changed}
  - shell: chdir=${DIR.stdout}/webapp sudo -u ${user} sm install
    only_if: ${has_webapp.changed}
  - shell: chown ${user} ${DIR.stdout}/webapp
    only_if: ${has_webapp.changed}
  - template: owner=root group=root src=files/cloud9/cloud9.service dest=/etc/systemd/system/${NAME.stdout}.service
    register: has_service
  - shell: systemctl enable ${NAME.stdout}.service
    only_if: ${has_service.changed}
  - shell: systemctl restart ${NAME.stdout}.service
    only_if: ${has_service.changed} or ${has_webapp.changed}
