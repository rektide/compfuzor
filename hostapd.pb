---
- hosts: all
  vars:
    TYPE: hostapd
    INSTANCE: main
    SUBINSTANCE: wlan0
    ETC:
    - hostapd.conf
    LINKS:
      run/hostapd: /var/run/hostapd
    PIDFILE: True
    SYSTEMD_EXEC: /usr/sbin/hostapd -P {{PIDFILE}} -C {{ETC}}/hostapd.conf
  tasks:
  - includes: tasks/compfuzor.includes
  
