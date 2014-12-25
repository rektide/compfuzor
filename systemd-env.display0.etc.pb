---
- hosts: all
  gather_facts: False
  vars:
    TYPE: systemd-env-display0
    INSTANCE: main
  tasks:
  - file: path="/etc/systemd/system/user@.service.d/" state=directory mode=755 owner=root group=root
  - copy: content="DefaultEnvironment=DISPLAY=:0" dest="/etc/systemd/system/user@.service.d/display0.conf" mode=444 owner=root group=root
