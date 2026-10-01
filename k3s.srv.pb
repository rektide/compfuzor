---
- hosts: all
  vars:
    TYPE: "k3s{{ is_control_plane|ternary('-server', '-agent') }}"
    INSTANCE: "{{ DOMAIN|replace('.', '-') }}"
    PASSWORDS:
    - name: token
      format: 'pwgen -s 32 1'
    - name: agentToken
      format: 'pwgen -s 32 1'
    PASSWORDS_FILES: true
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
    # Explicit apiserver SAN list: extra names + cluster hostnames + the
    # pinned node IP (auto-included in the serving cert by --node-ip anyway,
    # but listed to keep the unit self-describing) + extraSans. NEVER
    # aggregate ansible_all_ipv4_addresses into tls-san: on DHCP hosts that
    # freezes the deploy-time lease into the unit -- the recurring "bad ip".
    TLS_SANS: >-
      {{ (extraDomains|default([]) + _cluster_hosts + extraSans|default([])
          + ([NODE_IP] if NODE_IP|default(False) else [])) | unique }}

    # unit(s) via SYSTEMD_ROOTS: the main server unit plus (when
    # ETCD_SNAPSHOT_SINK is set) the snapshot-sync pair. Roots keep every
    # unit's sections self-contained: top-level SYSTEMD_* sections leak into
    # each root render (Restart/ExecStartPre/Alias collisions).
    SYSTEMD_ROOTS: "{{ ['k3sUnit'] + (['snapSyncService', 'snapSyncTimer'] if ETCD_SNAPSHOT_SINK else []) }}"
    #service
    #SYSTEMD_SERVICE: True
    # support added in https://github.com/rancher/k3s/pull/100 ?
    _exec:
      - "/usr/local/bin/k3s"
      - "{{is_control_plane|ternary('server', 'agent')}}"
      - "{{commonArgs|reject('eq', '')|join(' ')}}"
      - "{{(is_control_plane|ternary(serverArgs, agentArgs))|reject('eq', '')|join(' ')}}"
    k3sUnit:
      SYSTEMD_SERVICE: "{{NAME}}"
      SYSTEMD_UNITS:
        Description: "{{ NAME }}"
        After: network-online.target
        Wants: network-online.target
      SYSTEMD_SERVICES:
        Delegate: yes
        ExecStart: "{{_exec|join(' ')}}"
        ExecStartPre:
          - "-/sbin/modprobe br_netfilter"
          - "-/sbin/modprobe overlay"
          # no "-" prefix: a failed guard must block the k3s start. The guard
          # auto-recovers single-server etcd member peer-URL drift (DHCP lease
          # change) via a one-shot cluster-reset, or verifies a static NODE_IP
          # pin is assigned; systemd restarts (RestartSec=30s) until it passes.
          - "{{DIR}}/bin/drift-guard.sh"
        # Kubelet forces kernel.panic_on_oops=1 at startup. Its
        # --protect-kernel-defaults option only turns that rewrite into a fatal
        # mismatch; it does not preserve a local value of 0. Leave this disabled
        # while collecting the next ramoops capture. Afterwards, uncomment it to
        # restore oops-without-panic after k3s reaches READY=1. kernel.panic=10 is
        # intentionally retained for genuine panics and manual ramoops tests.
        # Compfuzor will then emit ExecStartPost= into the generated k3s systemd
        # unit. Systemd runs it as root after READY=1 on every service start,
        # changing the live sysctl only; it does not persist the value across boot.
        # ExecStartPost:
        #   - "/usr/sbin/sysctl -w kernel.panic_on_oops=0"
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

    # off-box snapshot sync pair, generated only when ETCD_SNAPSHOT_SINK is
    # set (control-plane concern; harmless definition when unset).
    snapSyncService:
      SYSTEMD_SERVICE: "{{NAME}}-snapshot-sync"
      # the timer activates this unit; installing only links the file
      SYSTEMD_ENABLE: false
      SYSTEMD_UNITS:
        Description: "{{NAME}} etcd snapshot off-box sync"
        RequiresMountsFor: "{{ETCD_SNAPSHOT_SINK}}"
      SYSTEMD_SERVICES:
        Type: oneshot
        ExecStart: "{{DIR}}/bin/snapshot-sync.sh {{ETCD_SNAPSHOT_SINK}}"
        # script sources lib.sh -> env itself; no unit env inheritance
        EnvironmentFile: false
    snapSyncTimer:
      SYSTEMD_TIMER: "{{NAME}}-snapshot-sync"
      SYSTEMD_UNITS:
        Description: "Hourly {{NAME}} etcd snapshot sync"
      SYSTEMD_TIMERS:
        OnCalendar: hourly
        Persistent: true
        Unit: "{{NAME}}-snapshot-sync.service"
      SYSTEMD_INSTALLS:
        WantedBy: timers.target

    # Control-plane-only toolkit, deployed raw from files/k3s-server/ to
    # {{BINS_DIR}}/. All scripts discover their instance via bin/lib.sh
    # (BASH_SOURCE -> ../env -> DATA/NAME), so they work for any instance.
    #   status.sh        read-only diagnostic report
    #   drift-guard.sh   ExecStartPre: auto cluster-reset on node-IP drift,
    #                    or pin verification when NODE_IP is set
    #   reset.sh         manual single-server cluster-reset (drift remedy /
    #                    re-pin to a new node IP)
    #   restore.sh       snapshot restore (--cluster-reset-restore-path)
    #   etcd.sh          etcd/snapshot inspection + on-demand snapshot
    #   snapshot-sync.sh off-box snapshot copy (driven by snapshot-sync timer)
    #   lib.sh           shared helpers (sourced, not run)
    server_bins:
      - name: lib.sh
        src: lib.sh
        raw: True
      - name: status.sh
        src: status.sh
        raw: True
      - name: drift-guard.sh
        src: drift-guard.sh
        raw: True
      - name: reset.sh
        src: reset.sh
        raw: True
      - name: restore.sh
        src: restore.sh
        raw: True
      - name: etcd.sh
        src: etcd.sh
        raw: True
      - name: snapshot-sync.sh
        src: snapshot-sync.sh
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
    NODE_IP: "{{k3s_node_ip|default(False)}}"
    NODE_EXTERNAL_IP: false
    NODE_NAME: false
    PRIVATE_REGISTRY: false
    K3S_URL: ""
    K3S_BOOTSTRAP: false
    SNAPSHOTTER: btrfs
    RESOLV_CONF: false
    PREFER_BUNDLED_BIN: false

    # k3s server
    # `k3s_*` names are inventory-facing inputs. Ansible play vars outrank
    # inventory vars, so inventory must not try to override these derived
    # uppercase runtime names directly.
    CLUSTER_CIDR: "{{k3s_cluster_cidr|default('10.39.0.0/16')}}"
    SERVICE_CIDR: "{{k3s_service_cidr|default('10.40.0.0/16')}}"
    CLUSTER_DNS: "{{k3s_cluster_dns|default('10.40.0.2')}}"
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
    ETCD_SNAPSHOT_RETENTION: "{{k3s_etcd_snapshot_retention|default(28)}}"
    # etcd slow-apply warning threshold. Embedded etcd logs "apply request
    # took too long" past this duration (upstream default 100ms); on this
    # iops-starved box 500ms is the realistic floor. Inventory override:
    #   k3s_etcd_warn_apply_duration: 1s
    ETCD_WARN_APPLY_DURATION: "{{k3s_etcd_warn_apply_duration|default('500ms')}}"
    # Off-box snapshot sync: set inventory input k3s_etcd_snapshot_sink (e.g.
    # an autofs CIFS mount like /mnt/bitblaster/backup/<name>); an hourly
    # <NAME>-snapshot-sync.{service,timer} pair copies new snapshot zips
    # there (no-clobber; sink pruned to the newest ETCD_SNAPSHOT_SINK_KEEP
    # entries). Empty disables the units entirely. ETCD_SNAPSHOT_SINK_CREDS
    # additionally mirrors the DR secrets (cluster token, agent token,
    # secrets-encryption key) into <sink>/creds/ -- without them a snapshot
    # cannot be restored on fresh hardware.
    ETCD_SNAPSHOT_SINK: "{{k3s_etcd_snapshot_sink|default('')}}"
    ETCD_SNAPSHOT_SINK_KEEP: "{{k3s_etcd_snapshot_sink_keep|default(120)}}"
    ETCD_SNAPSHOT_SINK_CREDS: "{{k3s_etcd_snapshot_sink_creds|default('false')}}"
    SECRETS_ENCRYPTION: true
    SECRETS_ENCRYPTION_PROVIDER: secretbox
    # Kubelet pass-through arguments. Accepts either one string (backwards
    # compatible) or a list; every item becomes its own repeated
    # `--kubelet-arg <item>`. Keep host/storage-specific policy in inventory.
    # Inventory example:
    #   k3s_kubelet_args:
    #     - eviction-hard=nodefs.available<25Gi,imagefs.available<30Gi
    #     - image-gc-high-threshold=98
    #     - image-gc-low-threshold=97
    KUBELET_ARGS: "{{k3s_kubelet_args|default([])}}"
    _KUBELET_ARGS: >-
      {{ KUBELET_ARGS if (KUBELET_ARGS is sequence and KUBELET_ARGS is not string)
         else ([KUBELET_ARGS] if KUBELET_ARGS else []) }}

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
      K3S_URL: >-
        {%- if is_bootstrap -%}
        {%- elif K3S_URL is search('https://') -%}
        {{ K3S_URL }}
        {%- else -%}
        https://{{ K3S_URL|default(_bootstrap_host + ':6443', true) }}
        {%- endif -%}
      V: "{{V|default(2)}}"
      # common
      NODE_IP: "{{NODE_IP|default('', true)}}"
      NODE_EXTERNAL_IP: "{{NODE_EXTERNAL_IP|default('', true)}}"
      # server
      ETCD_SNAPSHOT_RETENTION: "{{ETCD_SNAPSHOT_RETENTION}}"
      ETCD_SNAPSHOT_SINK: "{{ETCD_SNAPSHOT_SINK}}"
      ETCD_SNAPSHOT_SINK_KEEP: "{{ETCD_SNAPSHOT_SINK_KEEP}}"
      ETCD_SNAPSHOT_SINK_CREDS: "{{ETCD_SNAPSHOT_SINK_CREDS}}"
      SNAPSHOTTER: "{{SNAPSHOTTER}}"
      DISABLE_LIST: "{{DISABLE_LIST}}"
      # Informational copy for status/debugging; ExecStart renders one
      # --kubelet-arg per normalized item directly (below).
      KUBELET_ARGS: "{{_KUBELET_ARGS|join(' ')}}"
      K3S_MULTISERVER: "{{ '1' if is_multiserver else '0' }}"

    # TODO/fantasy: make commonEnv/serverEnv/agentEnv and something to generate EXEC from that k/v!
    commonArgs:
    - "--data-dir $DATA"
    - "-v $V"
    - "{{ '--node-ip $NODE_IP' if NODE_IP|default(False) else '' }}"
    - "{{ '--node-external-ip $NODE_EXTERNAL_IP' + NODE_EXTERNAL_IP if NODE_EXTERNAL_IP|default(False) else '' }}"
    - "{{ '--private-registry $PRIVATE_REGISTRY' if PRIVATE_REGISTRY|default(False) else '' }}"
    - "{{ _KUBELET_ARGS | map('regex_replace', '^(.*)$', '--kubelet-arg \\1') | join(' ') }}"
    agentArgs: {}
    serverArgs:
    # bootstrap server initializes the cluster; joiners contact it via --server.
    - "{{ '--cluster-init' if is_bootstrap else '--server $K3S_URL' }}"
    - "{{ '--disable-agent' if not is_kubelet else '' }}"
    #- "--tls-san $CLUSTER_DOMAIN"
    - "{{ '--tls-san ' ~ TLS_SANS|join(',') if TLS_SANS|length > 0 else '' }}"
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
    - "--etcd-arg warning-apply-duration={{ETCD_WARN_APPLY_DURATION}}"
    # - "--etcd-arg warning-unary-request-duration=500ms"
    - "--etcd-snapshot-compress"
    - "--secrets-encryption"
    - "--secrets-encryption-provider {{SECRETS_ENCRYPTION_PROVIDER}}"
    - "{{ '--disable $DISABLE_LIST' if DISABLE_LIST|length > 0 else ''}}"
    - "{{ '--disable-network-policy' if DISABLE is superset(['network-policy']) else '' }}"
    - "{{ '--disable-kube-proxy' if DISABLE is superset(['kube-proxy']) else '' }}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
