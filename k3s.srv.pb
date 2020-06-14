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

    DOMAIN: base.yoyodyne.example.net
    K3S_KUBECONFIG_OUTPUT: "{{ETC}}/kubeconfig.admin"
    K3S_TOKEN_FILE: "{{ETC}}/token"
    K3S_AGENT_TOKEN_FILE: "{{ETC}}/agent-token"
    CLUSTER_CIDR: "10.39.0.0/16"
    SERVICE_CIDR: "10.40.0.0/16"
    CLUSTER_DNS: "10.40.0.2"
    FLANNEL_BACKEND: none

    ENV:
      DOMAIN: True
      K3S_TOKEN_FILE: True
      K3S_KUBECONFIG_OUTPUT: True
      CLUSTER_CIDR: "10.39.0.0/16"
      SERVICE_CIDR: "10.40.0.0/16"
      CLUSTER_DNS: "10.40.0.2"
      FLANNEL_BACKEND: none
    v: 2
    args:
    - "{{ '-v '+(v|string) if v|default(false) else '' }}"
    - "--tls-san cluster.{{DOMAIN}}"
    - "--cluster-domain cluster.{{DOMAIN}}"
    - "--data-dir {{VAR}}"
    - "--cluster-cidr {{CLUSTER_CIDR}}"
    - "--service-cidr {{SERVICE_CIDR}}"
    - "--cluster-dns {{CLUSTER_DNS}}"
    - "--flannel-backend {{FLANNEL_BACKEND}}"
    # etc input
    - "--token-file {{K3S_TOKEN_FILE}}"
    - "--agent-token-file {{K3S_AGENT_TOKEN_FILE}}"
    # etc output
    - "--write-kubeconfig {{K3S_KUBECONFIG_OUTPUT}}"
  tasks:
  - include: tasks/compfuzor.includes type=srv
