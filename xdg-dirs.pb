---
- hosts: all
  gather_facts: False
  vars:
    NAME: xdg-dirs
  tasks:
  - template: src=files/xdg-dirs/user-dirs.defaults dest=/etc/xdg/user-dirs.defaults
