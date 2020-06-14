---
- hosts: all
  vars:
    TYPE: k3c
    INSTANCE: main
    GROUP: adm
    LINKS:
    - key: "{{ETC}}/{{TYPE}}.toml"
      value: "{{ENV.K3C_CONFIG}}"
      force: True
    - key: "{{RUN}}/{{TYPE}}.sock"
      value: "{{ENV.K3C_ADDRESS}}"
      force: True
    - key: "{{VAR}}/{{TYPE}}.state"
      value: "{{ENV.K3C_STATE}}"
      force: True
    VAR_DIRS: True
    RUN_DIRS: True

    k3c_config: "{{ETC}}/{{NAME}}.toml"
    k3c_address: "{{RUN}}/{{NAME}}.sock"
    k3c_root: "{{VAR}}"
    k3c_state: "{{RUN}}/{{NAME}}.state"
    k3c_bridge_name: "k3{{INSTANCE|default(NAME)}}"
    k3c_bridge_cidr: "172.18.0.0/16"
    k3c_bootstrap_image: "docker.io/rancher/k3c:v0.2.1"
    k3c_bootstrap_skip: "false"
    #k3c_cni_bIN: ""
    #k3c_cni_netconf: ""
    k3c_sandbox_image: "docker.io/rancher/pause:3.1"
    k3c_socket_gid: "{{GROUP}}"
    k3c_socket_uid: 0
    ENV:
      #K3C_CONFIG: "{{k3c_config}}"
      K3C_ADDRESS: "{{k3c_address}}"
      K3C_ROOT: "{{k3c_root}}"
      K3C_STATE: "{{k3c_state}}"
      K3C_BRIDGE_NAME: "{{k3c_bridge_name}}"
      K3C_BRIDGE_CIDR: "{{k3c_bridge_cidr}}"
      K3C_BOOTSTRAP_IMAGE: "{{k3c_bootstrap_image}}"
      K3C_BOOTSTRAP_SKIP: "{{k3c_bootstrap_skip}}"
      #K3C_CNI_BIN: ""
      #K3C_CNI_NETCONF: ""
      K3C_SANDBOX_IMAGE: "{{k3c_sandbox_image}}"
      #K3C_SOCKET_GID: "{{k3c_socket_gid}}"
      #K3C_SOCKET_UID: "{{k3c_socket_uid}}"

    SYSTEMD_UNITS:
      #After: network.target
      Description: "{{ NAME }}"
    SYSTEMD_EXEC: "/usr/local/bin/k3c daemon"
    SYSTEMD_SERVICES:
      EnvironmentFile: "{{DIR}}/env"
      Restart: always
      RestartSec: 90s
      RuntimeDirectory: "{{NAME}}"
      Group: "{{GROUP}}"
    SYSTEMD_INSTALLS:
      #Alias: k3c.service
      #WantedBy: multi-user.target
  tasks:
  - include: tasks/compfuzor.includes type=srv
