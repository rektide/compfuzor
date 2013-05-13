---
- hosts: all
  gather_facts: False
  vars_files:
  - vars/common.vars
  - vars/pkgs.vars
  tasks:
  - apt: pkgs=$item state=$APT_INSTALL
    with_items: $DEBDEV
