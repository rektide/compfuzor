---
- hosts: all
  tags:
  - source
  gather_facts: False
  vars:
    TYPE: openwrt
    INSTANCE: git
    REPO: https://github.com/mirrors/openwrt.git
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - git: repo=git://nbd.name/packages.git dest={{DIR}}/feeds/packages
  - file: src=files/openwrt/feeds.conf.default dest={{DIR}}/feeds.conf.default # ran after git repo is checked out
  #- shell: chdir={{DIR} ./scripts/feeds update -a  # BROKEN have not install prereqs yet.
  #- shell: chdir={{DIR}} ./scripts/feeds install -a  # BROKEN have not install prereqs yet.
- hosts: all
  tags:
  - packages
  - root
  vars:
    deps: 
    - make
    - gcc
    - g++
    - libncurses5-dev
    - zlib1g-dev
    - gawk
    - gettext
    - xsltproc
    - libssl-dev
  vars_files:
  - vars/common.vars
  tasks:
  - apt: state=${APT_INSTALL} pkg=${item}
    with_items: ${deps}
    only_if: not ${APT_BYPASS}

