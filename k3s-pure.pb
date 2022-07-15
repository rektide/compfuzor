---
- hosts: all
  vars:
    prefix: "k3s-pure-"
    TYPE: "{{prefix}}{{ is_server|ternary('', '-agent') }}"
    INSTANCE: "{{server|replace('.', '-')}}"
    PASSWORD:
      - token
    server: k3s.example
    url: "https://{{domain}}:6443"

    is_server: "{{ 'servers' in group_names }}"
    exec: "{{ is_server|ternary('server', 'agent --server ' + server) }}"
    # unit
    SYSTEMD_UNITS:
      Description: "{{ NAME }}"
      After: network-online.target
      Wants: network-online.target
    # service
    SYSTEMD_EXEC: "/usr/local/bin/k3s {{exec}}"
    # support added in https://github.com/rancher/k3s/pull/100 ?
    SYSTEMD_SERVICES:
      Delegate: yes
      KillMode: process
      LimitNOFILE: 1048576
      LimitNPROC: infinity
      LimitCORE: infinity
      Restart: always
      RestartSec: 30s
      TasksMax: infinity
      TimeoutStartSec: 0
      Type: notify
    # install
    SYSTEMD_INSTALLS:
      Alias: k3s.service
    ENV:
      K3S_TOKEN: "{{token}}"
  tasks:
    - include: tasks/compfuzor.includes type=srv
