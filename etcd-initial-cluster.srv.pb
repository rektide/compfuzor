---
- hosts: all
  tags:
  - etcd_srv
  vars:
    TYPE: etcd
    INSTANCE: main
    SUBINSTANCE: "{{inventory_hostname|replace('.', '-')}}{{ '-'+client_port|string if client_port|int != 2379 else '' }}"
    OWNER: etcd

    VAR_DIRS:
    - data
    - wal
    client_port: 2379
    peer_port: "{{client_port|int+1}}"
    ENV:
      etcd_name: "{{NAME|replace('.','-')}}"
      # TODO advertise others
      etcd_advertise_client_urls: "{{advertise_client_urls|default('http://'+inventory_hostname+':'+client_port|string)}}"
      # TODO listen's must be ip address!
      etcd_listen_client_urls: "{{listen_client_urls|default('http://'+inventory_hostname+':'+client_port|string)}}"
      etcd_listen_peer_urls: "{{listen_peer_urls|default('http://'+inventory_hostname+':'+peer_port|string)}}"
      etcd_initial_advertise_peer_urls: "{{advertise_peer_urls|default('http://'+inventory_hostname+':'+peer_port|string)}}"
      etcd_cluster_active_size: "{{cluster_active_size|default(3)}}"
      etcd_data_dir: "{{VAR}}/data"
      etcd_wal_dir: "{{VAR}}/wal"

      etcd_initial_cluster: "{{ lookup('template', '../files/etcd/initial-cluster.j2') }}"
      #etcd_initial_cluster: "{% set comma = joiner(',') %}{% for h in range(play_hosts|length) %}{{ comma() }}{{play_hosts[h].name|default(TYPE+'-'+INSTANCE+'-'+play_hosts[h]+('-'+hostvars[play_hosts[h]].client_port if hostvars[play_hosts[h]].client_port|default(2380)|int != 2380 else ''))}}=http://{{play_hosts[h]}}:{{hostvars[play_hosts[h]]['peer_port']|default(vars['peer_port']|string)}}{% endfor %}"
      etcd_initial_cluster_state: new
      etcd_initial_cluster_token: "{{TYPE}}-{{INSTANCE}}"
      etcd_heartbeat_interval: 750
      etcd_election_timeout: 4000
      etcd_max_snapshots: 5
      etcd_max_wals: 20
      etcd_cors: ""
    SYSTEMD_SERVICE: True
    SYSTEMD_EXEC: /usr/local/bin/etcd
    SYSTEMD_USER: True
    SYSTEMD_PERMISSION_START_ONLY: True
    #SYSTEMD_ENVFILE: "{{DIR}}/env"
    SYSTEMD_TYPE: notify
  tasks:
  - include: tasks/compfuzor.includes type=srv
