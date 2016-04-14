---
- hosts: all
  vars:
    TYPE: bluez
    INSTANCE: git
    REPO: https://git.kernel.org/pub/scm/bluetooth/bluez.git
  tasks:
  - include: tasks/compfuzor.includes type=src
