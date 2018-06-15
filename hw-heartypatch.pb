- hosts: all
  vars:
    TYPE: hw-heartypatch
    INSTANCE: git
    REPO: https://github.com/Protocentral/protocentral_heartypatch
  tasks:
  - include: tasks/compfuzor.includes type=src
