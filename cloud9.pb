---
- hosts: all
  sudo: True
  vars:
    user: cloud9
    srv:
      host: 0.0.0.0
      port: 3232
      user: ${user}
    repo: https://github.com/ajaxorg/cloud9.git
    SRV_TYPE: c9
    npm_opts: --node-dir=/usr/src/node
  tasks:
  - include: handlers.yml
  - include: tasks/srv.vars.tasks
  - user: name=${user} system=true home=${SRV_DIR.stdout}
  - file: owner=${user} group=root state=directory path=${SRV_DIR.stdout}
  - file: owner=${user} group=root state=directory path=${SRV_DIR.stdout}/workspace
  - shell: which sm; echo $?
    register: has_sm
  - shell: npm ${npm_opts} install sm
    only_if: ${has_sm.rc} > 0
  - git: repo=${repo} dest=${SRV_DIR.stdout}/webapp
    register: has_webapp
  - shell: chown ${user} ${SRV_DIR.stdout}/webapp
    only_if: ${has_webapp.changed}
  - shell: chdir=${SRV_DIR.stdout}/webapp sudo -u ${user} sm install
    only_if: ${has_webapp.changed}
  - shell: chown ${user} ${SRV_DIR.stdout}/webapp
    only_if: ${has_webapp.changed}
  - template: owner=root group=root src=files/cloud9/cloud9.service dest=/etc/systemd/system/cloud9.service
    register: has_service
  - shell: systemctl enable cloud9.service
    only_if: ${has_service.changed}
  - shell: systemctl restart cloud9.service
    only_if: ${has_service.changed} or ${has_webapp.changed}
