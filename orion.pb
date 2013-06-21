---
- hosts: all
  sudo: True
  gather_facts: false
  handlers:
  - include: handlers.yml
  vars:
    TYPE: orion
    INSTANCE: main
    srv:
      host: 0.0.0.0
      port: 4303
      user: "{{USER}}"
    REPO: git://git.eclipse.org/gitroot/orion/org.eclipse.orion.client.git
    #npm_opts: --node-dir=/usr/src/node
  vars_files:
  - vars/common.vars
  - vars/srv.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - shell: echo hello from {{NAME}}
  - include: tasks/srv.user.tasks
  - include: tasks/systemd.service.tasks 
  - include: tasks/npm.prepare.tasks subdir=modules/orionode
  - shell: chdir={{DIR}} chown {{USER}} . -R
  #- include: tasks/systemd.thunk.tasks service={{NAME}}
  #  only_if: ${has_service.changed}
