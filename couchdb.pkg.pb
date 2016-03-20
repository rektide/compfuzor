---
- hosts: all
  vars:
    TYPE: couchdb
    INSTANCE: main
    APT_REPO: http://ppa.launchpad.net/couchdb/stable/ubuntu
    APT_DISTRIBUTION: "{{UBUNTU_DISTRIBUTION}}"
  tasks:
  - include: tasks/compfuzor.includes type=pkg
