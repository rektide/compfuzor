---
- hosts: all
  gather_facts: False
  vars:
    TYPE: openvswitch
    INSTANCE: main
    PKGS:
    - openvswitch-common
    - openvswitch-dbg
    - openvswitch-ipsec
    - openvswitch-pki
    - openvswitch-switch
    - openvswitch-test
    - openvswitch-vtep
    - python-openvswitch
  tasks:
  - include: tasks/compfuzor.includes
