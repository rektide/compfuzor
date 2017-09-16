---
- hosts: all
  vars:
    TYPE: strongswan
    INSTANCE: main
    ETC_FILES:
    - strongswan.conf
    - ipsec.conf
    - ipsec.secrets
    ETC_DIRS:
    - charon
    - cacerts
    SYSTEMD_EXEC: "/usr/sbin/ipsec start --nofork --conf={{ETC}}/ipsec.conf"
    SYSTEMD_RELOAD: /usr/bin/ipsec reload
    SYSTEMD_STANDARD_OUTPUT: syslog
    SYSTEMD_RESTART: on-abnormal
    SYSTEMD_DESCRIPTION: strongSwan IPsec IKEv2 daemon
  tasks:
  - include: tasks/compfuzor.includes type=srv
