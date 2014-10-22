---
- hosts: all
  tags:
  - etcd_srv
  gather_facts: False
  vars:
    TYPE: etcd
    INSTANCE: "main-{{inventory_hostname}}-{{client_port}}"

    VAR_DIR: True
    SYSTEMD_SERVICE: True

    client_port: "{{port|default(4001)}}"
    peer_port: "{{client_port|int+3000}}"
    ENV:
      etcd_name: "{{name|default(NAME)}}"
      etcd_advertise_client_urls: "{{advertise_client_urls|default('http://'+inventory_hostname+':'+client_port)}}"
      etcd_listen_client_urls: "{{listen_client_urls|default('http://'+inventory_hostname+':'+client_port)}}"
      #etcd_advertise_peer_urls: "{{advertise_peer_urls|default('http://'+inventory_hostname+':'+peer_port)}}"
      etcd_listen_peer_urls: "{{listen_peer_urls|default('http://'+inventory_hostname+':'+peer_port)}}"
      etcd_cluster_active_size: "{{cluster_active_size|default(3)}}"
      etcd_data_dir: "{{VAR}}"

      #etcd_initial_cluster: "{{ lookup('template', './files/etcd/initial-cluster.j2') }}"
      etcd_initial_cluster: "{% set comma = joiner(',') %}{% for h in range(play_hosts|length) %}{{ comma() }}{{NAME}}-{{h}}=http://{{play_hosts[h]}}:{{hostvars[play_hosts[h]]['peer_port']|default(vars['peer_port'])}}{% endfor %}"
      etcd_initial_cluster_state: new
    ETCD_BIN: /usr/local/bin/etcd
  tasks:
  - include: tasks/compfuzor.includes type=srv
  - shell: echo {{item}}
    with_items: play_hosts
