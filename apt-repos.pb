---
- hosts: all
  sudo: True
  gather_facts: False
  vars:
    src: files/apt-repos/sources.list.d
    dest: /etc/apt/sources.list.d
    REPOS:
    #- debian.unstable
    #- debian.testing
    #- emdebian.unstable
    #- mate
    - prosody
    - google
    - google.testing
  tasks:
  - copy: src=${src}/${item}.list dest=${dest}/${item}.list
    with_items: $REPOS
