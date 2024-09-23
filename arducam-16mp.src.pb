---
- hosts: all
  vars:
    TYPE: arducam-16mp
    INSTANCE: git
    REPO: https://github.com/ArduCAM/IMX519_AK7375
  tasks:
    - include: tasks/compfuzor.includes type=src
