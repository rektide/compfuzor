---
- hosts: agents
  vars:
    TYPE: k3s-agent
    INSTANCE: "{{ DOMAIN|replace('.', '-') }}"
    VAR_DIRS:
    - data
    - local-provisioner
    PASSWORD_LENGTH: 96
    PASSWORD:
    - agentToken
    ETC_FILES:
    - name: agent-token
      var: agentToken


    # unit
    SYSTEMD_UNITS:
      Description: "{{ NAME }}"
      After: network-online.target
      Wants: network-online.target
    # service
    SYSTEMD_EXEC: "/usr/local/bin/k3s agent {{args|join('\\\n	')}}"
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
      Alias: k3s-agent.service

    DOMAIN: base.yoyodyne.example.net
    CLUSTER_DOMAIN: "cluster.{{DOMAIN}}"
    DATA: "{{VAR}}/data"
    K3S_TOKEN_FILE: "{{ETC}}/token"
    K3S_KUBECONFIG_OUTPUT: "{{ETC}}/kubeconfig.admin"
    K3S_KUBECONFIG_MODE: "0640"
    K3S_AGENT_TOKEN_FILE: "{{ETC}}/agent-token"
    CLUSTER_CIDR: "10.39.0.0/16"
    SERVICE_CIDR: "10.40.0.0/16"
    CLUSTER_DNS: "10.40.0.2"
    FLANNEL_BACKEND: none
    LOCAL_PROVISIONER_PATH: "{{VAR}}/local-provisioner"
    CONTAINER_RUNTIME_ENDPOINT: ""
    PRIVATE_REGISTRY: ""
    K3S_URL: ""

    ENV:
      DOMAIN: "{{DOMAIN}}"
      CLUSTER_DOMAIN: "{{CLUSTER_DOMAIN}}"
      DATA: "{{DATA}}"
      K3S_TOKEN_FILE: "{{K3S_TOKEN_FILE}}"
      K3S_KUBECONFIG_OUTPUT: "{{K3S_KUBECONFIG_OUTPUT}}"
      K3S_KUBECONFIG_MODE: "{{K3S_KUBECONFIG_MODE}}"
      K3S_AGENT_TOKEN_FILE: "{{K3S_AGENT_TOKEN_FILE}}"
      CLUSTER_CIDR: "{{CLUSTER_CIDR}}"
      SERVICE_CIDR: "{{SERVICE_CIDR}}"
      CLUSTER_DNS: "{{CLUSTER_DNS}}"
      FLANNEL_BACKEND: "{{FLANNEL_BACKEND}}"
      LOCAL_PROVISIONER_PATH: "{{LOCAL_PROVISIONER_PATH}}"
      CONTAINER_RUNTIME_ENDPOINT: "{{CONTAINER_RUNTIME_ENDPOINT}}"
      PRIVATE_REGISTRY: "{{PRIVATE_REGISTRY}}"
      K3S_URL: "{{K3S_URL}}"
    v: 2
    args:
    - "{{ '-v '+(v|string) if v|default(false) else '' }}"
    - "--data-dir {{DATA}}"
    - "--flannel-backend {{FLANNEL_BACKEND}}"
    # etc input
    - "--token-file {{K3S_TOKEN_FILE}}"
    # etc output
    ##- "--write-kubeconfig {{K3S_KUBECONFIG_OUTPUT}}"
    ##- "--write-kubeconfig-mode {{K3S_KUBECONFIG_MODE}}"
    - "{{ '--container-runtime-endpoint '+CONTAINER_RUNTIME_ENDPOINT if CONTAINER_RUNTIME_ENDPOINT != '' else '' }}"
    - "{{ '--private-registry '+PRIVATE_REGISTRY if PRIVATE_REGISTRY != '' else '' }}"
    - "--server {{K3S_URL}}"
  tasks:
  - include: tasks/compfuzor.includes type=srv
