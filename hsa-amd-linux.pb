---
- hosts: all
  vars:
    TYPE: hsa-amd-linux
    INSTANCE: git
    REPO: https://github.com/HSAFoundation/HSA-Drivers-Linux-AMD
  tasks:
  - include: tasks/compfuzor.includes type=src
  - shell: "dpkg -i $(ls \"{{DIR}}/kfd-*/ubuntu/*deb|grep -v linux)"
