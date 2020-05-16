---
- hosts: all
  vars:
    TYPE: namespaced-openvpn
    INSTANCE: git
    REPO: https://github.com/slingamn/namespaced-openvpn
  tasks:
  - include: tasks/compfuzor.includes type=src
