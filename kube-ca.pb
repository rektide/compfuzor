# please see https://jvns.ca/blog/2017/08/05/how-kubernetes-certificates-work/ which explains these 5 CAs
- hosts: all
  vars:
    TYPE: kube-ca
    INSTANCE: main
    ETC_FILES:
    - name: cas.json
      content: "{{CAs|to_nice_json}}"

    etcd: "etcd-{{INSTANCE}}"
    etcd_client: "etcd-client-{{INSTANCE}}"
    etcd_server: "etcd-server-{{INSTANCE}}"
    etcd_peer: "etcd-peer-{{INSTANCE}}"
    controller_manager: "kubernetes-controller-manager-{{INSTANCE}}"
    kubelet: "kubernetes-kubelet-{{INSTANCE}}"
    kubelet_client: "kubernetes-kubelet-client-{{INSTANCE}}"
    api: "kubernetes-api-{{INSTANCE}}"
    aggregator: "kubernetes-aggregator-{{INSTANCE}}"

    CA_PARENT: "ca-{{INSTANCE}}"
    DEFAULT_DOMAIN: "{{INSTANCE|replace('-', '.')}}"
    CAs:
    - name: parent
      external: "{{EXTERNAL|default(CA_PARENT)}}"
      externalSub: "current-intermediate" # use this sub-ca within the parent ca. optional.
      comment: point to an external ca to sign these ca's with
    - name: ca
      defaultParent: true
      parent: "parent" # it has an external parent
    - name: intermediary
      alias: current-intermediate
      parent: ca # all other's will be signed with this if they have no parent
      defaultParent: true
    - name: "{{aggregator}}"
    - name: "{{api}}"
      comment: base api server certs

    - name: "{{etcd}}"
      comment: etcd bears this identity
    - name: "{{etcd_client}}"
      comment: clients connecting to etcd bear this identity
      parent: "{{etcd}}"
      consumer:
      - "{{api}}"
    - name: "{{etcd_server}}"
      parent: "{{etcd}}"
    - name: "{{etcd_peer}}"
      parent: "{{etcd}}"

    - name: kubelet
      comment: kubelet uses this for it's identity, as \"tls\"
      owner:
      - "{{kubelet}}"
      consumer:
      - "{{kubelet_client}}"
    - name: kubelet-client
      comment: clients must bear certs with this ca
      owner:
      - "{{kubelet_client}}"
      consumer:
      - "{{kubelet}}"
    - name: proxy-client
      comment: agents talking to api-server or aggregator use these identities
      owner: "{{api}}"
    - name: requestheader
      comment: compfuzor is not setup for authenticating proxies but creates the ca s.t. configs can use it
      owner:
      - "{{api}}"
    - name: service-account
      comment: 
      owner:
      - "{{controller_manager}}"
    CERTS:
    - cn: kubecfg
      org: system:masters
      owner: "{{controller_manager}}" # a guess
    ENV:
      ETC: "{{DIR}}/etc"
      VAR: "{{DIR}}/var"
  tasks:
  - include: tasks/compfuzor.includes type=srv
  # two outputs: 
  # 1. ca's
  # 2. env files appropriate 
