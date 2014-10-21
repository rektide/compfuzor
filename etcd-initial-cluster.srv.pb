---
- hosts: all
  tags:
  - etcd_srv
  gather_facts: False
  vars:
    TYPE: etcd
    INSTANCE: main
    port: 4001

    VAR_DIR: True
    ETCD_FILES:
    - envfile
    SYSTEMD_SERVICE: True

    client_port: "{{advertise_client_port|default(client_port|default(4001)}}"
    peer_port: "{{advertise_client_port|default(client_port|default(client_port|int+3000)}}"
    ENV:
      etcd_name: "{{name|default(NAME)}}"
      etcd_advertise_client_urls: "{{advertise_client_urls|default('http://'+inventory_hostname+':'+client_port)}}"
      etcd_listen_client_urls: "{{listen_client_urls|default('http://'+inventory_hostname+':'+client_port}}"
      etcd_advertise_peer_urls: "{{advertise_peer_urls|default('http://'+inventory_hostname+':'+advertise}}"
      etcd_listen_peer_urls: "{{listen_peer_urls}}"
      etcd_cluster_active_size: {{cluster_active_size|default(3)}}
      etcd_data_dir: "{{VAR}}"

      etcd_initial_cluster: "$TEMPLATE('files/etcd/cluster-initial.j2')"
      etcd_initial_cluster_state: new
    ETCD_BIN: /usr/local/bin/etcd
  tasks:
  - include: tasks/compfuzor.includes type=srv
