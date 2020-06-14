---
- hosts: all
  vars:
    TYPE: k3s
    INSTANCE: "{{ DOMAIN|replace('.', '-') }}"
    PASSWORD:
    - token
    - agentToken
    PASSWORD_LENGTH: 96
    ETC_FILES:
    - name: token
      var: token
    - name: agent-token
      var: agentToken
    VAR_DIRS:
    - data
    - local-provisioner

    # unit
    SYSTEMD_UNITS:
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
    - "--tls-san {{CLUSTER_DOMAIN}}"
    - "--cluster-domain {{CLUSTER_DOMAIN}}"
    - "--data-dir {{DATA}}"
    - "--cluster-cidr {{CLUSTER_CIDR}}"
    - "--service-cidr {{SERVICE_CIDR}}"
    - "--cluster-dns {{CLUSTER_DNS}}"
    - "--flannel-backend {{FLANNEL_BACKEND}}"
    # etc input
    ##- "--token-file {{K3S_TOKEN_FILE}}"
    ##- "--agent-token-file {{K3S_AGENT_TOKEN_FILE}}"
    # etc output
    ##- "--write-kubeconfig {{K3S_KUBECONFIG_OUTPUT}}"
    ##- "--write-kubeconfig-mode {{K3S_KUBECONFIG_MODE}}"
    - "--default-local-storage-path {{LOCAL_PROVISIONER_PATH}}"
    - "{{ '--container-runtime-endpoint '+CONTAINER_RUNTIME_ENDPOINT if CONTAINER_RUNTIME_ENDPOINT != '' else '' }}"
    - "{{ '--private-registry '+PRIVATE_REGISTRY if PRIVATE_REGISTRY != '' else '' }}"
    ##- "--server {{K3S_URL}}"
  tasks:
  - include: tasks/compfuzor.includes type=srv
