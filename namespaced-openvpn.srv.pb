---
- hosts: all
  vars:
    TYPE: namespaced-openvpn
    INSTANCE: main
    ETC_DIR: True
    # 'config' file not included

    # configuration based off of openvpn-client@.service, with hope
    opt: "/opt/namespaced-openvpn-git"
    SYSTEMD_UNITS:
      After: network-online.target
      Wants: network-online.target
    SYSTEMD_EXEC: "{{opt}}/namespaced-openvpn --config {{ETC}}/config --auth-user-pass {{ETC}}/cred"
    SYSTEMD_SERVICES:
      Type: notify
      WorkingDirectory: "{{DIR}}"
      LimitNPROC: 10
      #CapabilityBoundingSet=CAP_IPC_LOCK CAP_NET_ADMIN CAP_NET_RAW CAP_SETGID CAP_SETUID CAP_SYS_CHROOT CAP_DAC_OVERRIDE
      PrivateTmp: True
      ProtectSystem: True
      ProtectHome: True
      KillMode: process
    SYSTEMD_INSTALLS:
      WantedBy: multi-user.target
  tasks:
  - include: tasks/compfuzor.includes type=srv
