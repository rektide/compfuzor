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
    dest: /srv/cloud9
    npm_opts: --node-dir=/usr/src/node
  tasks:
  - user: name=${user} system=true home=/srv/cloud9
  - file: owner=${user} group=root state=directory path=${dest}
  - file: owner=${user} group=root state=directory path=${dest}/workspace
  - shell: which sm; echo $?
    register: has_sm
  - shell: npm ${npm_opts} install sm
    only_if: ${has_sm.rc} > 0
  - git: repo=${repo} dest=${dest}/webapp
    register: has_webapp
  - shell: chown ${user} ${dest}/webapp
    only_if: ${has_webapp.changed}
  - shell: chdir=${dest}/webapp sudo -u ${user} sm install
    only_if: ${has_webapp.changed}
  - shell: chown ${user} ${dest}/webapp
    only_if: ${has_webapp.changed}
  - template: owner=root group=root src=files/cloud9/cloud9.service dest=/etc/systemd/system/cloud9.service
    register: has_service
  - shell: systemctl enable cloud9.service
    only_if: ${has_service.changed}
  - shell: systemctl restart cloud9.service
    only_if: ${has_service.changed} or ${has_webapp.changed}
