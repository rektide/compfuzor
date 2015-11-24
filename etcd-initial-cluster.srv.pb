---
- hosts: all
  tags:
  - etcd_srv
  gather_facts: False
  vars:
    TYPE: etcd
    INSTANCE: main
    SUBINSTANCE: "{{inventory_hostname}}{{ '-'+client_port|string if client_port|int != 4001 else '' }}"
    OWNER: etcd

    VAR_DIR: True
    client_port: 4001
    #peer_port: 7001
    peer_port: "{{client_port|int+3000}}"
    ENV:
      etcd_name: "{{name|default(TYPE + '-' + INSTANCE)}}"
      etcd_advertise_client_urls: "{{advertise_client_urls|default('http://'+inventory_hostname+':'+client_port|string)}}"
      etcd_listen_client_urls: "{{listen_client_urls|default('http://'+inventory_hostname+':'+client_port|string)}}"
      etcd_advertise_peer_urls: "{{advertise_peer_urls|default('http://'+inventory_hostname+':'+peer_port|string)}}"
      etcd_listen_peer_urls: "{{listen_peer_urls|default('http://'+inventory_hostname+':'+peer_port|string)}}"
      etcd_cluster_active_size: "{{cluster_active_size|default(3)}}"
      etcd_data_dir: "{{VAR}}"

      etcd_initial_cluster: "{{ lookup('template', '../files/etcd/initial-cluster.j2') }}"
      #etcd_initial_cluster: "{% set comma = joiner(',') %}{% for h in range(play_hosts|length) %}{{ comma() }}{{play_hosts[h].name|default(TYPE+'-'+INSTANCE+'-'+play_hosts[h]+('-'+hostvars[play_hosts[h]].client_port if hostvars[play_hosts[h]].client_port|default(4001)|int != 4001 else ''))}}=http://{{play_hosts[h]}}:{{hostvars[play_hosts[h]]['peer_port']|default(vars['peer_port']|string)}}{% endfor %}"
      etcd_initial_cluster_state: new
    SYSTEMD_SERVICE: True
    SYSTEMD_EXEC: /usr/local/bin/etcd
    SYSTEMD_USER: True
  tasks:
  - include: tasks/compfuzor.includes type=srv
