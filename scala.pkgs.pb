---
- hosts: all
  vars:
    TYPE: scala
    INSTANCE: debian
    APT_REPO: http://dl.bintray.com/sbt/debian
    APT_COMPONENT: "/"
  tasks:
  - include: tasks/compfuzor.includes type=pkg
