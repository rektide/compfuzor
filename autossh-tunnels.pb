---
- hosts: all
  sudo: True
  vars:
    TYPE: autossh-tunnel
    INSTANCE: main
    VAR_DIR: True
    ETC_FILES:
    - src: autossh_config
      dest: "{{NAME}}.config"
    SYSTEMD_SERVICE: True
    SYSTEMD_EXEC: "/usr/bin/autossh -M {{item.monitor|default(monitor)|default(10022)|int + hostnum|int}} -F {{ETC}}/{{NAME}}.config -tt {{item.host}}"
    SYSTEMD_RESTART: on-failure
    SYSTEMD_RESTART_SEC: "2s"
    PKGS:
    - autossh
  vars_files:
  - vars/common.vars
  - [ "private/autossh-tunnel/{{NAME}}.vars",
      "private/autossh-tunnel/{{INSTANCE}}.vars",
      "private/{{NAME}}.vars",
      "private/autossh-tunnel/{{TYPE}}.vars",
      "private/{{TYPE}}.vars",
      "example-private/{{TYPE}}/{{TYPE}}.vars" ]
  tasks:
  - include: tasks/compfuzor/vars_base.tasks
  - debug: msg=''

  - name: "look for a global key file to try to use"
    set_fact: key="{{item}}"
    with_first_found:
    - "private/autossh-tunnel/{{NAME}}.pem"
    - "private/autossh-tunnel/{{INSTANCE}}.pem"
    - "private/{{NAME}}.pem"
    - "private/autossh-tunnel/{{TYPE}}.pem"
    - "private/{{TYPE}}.pem"
    - "files/autossh-tunnel/{{TYPE}}.pem"
    when: key is not defined
    register: has_key
    #ignore_errors: False
  - name: "autossh-tunnel: fallback to no host key {{key}}"
    set_fact: key="{{False}}"
    when: has_key|failed

  - name: "autossh-tunnel: check for existing ssh"
    stat: path=~/.ssh
    register: has_ssh
  - include: tasks/compfuzor/vars_hierarchy.tasks include=etc
  - name: "autossh-tunnel: make ETC merely a pointer to exiting ~/.ssh directory"
    file: src="~/.ssh" dest="{{ETC}}" state=link
    when: has_ssh.stat.exists

  - name: "autossh-tunnel: storing present state"
    set_fact: "systemd_bypass={{SYSTEMD_BYPASS|default(False)|bool}}"
  - name: "autossh-tunnel: disabling systemd thunk for hosts"
    set_fact: "SYSTEMD_BYPASS=True"
  - include: tasks/compfuzor.includes
  - name: "autossh-tunnel: resuming previous bypass state"
    set_fact: "SYSTEMD_BYPASS={{systemd_bypass|bool}}"

  - name: "autossh-tunnel: install top level keys {{key}}"
    template: src="{{key|replace('.pem', '')}}.pem" dest={{ETC}}/{{NAME}}.pem mode=0400
    when: not not key|default(False)
    register: has_key

  - name: "autossh-tunnel: install host keys"
    template: src="private/autossh-tunnel/{{item.key|replace('.pem', ''}}.pem" dest="{{ETC}}/{{NAME}}-{{item.host|replace('.','-')}}.pem" mode=0400
    with_items: hosts
    when: item.key|default(False)|bool
    register: has_keys

  - debug: msg="{{NAME}}"
  - name: "autossh-tunnel: install services"
    include: tasks/systemd.unit.includes unit_type=service unit_name="{{TYPE}}-{{INSTANCE}}-{{item.host|replace('.','-')}}"
    with_items: hosts
  - name: "autossh-tunnel: thunk servics"
    include: tasks/systemd.thunk.tasks service="{{TYPE}}-{{INSTANCE}}-{{item.host|replace('.','-')}}"
    with_items: hosts
    when: not SYSTEMD_THUNK_BYPASS|default(False)
