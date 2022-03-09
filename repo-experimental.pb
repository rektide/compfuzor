---
- hosts: all
  become: True
  tags:
  - packages
  - root
  vars:
    NAME: debian-experimental
    APT_REPO: http://deb.debian.org/debian
    APT_DISTRIBUTION: experimental
    APT_PIN: "release a=experimental"
    APT_PIN_PRIORITY: 200
    APT_TRUST: false # assume we have debian keys
  tasks:
  - include: tasks/compfuzor/apt.tasks
