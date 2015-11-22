---
- hosts: all
  gather_facts: False
  vars:
    TYPE: openwrt
    INSTANCE: git
    REPO: https://github.com/openwrt/openwrt
    BINS:
    - name: "build-feeds"
      run: True
  tasks:
  - include: tasks/compfuzor.includes type=src
