---
- hosts: all
  sudo: True
  tasks:
  - copy: src=files/mate.list dest=/etc/apt/source.list.d/
