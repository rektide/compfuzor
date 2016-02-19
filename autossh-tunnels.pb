---
- hosts: all
  sudo: True
  vars:
    TYPE: autossh-tunnel
    NAME: autossh-tunnel
    INSTANCE: main
    ETC_DIR: True
    VAR_DIR: True
    #ETC_FILES:
    #- autossh_config
    SYSTEMD_EXEC: "/usr/bin/autossh -M {{item.monitor|default(monitor)|default(10022)}} -F {{ETC}}}/{{NAME}}.config -tt {{item.host}}"
    SYSTEMD_RESTART: on-failure
    SYSTEMD_RESTART_SEC: 2s
    PKGS:
    - autossh
  vars_files:
  - [ "private/autossh-tunnel/{{INSTANCE}}.vars", "private/autossh-tunnel/autossh-tunnel.vars", "private/autossh-tunnel.vars", "example-private/autossh-tunnel/autossh-tunnel.vars" ]
  tasks:
  - set_fact: key={{item}}
    with_first_found:
    - "private/autossh/{{INSTANCE}}.pub"
    - "files/autossh/{{INSTANCE}}.pub"
    - "private/autossh/autossh.pub"
    - "files/autossh/autossh.pub"
    - "private/autossh.pub"
    register: got_key
    failed_when: False
  - include: tasks/compfuzor.includes
  - file: state=directory owner=${exec_user} group=root mode=0600 path=${dest}
  - file: state=directory owner=${exec_user} group=root mode=0600 path=${dest}/keys
  - template: src=files/autossh-tunnels/autossh_config dest=${dest}/autossh_config
    register: has_config
  - template: src=files/systemd.service dest={{SYSTEMD_UNIT_DIR}}/{{NAME}}-{{item.host}}.service
    with_items: $hosts
    register: has_service
  - copy: src={{item}} dest={{ETC}}/keys/{{item|basename}} mode=0400
    with_fileglob: private/autossh-tunnels/keys/*
  - include: tasks/systemd.thunk.tasks service={{NAME}}-{{item.host}}
    with_items: $hosts
    only_if: ${has_service.changed} or ${has_config.changed}

  - shell: systemctl enable autossh-tunnels-${item.host}.service
    with_items: $hosts
    only_if: ${has_service.changed} or ${has_config.changed}
  - shell: systemctl reload-or-restart autossh-tunnels-${item.host}.service
    with_items: $hosts
    only_if: ${has_service.changed} or ${has_config.changed}
