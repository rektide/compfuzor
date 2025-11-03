---
- hosts: all
  vars:
    TYPE: "k3s{{ is_agent|default(False)|ternary('-agent', '-server') }}"
    INSTANCE: "{{ DOMAIN|replace('.', '-') }}"
    PASSWORDS:
    - token
    - agentToken
    PASSWORD_LENGTH: 96
    ETC_FILES:
    - name: token
      var: token
    - name: agent-token
      var: agentToken
    - name: config.toml.tmpl
    VAR_DIRS:
    - data/agent/etc/containerd
    - local-provisioner
    LINKS:
    - src: "{{ETC}}/config.toml.tmpl"
      dest: "{{VAR}}/data/agent/etc/containerd/config.toml.tmpl"
    - src: "{{VAR}}/data"
      dest: "/var/lib/rancher/k3s"
    - src: "{{ETC}}"
      dest: "/etc/rancher/k3s"
    is_agent: False

    # unit
    SYSTEMD_UNITS:
      Description: "{{ NAME }}"
      After: network-online.target
      Wants: network-online.target
    # service
    SYSTEMD_SERVICE: True
    SYSTEMD_EXEC:
    - "/usr/local/bin/k3s"
    - "{{is_agent|ternary('agent', 'server')}}"
    - "{{commonArgs|join(' ')}}"
    - "{{is_agent|ternary(agentArgs, serverArgs)|join(' ')}}"
    # support added in https://github.com/rancher/k3s/pull/100 ?
    SYSTEMD_SERVICES:
      Delegate: yes
      ExecStartPre:
      - "-/sbin/modprobe br_netfilter"
      - "-/sbin/modprobe overlay"
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
      Alias: "{{TYPE}}.service"

    # non k3s
    DOMAIN: "{{domain|default('base.yoyodyne.example.net')}}"
    CLUSTER_DOMAIN: "cluster.{{DOMAIN}}"
    DATA: "{{VAR}}/data"
    K3S_TOKEN_FILE: "{{ETC}}/cluster-token"
    # do not set to default, will create bad symlink
    #K3S_KUBECONFIG_OUTPUT: "{{ETC}}/k3s.yaml"
    K3S_KUBECONFIG_OUTPUT: ""
    K3S_KUBECONFIG_MODE: "0640"
    K3S_AGENT_TOKEN_FILE: "{{ETC}}/agent-token"
    K3S_CONFIG_FILE: "{{ETC}}/config.yaml"

    # k3s common
    CONTAINER_RUNTIME_ENDPOINT: false
    NODE_IP: false
    NODE_EXTERNAL_IP: false
    NODE_NAME: false
    PRIVATE_REGISTRY: false
    K3S_URL: ""
    SNAPSHOTTER: btrfs
    RESOLV_CONF: false
    PREFER_BUNDLED_BIN: false

    # k3s server
    CLUSTER_CIDR: "{{cluster_cidr|default('10.39.0.0/16')}}"
    SERVICE_CIDR: "{{service_cidr|default('10.40.0.0/16')}}"
    CLUSTER_DNS: "{{cluster_dns|default(SERVICE_CIDR | ansible.utils.ipmath(10))}}"
    FLANNEL_BACKEND: none
    LOCAL_PROVISIONER_PATH: "{{VAR}}/local-provisioner"
    DISABLE:
      - traefik
      - servicelb
      - network-policy
      - kube-proxy
    DISABLE_LIST: "{{ DISABLE|default([], true)|difference(['network-policy', 'kube-proxy'])|join(',')}}"
    DISABLE_NETWORK_POLICY: "{{ DISABLE|default([], true)|intersect(['network-policy'])|length() == 0}}"
    DISABLE_KUBE_PROXY:     "{{ DISABLE|default([], true)|intersect(['kube-proxy']    )|length() == 1}}"
    ETCD_SNAPSHOT_RETENTION: 28

    # k3s agent

    ENV:
      DOMAIN: "{{DOMAIN}}"
      CLUSTER_DOMAIN: "{{CLUSTER_DOMAIN}}"
      DATA: "{{DATA}}"
      #K3S_TOKEN_FILE: "{{K3S_TOKEN_FILE}}"
      #K3S_AGENT_TOKEN_FILE: "{{K3S_AGENT_TOKEN_FILE}}"
      K3S_KUBECONFIG_OUTPUT: "{{K3S_KUBECONFIG_OUTPUT}}"
      K3S_KUBECONFIG_MODE: "{{K3S_KUBECONFIG_MODE}}"
      #K3S_CONFIG_FILE: "{{K3S_CONFIG_FILE}}"
      #K3S_NODE_NAME: "{{}}"
      CLUSTER_CIDR: "{{CLUSTER_CIDR}}"
      SERVICE_CIDR: "{{SERVICE_CIDR}}"
      CLUSTER_DNS: "{{CLUSTER_DNS}}"
      FLANNEL_BACKEND: "{{FLANNEL_BACKEND}}"
      LOCAL_PROVISIONER_PATH: "{{LOCAL_PROVISIONER_PATH}}"
      CONTAINER_RUNTIME_ENDPOINT: "{{CONTAINER_RUNTIME_ENDPOINT|default('', true)}}"
      PRIVATE_REGISTRY: "{{PRIVATE_REGISTRY|default('', true)}}"
      K3S_URL: "{{'https://' + K3S_URL|default(inventory_hostname + ':6443', true) if K3S_URL is not search('https://') else K3S_URL}}"
      V: "{{V|default(2)}}"
      # common
      NODE_IP: "{{NODE_IP|default('', true)}}"
      NODE_EXTERANL_IP: "{{NODE_EXTERNAL_IP|default('', true)}}"
      # server
      ETCD_SNAPSHOT_RETENTION: "{{ETCD_SNAPSHOT_RETENTION}}"
      SNAPSHOTTER: "{{SNAPSHOTTER}}"
      DISABLE_LIST: "{{DISABLE_LIST}}"

    # TODO/fantasy: make commonEnv/serverEnv/agentEnv and something to generate EXEC from that k/v!
    commonArgs:
    - "--data-dir ${DATA}"
    - "-v $V"
    - "{{ '--node-ip ${NODE_IP}' if NODE_IP|default(False) else '' }}"
    - "{{ '--node-external-ip ${NODE_EXTERNAL_IP}' + NODE_EXTERNAL_IP if NODE_EXTERNAL_IP|default(False) else '' }}"
    - "{{ '--private-registry ${PRIVATE_REGISTRY}' if PRIVATE_REGISTRY|default(False) else '' }}"
    agentArgs: {}
    serverArgs:
    #- "--tls-san $CLUSTER_DOMAIN"
    - "{{ '--tls-san '+extraDomains|concat(extraIpv4Domains)|join(',') if extraDomains|default(False) else '' }}"
    - "--cluster-domain ${CLUSTER_DOMAIN}"
    - "--cluster-cidr ${CLUSTER_CIDR}"
    - "--service-cidr ${SERVICE_CIDR}"
    - "--cluster-dns ${CLUSTER_DNS}"
    - "--flannel-backend ${FLANNEL_BACKEND}"
    # etc input
    # etc output
    ##- "--write-kubeconfig {{K3S_KUBECONFIG_OUTPUT}}"
    ##- "--write-kubeconfig-mode {{K3S_KUBECONFIG_MODE}}"
    - "--default-local-storage-path ${LOCAL_PROVISIONER_PATH}"
    - "{{ '--container-runtime-endpoint ${CONTAINER_RUNTIME_ENDPOINT}' if CONTAINER_RUNTIME_ENDPOINT|default(False) != '' else '' }}"
    - "{{ '--etcd-snapshot-retention ${ETCD_SNAPSHOT_RETENTION}' if ETCD_SNAPSHOT_RETENTION|default(False) else '' }}" # at 12 hour interval
    - "--etcd-snapshot-compress"
    - "{{ '--disable ${DISABLE_LIST}' if DISABLE_LIST|length > 0 else ''}}"
    - "{{ '--disable-network-policy' if DISABLE is superset(['network-policy']) else '' }}"
    - "{{ '--disable-kube-proxy' if DISABLE is superset(['kube-proxy']) else '' }}"
    - "--secrets-encryption=true"
    - "--secrets-encryption-provider=secretbox"
  tasks:
    - name: insure basic rancher directories
      file:
        path: "{{item}}"
        state: directory
      loop:
        - /var/lib/rancher
        - /etc/rancher
      become: True
    - import_tasks: tasks/compfuzor.includes
