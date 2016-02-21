---
- hosts: all
  sudo: True
  vars:
    TYPE: autossh-tunnel
    INSTANCE: main
    NAME: "{{TYPE}}-{{INSTANCE}}" # used by vars file, run manually vs leaving compfuzor to calculate
    ETC_DIR: True
    VAR_DIR: True
    ETC_FILES:
    - src: autossh_config
      dest: "{{NAME}}.config"
    SYSTEMD_EXEC: "/usr/bin/autossh -M {{item.monitor|default(monitor)|default(10022)|int + hostnum}} -F {{ETC}}}/{{NAME}}.config -tt {{item.host}}"
    SYSTEMD_RESTART: on-failure
    SYSTEMD_RESTART_SEC: 2s
    SYSTEMD_BYPASS: True
    PKGS:
    - autossh
  vars_files:
  - [ "private/autossh-tunnel/{{NAME}}.vars", "private/autossh-tunnel/{{INSTANCE}}.vars", "private/autossh-tunnel/{{TYPE}}.vars", "private/autossh-tunnel/autossh-tunnel.vars", "private/{{NAME}}.vars", "private/{{TYPE}}.vars", "private/autossh-tunnel.vars", "example-private/autossh-tunnel/autossh-tunnel.vars" ]
  tasks:
  - name: look for a global key file to try to use
    set_fact: key={{item}}
    with_first_found:
    - "private/autossh-tunnel/{{NAME}}.pem"
    - "private/autossh-tunnel/{{INSTANCE}}.pem"
    - "private/autossh-tunnel/{{TYPE}}.pem"
    - "private/autossh-tunnel/autossh-tunnel.pem"
    - "private/autossh-tunnel.pem"
    - "files/autossh-tunnel/{{NAME}}.pem"
    - "files/autossh-tunnel/{{INSTANCE}}.pem"
    - "files/autossh-tunnel/{{TYPE}}.pem"
    - "files/autossh-tunnel/autossh-tunnel.pem"
    when: not key|default(True)
    register: has_key
    ignore_errors: False
  - name: "autossh-tunnel: fallback to no host key"
    set_fact: key=False
    when: has_key|failed

  - name: "check for existing ssh"
    stat: path=~/.ssh
    register: has_ssh
  - name: "autossh-tunnel: make ETC merely a pointer to exiting ~/.ssh directory"
    file: src=~/.ssh/ dest={{ETC}} state=link
    when: has_ssh.stat.exists
   
  - include: tasks/compfuzor.includes

  - name: "autossh-tunnel: install top level keys"
    template: src="{{key|replace('.pem', '')}}.pem" dest={{ETC}}/{{NAME}}.pem mode=0400
    when: key|default(False)
    register: has_key
  - name: "autossh-tunnel: install host keys"
    template: src="private/autossh-tunnel/{{item.key|replace('.pem', ''}}.pem" dest={{ETC}}/{{NAME}}-{{item.host}}.pem mode=0400
    with_items: hosts
    when: item.key|default(False)
    register: has_keys

  - name: "autossh-tunnel: install services"
    include: tasks/systemd.unit.includes unit_type=service service_name={{NAME}}-{{item.host}}
    with_items: hosts
  - name: "autossh-tunnel: thunk servics"
    include: tasks/systemd.thunk.tasks service={{NAME}}-{{item.host}}
    with_items: hosts
    when: not SYSTEMD_THUNK_BYPASS|default(False) 
