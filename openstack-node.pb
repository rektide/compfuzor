---
- hosts: all
  sudo: True
  gather_facts: False
  tags:
  - packages
  - root
  vars_files:
  - vars/common.vars
  - vars/pkgs.vars
  sudo: True
  tasks:
  - apt: pkg=${items} state=${APT_INSTALL}
    with_items: ${OPENSTACK_NODE}
    only_if: not ${APT_BYPASS}
