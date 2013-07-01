---
- hosts: all
  gather_facts: False
  vars_files:
  - vars/common.vars
  - vars/pkgs.vars
  vars:
  - ECLIPSE_URL: http://mirror.cc.columbia.edu/pub/software/eclipse/technology/epp/downloads/release/kepler/R/eclipse-standard-kepler-R-linux-gtk-x86_64.tar.gz
  - ECLIPSE_FILE: eclipse-standard-kepler-R-linux-gtk-x86_64.tar.gz
  tasks:
  - apt: pkg=$item state=$APT_INSTALL
    with_items: $DEVEL_JAVA
  - get_url: url={{ECLIPSE_URL}} dest=/usr/src/{{ECLIPSE_FILE}}
  - shell: chdir=/usr/src tar -xvzf {{ECLIPSE_FILE}}
