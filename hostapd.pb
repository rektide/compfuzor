---
- hosts: all
  vars:
    TYPE: hostapd
    INSTANCE: main
    SUBINSTANCE: wlan0
    ETC:
    - hostapd.conf
    PIDFILE: True
    SYSTEMD_EXEC: /usr/sbin/hostapd -P {{PIDFILE}} -C {{ETC}}/hostapd.conf
    bridge: "hostapd-{{SUBINSTANCE}}"
    group: adm # admin group
    passphrase: "alacazam"
  tasks:
  - includes: tasks/compfuzor.includes
  
