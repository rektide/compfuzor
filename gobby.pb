---
- hosts: all
  gather_facts: False
  vars_files:
  - vars/common.vars
  vars:
  - PACKAGES:
    - gobby-0.5
    - infinoted
  handlers:
  - include: handlers.yml
  tasks:
  - apt: state=$APT_INSTALL pkg=$item
    with_items: $PACKAGES
    only_if: not $APT_BYPASS
