# please see https://jvns.ca/blog/2017/08/05/how-kubernetes-certificates-work/ which explains these 5 CAs
- hosts: all
  vars:
    TYPE: kube-ca
    INSTANCE: main

    etcd: "etcd"
    controller-manager: "kubernetes-controller-manager"
    kubelet: "kubernetes-kubelet"
    kubelet-client: "kubernetes-kubelet-client"
    api: "kubernetes-api"

    CA_PARENT: "ca-{{INSTANCE}}"
    CAs:
    - name: ca
      external: "{{parent}}"
      comment: point to an external ca to sign these ca's with
    - name: aggregator
      owner: "{{aggregator}}"
    - name: api
      comment: base api server certs
      owner: "{{api}}"
    - name: etcd
      comment: etcd bears this identity
      owner: "{{etcd}}"
      consumer:
      - "{{api-server}}"
    - name: etcd-ca
      comment: clients connecting to etcd bear this identity
      consumer:
      - "{{api}}"
    - name: kubelet
      comment: kubelet uses this for it's identity, as \"tls\"
      owner:
      - "{{kubelet}}"
      consumer:
      - "{{kubelet-client}}"
    - name: kubelet-client
      comment: clients must bear certs with this ca
      owner:
      - "{{kubelet-client}}"
      consumer:
      - "{{kubelet}}"
    - name: proxy-client
      comment: agents talking to api-server or aggregator use these identities
      owner: "{{api-server}}"
    - name: requestheader
      comment: compfuzor is not setup for authenticating proxies but creates the ca s.t. configs can use it
      owner:
      - "{{api-server}}"
    - name: service-account
      comment: 
      owner:
      - "{{controller-manager}}"
  tasks:
  - include: tasks/compfuzor.includes
  # two outputs: 
  # 1. ca's
  # 2. env files appropriate 
