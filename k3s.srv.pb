---
- hosts: all
  vars:
    TYPE: k3s
    INSTANCE: "{{ domain }}"
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
    # unitj
    SYSTEMD_DESCRIPTION: k3s
    SYSTEMD_AFTER: network.target
    # service
    SYSTEMD_EXEC: "/usr/local/bin/k3s {{args|join(' ')}}"
    SYSTEMD_RESTART: on-failure
    # support added in https://github.com/rancher/k3s/pull/100 ?
    SYSTEMD_TYPE: notify
    # install
    SYSTEMD_WANTED_BY: multi-user.target
    SYSTEMD_ALIAS: k3s.service

    domain: base.yoyodyne.net
    cluster_cidr: "10.41.0.0/16"
    service_cidr: "10.42.0.0/16"
    flannel_backend: none
    v: 2
    args:
    - "{{ '-v '+(v|string) if v|default(false) else '' }}"
    - "--tls-san {{ INSTANCE }}"
    - "--cluster-domain {{ INSTANCE }}"
    - "--data-dir {{ VAR }}"
    - "--cluster-cidr {{ cluster_cidr }}"
    - "--service-cidr {{ service_cidr }}"
    - "--cluster-dns 10.32.0.2"
    - "--flannel-backend {{ flannel_backend }}"
    # etc input
    - "--token-file {{ETC}}/token"
    - "--agent-token-file {{ETC}}/agent-token"
    # etc output
    - "--write-kubeconfig {{ETC}}/kubeconfig.admin"
  tasks:
  - include: tasks/compfuzor.includes type=srv
