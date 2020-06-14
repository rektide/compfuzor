---
- hosts: all
  vars:
    TYPE: k3s
    INSTANCE: "{{ DOMAIN|replace('.', '-') }}"
    VAR_DIR: True
    PASSWORD:
    - token
    - agentToken
    PASSWORD_LENGTH: 96
    ETC_FILES:
    - name: token
      content: "{{ token }}"
    - name: agent-token
      content: "{{ agentToken }}"
    # unit
    SYSTEMD_UNITS:
      After: network.target
      Description: "{{ NAME }}"
    # service
    SYSTEMD_EXEC: "/usr/local/bin/k3s server {{args|join('\\\n	')}}"
    # support added in https://github.com/rancher/k3s/pull/100 ?
    SYSTEMD_SERVICES:
      Delegate: yes
      ExecStartPre:
      - "-/sbin/modprobe br_netfilter"
      - "-/sbin/modprobe overlay"
      KillMode: process
      LimitNOFILE: infinity
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
      WantedBy: multi-user.target

    domain: base.yoyodyne.net
    cluster_cidr: "10.39.0.0/16"
    service_cidr: "10.40.0.0/16"
    cluster_dns: "10.40.0.2"
    flannel_backend: none
    v: 2
    ENV:
      cluster_cidr: "{{cluster_cidr}}"
      service_cidr: "{{service_cidr}}"
      cluster_dns: ""
      flannel_backend: "{{flannel_backend}}"
    args:
    - "{{ '-v '+(v|string) if v|default(false) else '' }}"
    - "--tls-san cluster.{{ domain }}"
    - "--cluster-domain cluster.{{ domain }}"
    - "--data-dir {{ VAR }}"
    - "--cluster-cidr {{cluster_cidr}}"
    - "--service-cidr {{service_cidr}}"
    - "--cluster-dns {{cluster_dns}}"
    - "--flannel-backend {{ flannel_backend }}"
    # etc input
    - "--token-file {{ETC}}/token"
    - "--agent-token-file {{ETC}}/agent-token"
    # etc output
    - "--write-kubeconfig {{ETC}}/kubeconfig.admin"
  tasks:
  - include: tasks/compfuzor.includes type=srv
