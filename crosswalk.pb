---
- hosts: all
  gather_facts: False
  vars:
    TYPE: crosswalk
    INSTANCE: latest
    DEB: https://download.01.org/crosswalk/releases/crosswalk/linux/deb/canary/latest/crosswalk_15.44.377.0-1_amd64.deb 
