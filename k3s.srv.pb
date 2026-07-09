---
- hosts: all
  vars:
    TYPE: "k3s{{ is_control_plane|ternary('-server', '-agent') }}"
    INSTANCE: "{{ DOMAIN|replace('.', '-') }}"
    PASSWORDS:
    - name: token
      format: 'echo "$(pwgen -As 6 1).$(pwgen -As 16 1)"'
    - name: agentToken
      format: 'echo "$(pwgen -As 6 1).$(pwgen -As 16 1)"'
    PASSWORDS_FILES: true
    PASSWORDS_DIR: "{{ETC}}/secrets"
    ETC_FILES:
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
    # Role derivation: kubelet and control_plane are per-host inventory vars.
    # If neither is set, both default true (full k3s server). If either is
    # set, the other defaults false. This allows:
    #   (nothing)            → control_plane + kubelet (full server)
    #   kubelet: true        → agent only (k3s agent)
    #   control_plane: true  → agentless server (k3s server --disable-agent)
    _role_set: "{{ kubelet is defined or control_plane is defined }}"
    is_kubelet: "{{ kubelet | default(not _role_set | bool) | bool }}"
    is_control_plane: "{{ control_plane | default(not _role_set | bool) | bool }}"
    # Multi-server topology. K3S_BOOTSTRAP designates which host runs
    # --cluster-init on first bringup. Defaults to first sorted host in the
    # cluster group; override via -e K3S_BOOTSTRAP=<hostname>. Joining servers
    # get --server $K3S_URL instead of --cluster-init.
    _bootstrap_host: "{{ K3S_BOOTSTRAP | default(groups[cluster]|default([inventory_hostname])|sort|first, true) }}"
    is_bootstrap: "{{ inventory_hostname == _bootstrap_host }}"
    is_multiserver: "{{ (groups[cluster]|default([inventory_hostname])|length) > 1 }}"
    # all hostnames in the cluster group (for tls-san aggregation across peers)
    _cluster_hosts: "{{ groups[cluster] | default([inventory_hostname]) }}"

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
      - "{{is_control_plane|ternary('server', 'agent')}}"
      - "{{commonArgs|reject('eq', '')|join(' ')}}"
      - "{{(is_control_plane|ternary(serverArgs, agentArgs))|reject('eq', '')|join(' ')}}"
    SYSTEMD_SERVICES:
      Delegate: yes
      ExecStart: "{{_exec|join(' ')}}"
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

    # Control-plane-only toolkit. reset.sh is manual cluster-reset for
    # single-server IP-drift recovery (refuses on multi-server); status.sh
    # is a read-only diagnostic. Deployed raw from files/k3s-server/ to
    # {{BINS_DIR}}/.
    server_bins:
      - name: status.sh
        src: status.sh
        raw: True
      - name: reset.sh
        src: reset.sh
        raw: True
    BINS: "{{ server_bins if is_control_plane else [] }}"

    # non k3s
    DOMAIN: "{{domain|default('base.yoyodyne.example.net')}}"
    CLUSTER_DOMAIN: "cluster.{{DOMAIN}}"
    DATA: "{{VAR}}/data"
    K3S_TOKEN_FILE: "{{PASSWORDS_DIR}}/token"
    # do not set to default, will create bad symlink
    #K3S_KUBECONFIG_OUTPUT: "{{ETC}}/k3s.yaml"
    K3S_KUBECONFIG_OUTPUT: ""
    K3S_KUBECONFIG_MODE: "0640"
    K3S_AGENT_TOKEN_FILE: "{{PASSWORDS_DIR}}/agentToken"
    K3S_CONFIG_FILE: "{{ETC}}/config.yaml"

    # k3s common
    CONTAINER_RUNTIME_ENDPOINT: false
    NODE_IP: false
    NODE_EXTERNAL_IP: false
    NODE_NAME: false
    PRIVATE_REGISTRY: false
    K3S_URL: ""
    K3S_BOOTSTRAP: false
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
    SECRETS_ENCRYPTION: true
    SECRETS_ENCRYPTION_PROVIDER: secretbox
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
      K3S_TOKEN_FILE: "{{K3S_TOKEN_FILE}}"
      K3S_AGENT_TOKEN_FILE: "{{K3S_AGENT_TOKEN_FILE}}"
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
      K3S_URL: "{{'https://' + K3S_URL|default(_bootstrap_host + ':6443', true) if K3S_URL is not search('https://') else K3S_URL}}"
      V: "{{V|default(2)}}"
      # common
      NODE_IP: "{{NODE_IP|default('', true)}}"
      NODE_EXTERNAL_IP: "{{NODE_EXTERNAL_IP|default('', true)}}"
      # server
      ETCD_SNAPSHOT_RETENTION: "{{ETCD_SNAPSHOT_RETENTION}}"
      SNAPSHOTTER: "{{SNAPSHOTTER}}"
      DISABLE_LIST: "{{DISABLE_LIST}}"
      KUBELET_ARGS: "{{KUBELET_ARGS}}"
      K3S_MULTISERVER: "{{ '1' if is_multiserver else '0' }}"

    # TODO/fantasy: make commonEnv/serverEnv/agentEnv and something to generate EXEC from that k/v!
    commonArgs:
    - "--data-dir $DATA"
    - "-v $V"
    - "{{ '--node-ip $NODE_IP' if NODE_IP|default(False) else '' }}"
    - "{{ '--node-external-ip $NODE_EXTERNAL_IP' + NODE_EXTERNAL_IP if NODE_EXTERNAL_IP|default(False) else '' }}"
    - "{{ '--private-registry $PRIVATE_REGISTRY' if PRIVATE_REGISTRY|default(False) else '' }}"
    - "{{ '--kubelet-arg $KUBELET_ARGS' if KUBELET_ARGS else '' }}"
    agentArgs: {}
    serverArgs:
    # bootstrap server initializes the cluster; joiners contact it via --server.
    - "{{ '--cluster-init' if is_bootstrap else '--server $K3S_URL' }}"
    - "{{ '--disable-agent' if not is_kubelet else '' }}"
    #- "--tls-san $CLUSTER_DOMAIN"
    - "{{ '--tls-san '+extraDomains|listify|concat(_cluster_hosts, extraIpv4Domains)|unique|join(',') if extraDomains|default(False) else '' }}"
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
    - "{{ '--container-runtime-endpoint $CONTAINER_RUNTIME_ENDPOINT' if CONTAINER_RUNTIME_ENDPOINT|default(False) else '' }}"
    - "{{ '--etcd-snapshot-retention $ETCD_SNAPSHOT_RETENTION' if ETCD_SNAPSHOT_RETENTION|default(False) else '' }}" # at 12 hour interval
    - "--etcd-snapshot-compress"
    - "--secrets-encryption"
    - "--secrets-encryption-provider {{SECRETS_ENCRYPTION_PROVIDER}}"
    - "{{ '--disable $DISABLE_LIST' if DISABLE_LIST|length > 0 else ''}}"
    - "{{ '--disable-network-policy' if DISABLE is superset(['network-policy']) else '' }}"
    - "{{ '--disable-kube-proxy' if DISABLE is superset(['kube-proxy']) else '' }}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
