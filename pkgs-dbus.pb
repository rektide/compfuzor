---
# utilities for inspecting and debugging dbus systems
- hosts: all
  gather_facts: false
  vars_files:
  - vars/common.vars
  vars:
    PKGS:
    - dbus
    - mdbus2
    - d-feet
    - bustle
  tasks:
  - apt: pkg={{item}} state={{APT_INSTALL}}
    with_items: {{PKGS}}
