---
- hosts: all
  gather_facts: false
  vars:
    TYPE: zfsonlinux
    INSTANCE: jessie
    APT_REPO: http://archive.zfsonlinux.org/debian
    #APT_DISTRIBUTION: "%DIST%"
    APT_DISTRIBUTION: "{{ INSTANCE }}"
    APT_TRUSTED: zfsonlinux
    PKGSET: zfsonlinux
  tasks:
  - include: tasks/compfuzor.includes type=opt
