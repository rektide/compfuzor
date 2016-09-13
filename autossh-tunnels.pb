---
- hosts: all
  vars:
    TYPE: autossh-tunnel
    INSTANCE: main
    VAR_DIR: True
    ETC_FILES:
    - src: autossh_config
      dest: "{{NAME}}.config"
    SYSTEMD_EXEC: "/usr/bin/autossh -M {{(item|default({})).monitor|default(monitor)|default(10022)|int + hostnum|int}} -F {{ETC}}/{{NAME}}.config -tt %I"
    SYSTEMD_RESTART: on-failure
    SYSTEMD_RESTART_SEC: "2s"
    SYSTEMD_INSTANCES: "{{hosts|map(attribute='host')|list}}"
    PKGS:
    - autossh
    SYSTEMD_THUNK_BYPASS: True
  tasks:
  - name: "make ETC merely a pointer to exiting ~/.ssh directory"
    set_fact:
      ETC: "{{ansible_user_dir}}/.ssh"
    when: USERMODE|default(False) and not ETC_DIR|default(False)
  - include: tasks/compfuzor.includes type=srv

  # look for keys
  - name: "look for a global key file to try to use"
    set_fact: key="{{item}}"
    with_first_found:
    - "private/autossh-tunnel/{{NAME}}.pem"
    - "private/autossh-tunnel/{{INSTANCE}}.pem"
    - "private/{{NAME}}.pem"
    - "private/autossh-tunnel/{{TYPE}}.pem"
    - "private/{{TYPE}}.pem"
    - "files/autossh-tunnel/{{TYPE}}.pem"
    - "files/_empty"
    when: key is not defined
    register: has_key
    #ignore_errors: False
  - name: "autossh-tunnel: fallback to no host key {{key}}"
    set_fact: key="{{False}}"
    when: has_key|failed or has_key == "files/_empty"

  # copy in keys
  - name: "autossh-tunnel: install top level keys {{key}}"
    template: src="{{key}}" dest="{{ETC}}/{{NAME}}" mode=0400
    when: not not key|default(False)
    register: has_key
  - name: "autossh-tunnel: install host keys"
    template: src="{{item.key}}" dest="{{ETC}}/{{NAME}}-{{item.host|replace('.','-')}}.pem" mode=0400 backup=True
    with_items: "{{hosts}}"
    when: item.key|default(False)
    register: has_keys

  # thunk for real
  - include: tasks/systemd.thunk.tasks service="{{NAME}}@{{item}}"
    with_items: "{{SYSTEMD_INSTANCES|default([])}}"
