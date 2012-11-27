---
- hosts: all
  sudo: True
  vars:
    src=files/apt-repos/sources.list.d
    dest=/etc/apt/sources.list.d
  tasks:
  - copy: src=${src}/mate.list dest=${dest}/source.list.d/mate.list
