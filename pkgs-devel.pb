---
- hosts: all
  gather_facts: False
  vars_files:
  - vars/common.vars
  - vars/pkgs.vars
  tasks:
  - apt: pkg=$item state=$APT_INSTALL
    with_items: $DEVEL
