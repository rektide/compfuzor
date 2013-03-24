---
- hosts: all
  gather_facts: False
  vars_files:
  - vars/common.vars
  - vars/pkgs.vars
  vars:
    BIN:
    - isostamp
  tasks:
  - apt: pkg=$item state=$APT_INSTALL
    with_items: $BASE
  - apt: pkg=$item state=$APT_INSTALL
    with_items: $WORKSTATION
  - copy: src=files/pkgs/$item dest=/usr/local/bin/$item mode=755
    with_items: $BIN
