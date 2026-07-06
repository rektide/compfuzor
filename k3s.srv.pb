---
- hosts: all
  vars:
    TYPE: "k3s{{ is_server|ternary('-server', '-agent') }}"
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
    is_server: "{{ 'servers' in group_names }}"
    # TODO(multi-server): this playbook currently only supports single-server
    #   embedded-etcd clusters. To support HA control planes:
    #   - distinguish bootstrap server from joining servers (e.g. by inventory
    #     order: groups['servers']|sort|first is bootstrap, the rest join).
    #   - joining servers need `--server <peer-url>` (currently absent from
    #     serverArgs below) and must NOT receive --cluster-init (the empty-etcd
    #     branch in launch.sh:9 would otherwise fork a second cluster).
    #   - K3S_URL below defaults to inventory_hostname (self), which is wrong
    #     for joining servers; it must point at an existing server peer.
    #   - launch.sh's --cluster-reset-on-drift MUST be gated off for
    #     multi-server (cluster-reset = etcd --force-new-cluster severs the
    #     node from its peers). Plan: write K3S_MULTISERVER env var here from
    #     groups['servers']|length and have launch.sh skip the reset branch.

    # unit
    SYSTEMD_UNITS:
      Description: "{{ NAME }}"
      After: network-online.target
      Wants: network-online.target
    # service
    #SYSTEMD_SERVICE: True
    # support added in https://github.com/rancher/k3s/pull/100 ?
    _exec:
      - "/usr/local/bin/k3s"
      - "{{is_server|ternary('server', 'agent')}}"
      - "{{commonArgs}}"
      - "{{is_server|ternary(serverArgs, agentArgs)}}"
    _execPre:
      - "-/sbin/modprobe br_netfilter"
      - "-/sbin/modprobe overlay"
    SYSTEMD_SERVICES:
      Delegate: yes
      # Servers wrap k3s through bin/launch.sh, which detects node-IP drift
      # (DHCP changes across reboots) and runs --cluster-reset before exec'ing
      # k3s. cluster-reset is etcd's --force-new-cluster: it preserves local
      # data but resets membership to a single member -- so launch.sh is
      # SINGLE-SERVER ONLY. On multi-server it would sever the cluster.
      # Agents don't run etcd, so no drift risk.
      ExecStart: "{{ (BINS_DIR + '/launch.sh ') if is_server else '' }}{{_exec|join(' ')}}"
      ExecStartPre: "{{_execPre|join(' ')}}"
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

    # Server-only toolkit. launch.sh wraps ExecStart for drift detection;
    # status.sh is a read-only diagnostic; recover.sh is manual cluster-reset
    # for the current broken state (launch.sh handles future drift).
    # Deployed raw from files/k3s-server/ to {{BINS_DIR}}/.
    server_bins:
      - name: launch.sh
        src: launch.sh
        raw: True
      - name: status.sh
        src: status.sh
        raw: True
      - name: recover.sh
        src: recover.sh
        raw: True
    BINS: "{{ server_bins if is_server else [] }}"

    # non k3s
    DOMAIN: base.yoyodyne.example.net
    CLUSTER_DOMAIN: "cluster.{{DOMAIN}}"
    DATA: "{{VAR}}/data"
    K3S_TOKEN_FILE: "{{ETC}}/token"
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
    CLUSTER_CIDR: "10.39.0.0/16"
    SERVICE_CIDR: "10.40.0.0/16"
    CLUSTER_DNS: "10.40.0.2"
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
    # Kubelet eviction thresholds; empty string disables. Single-arg form
    # uses k3s/kubelet's default soft+hard parsing. Example below matches the
    # production workhorse-voodoowarez-com deployment.
    # Example: "eviction-hard=nodefs.available<25Gi,imagefs.available<25Gi"
    KUBELET_ARGS: ""

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
      NODE_EXTERNAL_IP: "{{NODE_EXTERNAL_IP|default('', true)}}"
      # server
      ETCD_SNAPSHOT_RETENTION: "{{ETCD_SNAPSHOT_RETENTION}}"
      SNAPSHOTTER: "{{SNAPSHOTTER}}"
      DISABLE_LIST: "{{DISABLE_LIST}}"
      KUBELET_ARGS: "{{KUBELET_ARGS}}"

    # TODO/fantasy: make commonEnv/serverEnv/agentEnv and something to generate EXEC from that k/v!
    commonArgs:
    - "--data-dir $DATA"
    - "-v $V"
    - "{{ '--node-ip $NODE_IP' if NODE_IP|default(False) else '' }}"
    - "{{ '--node-external-ip $NODE_EXTERNAL_IP' + NODE_EXTERNAL_IP if NODE_EXTERNAL_IP|default(False) else '' }}"
    - "{{ '--private-registry $PRIVATE_REGISTRY' if PRIVATE_REGISTRY|default(False) else '' }}"
    - "{{ '--kubelet-arg $KUBELET_ARGS' if KUBELET_ARGS else '' }}"
    agentArgs: {}
    # TODO(multi-server): serverArgs needs a conditional `--server $JOIN_URL`
    #   for non-bootstrap servers (joining an existing cluster). The bootstrap
    #   server uses --cluster-init (added by launch.sh when etcd data is empty)
    #   but joining servers must NOT receive --cluster-init and MUST receive
    #   --server pointing at an existing peer. Currently absent; without it a
    #   second server would silently fork a new cluster via --cluster-init.
    serverArgs:
    #- "--tls-san $CLUSTER_DOMAIN"
    - "{{ '--tls-san '+extraDomains|listify|concat(extraIpv4Domains)|join(',') if extraDomains|default(False) else '' }}"
    - "--cluster-domain $CLUSTER_DOMAIN"
    - "--cluster-cidr $CLUSTER_CIDR"
    - "--service-cidr $SERVICE_CIDR"
    - "--cluster-dns $CLUSTER_DNS"
    - "--flannel-backend $FLANNEL_BACKEND"
    # etc input
    # etc output
    ##- "--write-kubeconfig {{K3S_KUBECONFIG_OUTPUT}}"
    ##- "--write-kubeconfig-mode {{K3S_KUBECONFIG_MODE}}"
    - "--default-local-storage-path {{LOCAL_PROVISIONER_PATH}}"
    - "{{ '--container-runtime-endpoint $CONTAINER_RUNTIME_ENDPOINT' if CONTAINER_RUNTIME_ENDPOINT|default(False) != '' else '' }}"
    - "{{ '--etcd-snapshot-retention $ETCD_SNAPSHOT_RETENTION' if ETCD_SNAPSHOT_RETENTION|default(False) else '' }}" # at 12 hour interval
    - "--etcd-snapshot-compress"
    - "{{ '--disable $DISABLE_LIST' if DISABLE_LIST|length > 0 else ''}}"
    - "{{ '--disable-network-policy' if DISABLE is superset(['network-policy']) else '' }}"
    - "{{ '--disable-kube-proxy' if DISABLE is superset(['kube-proxy']) else '' }}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
