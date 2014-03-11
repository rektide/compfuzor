---
- hosts: all
  gather_facts: False
  vars:
    TYPE: sbt
    INSTANCE: "0.13.1"
    SBT_DEB: "http://repo.scala-sbt.org/scalasbt/sbt-native-packages/org/scala-sbt/sbt/0.13.1/sbt.deb"
    TARGET: "{{SRCS_DIR}}/sbt-{{INSTANCE}}.deb"
  vars_files:
  - vars/common.vars
  tasks:
  - get_url: url="{{SBT_DEB}}" dest="{{TARGET}}"
  - shell: dpkg -i "{{TARGET}}"
