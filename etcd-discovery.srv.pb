---
- hosts: all
  tags:
  - etcd_srv
  gather_facts: False
  vars:
    TYPE: etcd
    INSTANCE: "main-{{port}}"

    VAR_DIR: True
    ETCD_FILES:
    - envfile
    SYSTEMD_SERVICE: True

    discovery_factory: "https://discovery.etcd.io/new?"
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

      etcd_discovery: "{{discovery}}"
    ETCD_BIN: /usr/local/bin/etcd

  tasks:
  # insure `discovery`, retrieve new one if necessary
  - shell: "curl {{discovery_factory}}size={{ENV.etcd_cluster_active_size}}"
    register: discovery_new
    when: discovery is not defined
  - set_fact: discovery="{{discovery_new.stdout}}"
    when: discovery is not defined

  - set_fact: "i={{item}}"
    with_items: groups.etcd_srv
    when: "{{groups.etcd_srv[item]}} == {{ansible_hostname}}"

  - include: tasks/compfuzor.includes type=srv
