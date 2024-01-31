---
- hosts: all
  vars:
    TYPE: ryzen_smu
    INSTANCE: git
    REPO: https://github.com/leogx9r/ryzen_smu
  tasks:
    - include: tasks/compfuzor.includes type=src
