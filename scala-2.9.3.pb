---
- hosts: all
  gather_facts: False
  vars:
    scala_ver: 2.9.3
    scala_base_url: http://www.scala-lang.org/files/archive/
    scala_deb: "scala-{{scala_ver}}.deb"
  vars_files:
  - vars/common.vars
  - vars/src.vars
  tasks:
  - get_url: url={{scala_base_url}}{{scala_deb}} dest={{SRCS_DIR}}/{{scala_deb}}
  - shell: dpkg -i {{SRCS_DIR}}/{{scala_deb}}
    sudo: True
