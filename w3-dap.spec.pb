---
- hosts: all
  gather_facts: False
  vars:
    NAME: w3-dap
    HG_REPO: https://dvcs.w3.org/hg/dap
  tasks:
  - include: tasks/compfuzor.includes type=src
