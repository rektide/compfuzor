---
- hosts: all
  vars:
    TYPE: hsa-runtime-amd
    INSTANCE: git
    REPO: https://github.com/HSAFoundation/HSA-Runtime-AMD
    LINK:
      "/opt/hsa": "{{DIR}}"
  tasks:
  - include: tasks/compfuzor.includes type=src
