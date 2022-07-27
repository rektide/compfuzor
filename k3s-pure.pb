---
- hosts: all
  vars:
    prefix: "k3s-pure"
    TYPE: "{{prefix}}{{ is_server|ternary('', '-agent') }}"
    INSTANCE: "{{server|replace('.', '-')}}"
    PASSWORD:
      - token
    PASSWORD_LENGTH: 96
    server: k3s.example
    url: "https://{{server}}:6443"
    generated_token: "write-me-plz"

    is_server: "{{ 'servers' in group_names }}"
    exec: "{{ is_server|ternary('server --tls-san ' + server, 'agent --server ' + url) }}"
    # unit
    SYSTEMD_UNITS:
      Description: "{{ NAME }}"
      After: network-online.target
      Wants: network-online.target
    # service
    SYSTEMD_EXEC: "/usr/local/bin/k3s {{exec}}"
    # support added in https://github.com/rancher/k3s/pull/100 ?
    SYSTEMD_SERVICE: True
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
      # yeah so this needs to be the generated  /var/lib/rancher/k3s/server/node-token
      K3S_TOKEN: "{{is_server|ternary(token, generated_token)}}"
      K3S_KUBECONFIG_MODE: "0640"
  tasks:
    - include: tasks/compfuzor.includes type=srv
