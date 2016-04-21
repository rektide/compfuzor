---
- hosts: all
  tags:
  - etcd_srv
  gather_facts: False
  vars:
    TYPE: etcd
    INSTANCE: main
    SUBINSTANCE: "{{inventory_hostname|replace('.', '-')}}{{ '-'+client_port|string if client_port|int != 2379 else '' }}"
    OWNER: etcd

    VAR_DIR: True
    client_port: 2379
    peer_port: "{{client_port|int+1}}"
    ENV:
      etcd_name: "{{NAME|replace('.','-')}}"
      etcd_advertise_client_urls: "{{advertise_client_urls|default('http://'+inventory_hostname+':'+client_port|string)}}"
      etcd_listen_client_urls: "{{listen_client_urls|default('http://'+inventory_hostname+':'+client_port|string+',http://localhost:'+client_port|string)}}"
      etcd_initial_advertise_peer_urls: "{{advertise_peer_urls|default('http://'+inventory_hostname+':'+peer_port|string)}}"
      etcd_listen_peer_urls: "{{listen_peer_urls|default('http://'+inventory_hostname+':'+peer_port|string)}}"
      etcd_data_dir: "{{VAR}}"
      etcd_initial_cluster: "{{ lookup('template', '../files/etcd/initial-cluster.j2') }}"
      etcd_initial_cluster_state: new
      etcd_initial_cluster_token: "{{TYPE}}-{{INSTANCE}}"
    #SYSTEMD_SERVICE: True
    SYSTEMD_EXEC: /usr/local/bin/etcd
    #SYSTEMD_USER: True
    SYSTEMD_START_ONLY: True
    SYSTEMD_TYPE: notify
    SYSTEMD_ENVFILE: "{{DIR}}/env"
  tasks:
  - include: tasks/compfuzor.includes type=srv
